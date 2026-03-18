# Wraps Jira issue creation and workflow transitions used for manual prerequisite handling.
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

    hidden [hashtable] GetHeaders() {
        return @{
            Authorization = ('Bearer {0}' -f $this.Credential.GetPlainApiKey())
            Accept        = 'application/json'
        }
    }

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

    [string] GetTicketStatus([string] $ticketKey) {
        $uri = '{0}/rest/api/2/issue/{1}' -f $this.BaseUrl, $ticketKey
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $this.GetHeaders() -ContentType 'application/json; charset=utf-8' -ErrorAction Stop
        return [string] $response.fields.status.name
    }

    [void] SetTicketStatus([string] $ticketKey, [string] $targetStatus) {
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
    }

    [void] EnsureTicketClosed([string] $jiraUrl) {
        $ticketKey = $this.GetTicketKeyFromUrl($jiraUrl)
        $status = $this.GetTicketStatus($ticketKey)

        if ($status -eq 'Verify') {
            $this.SetTicketStatus($ticketKey, 'Close')
            return
        }

        if ($status -ne 'Geschlossen') {
            throw [System.InvalidOperationException]::new("Jira ticket '$ticketKey' is not closed. Current status: '$status'.")
        }
    }

    [string] CreatePrerequisiteTicket([PrefixWorkItem] $workItem, [string] $forestShortName, [bool] $dnsZoneDelegated) {
        $delegationText = 'nicht vorhanden'
        if ($dnsZoneDelegated) {
            $delegationText = 'vorhanden'
        }

        $networkIp = $workItem.PrefixSubnet.NetworkAddress.Value
        $networkMask = $workItem.PrefixSubnet.PrefixLength

        $description = @"
||Subnetz ID||Prefix ||Forest (MTU, MTUDEV, MTUGOV, MTUCHINA)||Site Zuordnung||Windows/Linux||Delegation ||
|$networkIp|/$networkMask| $forestShortName | $($workItem.SiteName) | unbekannt | $delegationText |
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
        return '{0}/browse/{1}' -f $this.BaseUrl, $ticketKey
    }
}
