<#
.SYNOPSIS
Updates the Jira ticket link custom field for a network prefix in NetBox.

.DESCRIPTION
This function sets the "ad_sites_and_services_ticket_url" custom field of a specified network prefix in NetBox to the provided Jira ticket URL by calling the Update-NetboxNetwork function.

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

.PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER NetworkNumber
The ID of the network prefix to update in NetBox.

.PARAMETER jiraTicketLink
The URL of the Jira ticket to associate with the network prefix.

.OUTPUTS
String - JSON representation of the updated network prefix object.

.EXAMPLE
Update-NetboxNetworkJiraTicketLink -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" -NetworkNumber "101" -jiraTicketLink "https://jira.example.com/browse/NET-123"
#>
function Update-NetboxNetworkJiraTicketLink {
    param (
        [Parameter(Mandatory=$true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory=$true)]
        [string]$NetboxApiKey,

        [Parameter(Mandatory=$true)]
        [string]$NetworkNumber,

        [Parameter(Mandatory=$true)]
        [string]$jiraTicketLink
    )

    $updateObject = @{
        "custom_fields" = @{
            "ad_sites_and_services_ticket_url" = $jiraTicketLink
        }
    }

    $response = Update-NetboxNetwork -NetworkNumber $NetworkNumber -UpdateObject $updateObject -NetboxApiKey $NetboxApiKey -NetboxBaseUrl $NetboxBaseUrl

    Write-Host "    Updated jira ticket field of network in NetBox." -ForegroundColor Green
    return $response | ConvertTo-Json
}

<#
.SYNOPSIS
Creates a Jira ticket to request reverse DNS zone creation and AD Sites and Services maintenance for a given subnet.

.DESCRIPTION
This function generates a Jira ticket with a predefined summary and description, including subnet and site details. It supports both production and development environments and uses the Jira REST API for ticket creation.

.PARAMETER JiraBaseUrl
The base URL of the Jira instance (e.g., https://jira.example.com).

.PARAMETER JiraApiKey
The API token used to authenticate with the Jira API.

.PARAMETER Subnet
The subnet in CIDR notation (e.g., "10.24.0.0/24") for which the ticket is being created.

.PARAMETER Site
The AD site associated with the subnet.

.PARAMETER ForestShortName
The forest's short name associated with the subnet.

.OUTPUTS
Object - The response from the Jira API containing the created ticket details.

.EXAMPLE
Create-ReverseZoneAndSiteAndServicesMaintainJiraTicket -JiraBaseUrl "https://jira.example.com" -JiraApiKey "abc123" -Subnet "10.24.0.0/24" -Site "MUC" -dev $false
#>
function New-ReverseZoneAndSiteAndServicesMaintainJiraTicket {
    param (
        [Parameter(Mandatory=$true)]
        [string]$JiraBaseUrl,

        [Parameter(Mandatory=$true)]
        [string]$JiraApiKey,

        [Parameter(Mandatory=$true)]
        [string]$Subnet,

        [Parameter(Mandatory=$true)]
        [string]$Site,

        [Parameter(Mandatory=$true)]
        [bool]$DnsZoneDelegated,

        [Parameter(Mandatory=$true)]
        [string]$ForestShortName
    )

    $headers = @{
        "Authorization" = "Bearer $JiraApiKey"
        "Accept"="application/json"
    }

    $summary = "DNS-Zonen pflegen - Reverse Lookup Zone anlegen / Sites und Services pflegen"

    $networkIp = $Subnet.Split('/')[0]
    $networkMask = $Subnet.Split('/')[1]

    if ($DnsZoneDelegated) { $dnsZoneDelegatedMapped = "vorhanden" } else { $dnsZoneDelegatedMapped = "nicht vorhanden" }

    $body = @{
        fields = @{
            project = @{ key = "TCO" }
            summary = $summary
            description = "||Subnetz ID||Prefix ||Forest (MTU, MTUDEV, MTUGOV, MTUCHINA)||Site Zuordnung||Windows/Linux||Delegation ||
|{color:#0747a6}Beispiel:
10.10.0.0{color}|{color:#0747a6}Beispiel:
/16{color}|{color:#0747a6}Beispiel:
MTU{color}|{color:#0747a6}Beispiel:
MUC{color}|{color:#0747a6}Beispiel:
WIN{color}|{color:#0747a6}Beispiel:
vorhanden{color}|
|$($networkIp)|/$($networkMask)| $($ForestShortName) | $($Site) | unbekannt | $dnsZoneDelegatedMapped |
Confluence Doku:
[Tier0-Operations CR Ticket erstellen - Tier0-CAS-Operations - MTU Confluence (dasa.de)|https://cpwa-confluence-p.muc.mtu.dasa.de:8453/display/TCO/Tier0-Operations+CR+Ticket+erstellen]"
            issuetype = @{ name = "Story" }
            labels = @("FIPI-Abnahme-nicht-benötigt", "FIPI-Freigabe-nicht-benötigt", "Tier0-Operations")
            assignee = @{ name = "YAT5495" }
        }
    } | ConvertTo-Json -Depth 10

    try {
        $ticketCreationResponse = Invoke-RestMethod -Uri "$JiraBaseUrl/rest/api/2/issue/" -Method Post -Headers $headers -Body $body -ContentType "application/json; charset=utf-8" -ErrorAction Stop

        Write-Host "    A Jira ticket '$($ticketCreationResponse.key)' has been successfully created, facilitating the subnet's association with an AD site, the reverse zone and DNS delegation configuration." -ForegroundColor Green

        $transitionsResponse = Invoke-RestMethod -Uri "$($jiraBaseUrl)/rest/api/2/issue/$($ticketCreationResponse.key)/transitions" -Headers $headers -Method Get -ContentType "application/json; charset=utf-8"

        $commitTransition = $transitionsResponse.transitions | Where-Object { $_.name -eq "Commit" }

        $transitionBody = @{
            transition = @{
                id = $commitTransition.id
            }
        } | ConvertTo-Json -Depth 2

        Invoke-RestMethod -Uri "$JiraBaseUrl/rest/api/2/issue/$($ticketCreationResponse.key)/transitions" -Headers $headers -Method Post -Body $transitionBody -ContentType "application/json;" -ErrorAction Stop

        return $ticketCreationResponse
    }
    catch {
        throw "An error occurred while creating a jira ticket: $_"
    }
}

<#
.SYNOPSIS
Extracts the Jira ticket key from a given Jira issue URL.

.DESCRIPTION
This function uses a regular expression to parse a Jira issue URL and extract the ticket key (e.g., "ABC-123"). It throws an error if no valid key is found.

.PARAMETER JiraUrl
The full URL of the Jira issue (e.g., "https://jira.example.com/browse/ABC-123").

.OUTPUTS
String - The extracted Jira ticket key.

.EXAMPLE
Get-JiraTicketKeyFromUrl -JiraUrl "https://jira.example.com/browse/ABC-123"
#>
function Get-JiraTicketKeyFromUrl {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JiraUrl
    )

    $regexPattern = "browse/([A-Z]+-\d+)"

    if ($JiraUrl -match $regexPattern) {
        $ticketKey = $matches[1]
        return $ticketKey
    }
    else {
        throw "No valid Jira ticket key found in the provided URL ($JiraUrl)."
        return $null
    }
}

<#
.SYNOPSIS
Retrieves the current status of a Jira ticket using its key.

.DESCRIPTION
This function queries the Jira REST API to get the status of a specified ticket. It handles errors gracefully and provides detailed output if the request fails.

.PARAMETER JiraBaseUrl
The base URL of the Jira instance (e.g., https://jira.example.com).

.PARAMETER JiraApiKey
The API token used to authenticate with the Jira API.

.PARAMETER TicketKey
The key of the Jira ticket (e.g., "ABC-123").

.OUTPUTS
String - The current status of the Jira ticket.

.EXAMPLE
Check-JiraTicketStatus -JiraBaseUrl "https://jira.example.com" -JiraApiKey "abc123" -TicketKey "ABC-123"
#>
function Get-JiraTicketStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JiraBaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$JiraApiKey,

        [Parameter(Mandatory = $true)]
        [string]$TicketKey
    )

    $headers = @{
        "Authorization" = "Bearer $JiraApiKey"
    }

    try {
        $ticket = Invoke-RestMethod -Uri "$JiraBaseUrl/rest/api/2/issue/$TicketKey" -Method Get -Headers $headers -ContentType "application/json; charset=utf-8" -ErrorAction Stop

        $ticketStatus = $ticket.fields.status.name

        return $ticketStatus
    }
    catch {
        throw "An error occurred while retrieving the ticket status: $_"
    }
}

<#
.SYNOPSIS
Executes a workflow transition to set the status of a Jira issue.

.DESCRIPTION
This function queries the Jira REST API for the available transitions of a given issue,
selects the transition that leads to the desired target status, and executes it.
If the transition has a screen with required fields (e.g., "resolution"), you can pass them
via -AdditionalFields. The function handles errors gracefully and returns the new status name.

.PARAMETER JiraBaseUrl
The base URL of the Jira instance (e.g., https://jira.example.com).

.PARAMETER JiraApiKey
The API token used to authenticate with the Jira API (used as Bearer token).

.PARAMETER TicketKey
The key of the Jira ticket (e.g., "ABC-123").

.PARAMETER TargetStatus
The desired status to reach (e.g., "Done", "In Progress", "Closed").

.PARAMETER AdditionalFields
Optional hashtable of fields to set as part of the transition
(e.g., @{ resolution = @{ name = "Done" } } ).

.OUTPUTS
String - The resulting status of the Jira ticket after the transition.

.EXAMPLE
Set-JiraIssueStatus -JiraBaseUrl "https://jira.example.com" -JiraApiKey "abc123" -TicketKey "ABC-123" -TargetStatus "Done" -AdditionalFields @{ resolution = @{ name = "Done" } }
#>
function Set-JiraIssueStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JiraBaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$JiraApiKey,

        [Parameter(Mandatory = $true)]
        [string]$TicketKey,

        [Parameter(Mandatory = $true)]
        [string]$TargetStatus,

        [hashtable]$AdditionalFields
    )

    $headers = @{
        "Authorization" = "Bearer $JiraApiKey"
        "Accept" = "application/json"
    }

    try {
        $transitionsUrl = "$JiraBaseUrl/rest/api/2/issue/$TicketKey/transitions?expand=transitions.fields"
        $transitionResponse = Invoke-RestMethod -Uri $transitionsUrl -Method Get -Headers $headers -ContentType "application/json; charset=utf-8" -ErrorAction Stop

        if (-not $transitionResponse.transitions) {
            throw "No transitions returned. Check permissions ('Transition issues'), workflow, and current issue status."
        }

        $transition = $transitionResponse.transitions | Where-Object { $_.name -eq $TargetStatus } | Select-Object -First 1

        if (-not $transition) {
            throw "Target status '$TargetStatus' is not available from the current state. $( $msg -join ' | ' )"
        }

        $body = @{
            transition = @{ id = "$( $transition.id )" }
        }

        if ($AdditionalFields) {
            $body["fields"] = $AdditionalFields
        }

        $jsonBody = $body | ConvertTo-Json -Depth 10

        $postUrl = "$JiraBaseUrl/rest/api/2/issue/$TicketKey/transitions"
        $null = Invoke-RestMethod -Uri $postUrl -Method Post -Headers $headers -ContentType "application/json; charset=utf-8" -Body $jsonBody -ErrorAction Stop

        $issueUrl = "$JiraBaseUrl/rest/api/2/issue/$TicketKey"
        $issue = Invoke-RestMethod -Uri $issueUrl -Method Get -Headers $headers -ContentType "application/json; charset=utf-8" -ErrorAction Stop
        $newStatus = $issue.fields.status.name

        return $newStatus
    }
    catch
    {
        throw "An error occurred while setting the issue status for '$TicketKey' to '$TargetStatus': $_"
    }
}
