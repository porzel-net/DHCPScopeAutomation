# Wraps Jira issue creation and workflow transitions used for manual prerequisite handling.
<#
.SYNOPSIS
Wraps Jira REST operations required by the automation.

.DESCRIPTION
Handles ticket lookup, status transitions, ticket closure, and prerequisite
ticket creation so higher layers can work with business intent instead of raw REST calls.

.NOTES
Methods:
- JiraClient(credential)
- GetHeaders()
- GetTicketKeyFromUrl(jiraUrl)
- GetTicketStatus(ticketKey)
- SetTicketStatus(ticketKey, targetStatus)
- EnsureTicketClosed(jiraUrl)
- CreatePrerequisiteTicket(workItem, forestShortName, dnsZoneDelegated)

.EXAMPLE
$client = [JiraClient]::new($jiraCredential)
$client.GetTicketKeyFromUrl('https://jira.example.test/browse/TCO-7')
#>
class JiraClient {
    [string] $BaseUrl
    [AutomationCredential] $Credential

    JiraClient([AutomationCredential] $credential) {
        if ($null -eq $credential) {
            throw [System.ArgumentNullException]::new('credential')
        }

        $this.Credential = $credential
        $this.BaseUrl = $credential.Appliance.TrimEnd('/')
    }

    <#
    .SYNOPSIS
    Returns the standard REST headers for Jira.
    .OUTPUTS
    System.Collections.Hashtable
    #>
    hidden [hashtable] GetHeaders() {
        return @{
            Authorization = ('Bearer {0}' -f $this.Credential.GetPlainApiKey())
            Accept        = 'application/json'
        }
    }

    <#
    .SYNOPSIS
    Extracts the Jira key from a browse URL.
    .OUTPUTS
    System.String
    #>
    [string] GetTicketKeyFromUrl([string] $jiraUrl) {
        if ([string]::IsNullOrWhiteSpace($jiraUrl)) {
            throw [System.ArgumentException]::new('JiraUrl is required.')
        }

        $pattern = 'browse/([A-Z]+-\d+)'
        if ($jiraUrl -match $pattern) {
            return $matches[1]
        }

        throw [System.ArgumentException]::new("No valid Jira ticket key found in '$jiraUrl'.")
    }

    <#
    .SYNOPSIS
    Returns the current workflow status of a ticket.
    .OUTPUTS
    System.String
    #>
    [string] GetTicketStatus([string] $ticketKey) {
        $uri = '{0}/rest/api/2/issue/{1}' -f $this.BaseUrl, $ticketKey
        Write-Verbose -Message ("Loading Jira status for ticket '{0}'." -f $ticketKey)
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $this.GetHeaders() -ContentType 'application/json; charset=utf-8' -ErrorAction Stop
        return [string] $response.fields.status.name
    }

    <#
    .SYNOPSIS
    Moves a ticket into the requested Jira status.
    .OUTPUTS
    System.Void
    #>
    [void] SetTicketStatus([string] $ticketKey, [string] $targetStatus) {
        Write-Verbose -Message ("Setting Jira ticket '{0}' to status '{1}'." -f $ticketKey, $targetStatus)
        $transitionsUri = '{0}/rest/api/2/issue/{1}/transitions?expand=transitions.fields' -f $this.BaseUrl, $ticketKey
        $transitionResponse = Invoke-RestMethod -Uri $transitionsUri -Method Get -Headers $this.GetHeaders() -ContentType 'application/json; charset=utf-8' -ErrorAction Stop
        $transition = $transitionResponse.transitions | Where-Object { $_.name -eq $targetStatus } | Select-Object -First 1

        if ($null -eq $transition) {
            throw [System.InvalidOperationException]::new("Target status '$targetStatus' is not available for ticket '$ticketKey'.")
        }

        $body = @{
            transition = @{
                id = [string] $transition.id
            }
        } | ConvertTo-Json -Depth 10

        $postUri = '{0}/rest/api/2/issue/{1}/transitions' -f $this.BaseUrl, $ticketKey
        Invoke-RestMethod -Uri $postUri -Method Post -Headers $this.GetHeaders() -ContentType 'application/json; charset=utf-8' -Body $body -ErrorAction Stop | Out-Null
        Write-Verbose -Message ("Jira ticket '{0}' transitioned to '{1}'." -f $ticketKey, $targetStatus)
    }

    <#
    .SYNOPSIS
    Ensures that a referenced Jira ticket is closed.
    .OUTPUTS
    System.Void
    #>
    [void] EnsureTicketClosed([string] $jiraUrl) {
        $ticketKey = $this.GetTicketKeyFromUrl($jiraUrl)
        $status = $this.GetTicketStatus($ticketKey)
        Write-Verbose -Message ("Ensuring Jira ticket '{0}' is closed. Current status is '{1}'." -f $ticketKey, $status)

        if ($status -eq 'Verify') {
            $this.SetTicketStatus($ticketKey, 'Close')
            return
        }

        if ($status -ne 'Geschlossen') {
            throw [System.InvalidOperationException]::new("Jira ticket '$ticketKey' is not closed yet. Current status is '$status'. The work item is waiting on this existing ticket.")
        }
    }

    <#
    .SYNOPSIS
    Creates the Jira ticket for blocked prerequisite work.
    .OUTPUTS
    System.String
    #>
    [string] CreatePrerequisiteTicket([PrefixWorkItem] $workItem, [string] $forestShortName, [bool] $dnsZoneDelegated) {
        Write-Verbose -Message ("Creating Jira prerequisite ticket for prefix '{0}' (Forest='{1}', DelegationPresent={2})." -f $workItem.GetIdentifier(), $forestShortName, $dnsZoneDelegated)
        $delegationText = 'nicht vorhanden'
        if ($dnsZoneDelegated) {
            $delegationText = 'vorhanden'
        }

        $networkIp = $workItem.PrefixSubnet.NetworkAddress.Value
        $networkMask = $workItem.PrefixSubnet.PrefixLength

        $description = @"
||Subnetz ID||Prefix ||Forest (MTU, MTUDEV, MTUGOV, MTUCHINA)||Site Zuordnung||Windows/Linux||Delegation ||
        |$networkIp|/$networkMask| $forestShortName | $($workItem.ValuemationSiteMandant) | unbekannt | $delegationText |
Confluence Doku:
[Tier0-Operations CR Ticket erstellen - Tier0-CAS-Operations - MTU Confluence (dasa.de)|https://cpwa-confluence-p.muc.mtu.dasa.de:8453/display/TCO/Tier0-Operations+CR+Ticket+erstellen]
"@

        $body = @{
            fields = @{
                project = @{ key = 'TCO' }
                summary = 'DNS-Zonen pflegen - Reverse Lookup Zone anlegen / Sites und Services pflegen'
                description = $description
                issuetype = @{ name = 'Story' }
                labels = @('FIPI-Abnahme-nicht-benötigt', 'FIPI-Freigabe-nicht-benötigt', 'Tier0-Operations')
                assignee = @{ name = 'YAT5495' }
            }
        } | ConvertTo-Json -Depth 10

        $createUri = '{0}/rest/api/2/issue/' -f $this.BaseUrl
        $ticket = Invoke-RestMethod -Uri $createUri -Method Post -Headers $this.GetHeaders() -Body $body -ContentType 'application/json; charset=utf-8' -ErrorAction Stop

        $ticketKey = [string] $ticket.key
        if ([string]::IsNullOrWhiteSpace($ticketKey)) {
            throw [System.InvalidOperationException]::new('Jira did not return a ticket key.')
        }

        $this.SetTicketStatus($ticketKey, 'Commit')
        Write-Verbose -Message ("Created Jira prerequisite ticket '{0}' for prefix '{1}'." -f $ticketKey, $workItem.GetIdentifier())
        return '{0}/browse/{1}' -f $this.BaseUrl, $ticketKey
    }
}
