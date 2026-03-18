<#
.SYNOPSIS
Retrieves network prefix information from NetBox based on optional filter criteria.

.DESCRIPTION
This function queries the NetBox API for network prefixes using optional filters.
It returns detailed information including custom fields, optional DNS name resolution
for the default gateway, and tenant/mandant context resolved via the related site.

For each returned prefix, the function may perform additional lookups:
- If a default gateway is defined (custom_fields.default_gateway.id), the function queries
  /api/ipam/ip-addresses/{id}/ via Get-IpAddressInformation to return DefaultGatewayIpAddress
  and DnsName.
- If a site reference is available (scope.id), the function queries /api/dcim/sites/{id}/
  via Get-NetboxSiteInformation to return ValuemationSiteMandant.

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

.PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER Filter
A hashtable of query parameters to filter the network prefixes (e.g., @{ site = "muc" }).
Supports multi-value filters by repeating the same query parameter
(e.g., @{ cf_domain = @("test.mtu.corp","de.mtu.corp") }).

.OUTPUTS
Array of PSCustomObjects - Each object contains:
- Id
- NetworkName
- Description
- DHCPType
- Domain
- ADSitesAndServicesTicketUrl
- SiteId
- Site
- DefaultGatewayId
- DefaultGatewayIpAddress (only if DefaultGatewayId is present)
- DnsName (only if DefaultGatewayId is present)
- ValuemationSiteMandant (only if SiteId is present)

.EXAMPLE
Get-NetworkInfo -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" -Filter @{ site = "muc"; cf_domain = @("test.mtu.corp", "de.mtu.corp") }
#>
function Get-NetworkInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory=$true)]
        [string]$NetboxApiKey,

        [hashtable]$Filter
    )

    $headers = @{ "Authorization" = "Token $NetboxApiKey" }


    $queryString = $null
    if ($Filter -and $Filter.Count -gt 0) {
        $queryParams = foreach ($key in $Filter.Keys) {
            $val = $Filter[$key]

            if ($null -eq $val) { continue }

            if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                foreach ($item in $val) {
                    if ($null -ne $item) {
                        "$([uri]::EscapeDataString($key))=$([uri]::EscapeDataString([string]$item))"
                    }
                }
            } else {
                "$([uri]::EscapeDataString($key))=$([uri]::EscapeDataString([string]$val))"
            }
        }

        if ($queryParams) {
            $queryString = ($queryParams -join '&')
        }
    }

    $url = "$NetboxBaseUrl/api/ipam/prefixes/?$queryString"

    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop

    $networkInfoArray = @()

    foreach ($network in $response.results) {
        $networkInfo = @{
            Id = $network.id
            NetworkName = $network.prefix
            Description = $network.description
            DHCPType = $network.custom_fields.dhcp_type
            Domain = $network.custom_fields.domain
            ADSitesAndServicesTicketUrl = $network.custom_fields.ad_sites_and_services_ticket_url
            SiteId = $network.scope.id
            Site = $network.scope.name
            DefaultGatewayId = $network.custom_fields.default_gateway.id
        }

        if($networkInfo.DefaultGatewayId) {
            $gatewayInfo = Get-IpAddressInformation -NetboxBaseUrl $NetboxBaseUrl -NetboxApiKey $NetboxApiKey -IpAddressId $networkInfo.DefaultGatewayId

            $networkInfo["DnsName"] = $gatewayInfo.DnsName
            $networkInfo["DefaultGatewayIpAddress"] = $gatewayInfo.IpAddress
        }

        if($networkInfo.SiteId) {
            $siteInfo = Get-NetboxSiteInformation -NetboxBaseUrl $NetboxBaseUrl -NetboxApiKey $NetboxApiKey -SiteId $networkInfo.SiteId

            $networkInfo["ValuemationSiteMandant"] = $siteInfo.ValuemationSiteMandant
        }

        $networkInfoArray += New-Object PSObject -Property $networkInfo
    }

    return $networkInfoArray
}

<#
.SYNOPSIS
Retrieves IP address objects from NetBox with precise filtering.

.DESCRIPTION
Queries the NetBox API (/api/ipam/ip-addresses/) with an optional filter hashtable.
Returns for each entry exactly: Id, IpAddress (host part), Status, and DnsName.
Supports multi-value filters by repeating the same query parameter (e.g., @{ status = @('active','reserved') }).

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

.PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER Filter
Hashtable of query parameters to filter IP addresses exactly (e.g., @{ address = "10.10.10.1"; status = "active" }).
Multi-values are supported via arrays: @{ status = @("active","reserved") }.

.OUTPUTS
Array of PSCustomObjects with properties: Id, IpAddress, Status, DnsName.

.EXAMPLE
Find-IpAddresses -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" `
    -Filter @{ status = @("active","reserved") }

.EXAMPLE
Find-IpAddresses -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" `
    -Filter @{ address = "10.10.10.1" }
#>
function Find-IpAddresses {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$NetboxApiKey,

        [hashtable]$Filter
    )

    $headers = @{ "Authorization" = "Token $NetboxApiKey" }
    $baseEndpoint = "$NetboxBaseUrl/api/ipam/ip-addresses/"

    $queryString = $null
    if ($Filter -and $Filter.Count -gt 0) {
        $queryParams = foreach ($key in $Filter.Keys) {
            $val = $Filter[$key]
            if ($null -eq $val) { continue }

            if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                foreach ($item in $val) {
                    if ($null -ne $item) {
                        "$([uri]::EscapeDataString($key))=$([uri]::EscapeDataString([string]$item))"
                    }
                }
            }
            else {
                "$([uri]::EscapeDataString($key))=$([uri]::EscapeDataString([string]$val))"
            }
        }

        if ($queryParams) {
            $queryString = ($queryParams -join '&')
        }
    }

    $url = if ($queryString) { "$baseEndpoint`?$queryString" } else { $baseEndpoint }


    $ipInfoArray = @()
    $nextUrl = $url

    try {
        while ($null -ne $nextUrl -and $nextUrl -ne '') {
            $response = Invoke-RestMethod -Uri $nextUrl -Headers $headers -Method Get -ErrorAction Stop

            foreach ($ip in $response.results) {
                $hostIp = $null
                if ($ip.address) {
                    $hostIp = ($ip.address -split '/')[0]
                }

                $obj = [PSCustomObject]@{
                    Id                 = $ip.id
                    IpAddress          = $hostIp
                    Status             = $ip.status.value
                    DnsName            = $ip.dns_name
                }

                $ipInfoArray += $obj
            }

            $nextUrl = $response.next
        }
    }
    catch {
        throw "Failed to retrieve IP address information from NetBox: $_"
    }

    return $ipInfoArray
}

<#
.SYNOPSIS
Retrieves gateway information including IP address, DNS name from a NetBox instance.

.DESCRIPTION
This function queries the NetBox API using a provided base URL, API token, and the ID of an IP address. It returns an object containing the IP address and DNS name.

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

.PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER IpAddressId
The ID of the default IP address in NetBox.

.OUTPUTS
PSCustomObject - Contains IpAddress, DnsName.

.EXAMPLE
Get-IpAddressInformation -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" -IpAddressId "42"
#>
function Get-IpAddressInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$NetboxApiKey,

        [Parameter(Mandatory = $true)]
        [string]$IpAddressId
    )

    $headers = @{
        "Authorization" = "Token $NetboxApiKey"
    }

    $uri = "$NetboxBaseUrl/api/ipam/ip-addresses/$IpAddressId/"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop

        if ($response) {
            $ipAddressInfo = [PSCustomObject]@{
                IpAddress = ($response.address -split "/")[0]
                DnsName   = $response.dns_name
            }

            return $ipAddressInfo
        }
        else {
            throw "No response received from NetBox."
        }
    }
    catch {
        throw "Failed to retrieve ip address information: $_"
    }
}

<#
.SYNOPSIS
Retrieves site information from NetBox by site ID.

.DESCRIPTION
Queries the NetBox API endpoint /api/dcim/sites/{id}/ and returns a compact object
containing Id, Display, Name, and the custom field 'valuemation_site_mandant'.

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

.PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER SiteId
Numeric ID of the site in NetBox.

.OUTPUTS
PSCustomObject - Contains Id, Display, Name, ValuemationSiteMandant.

.EXAMPLE
Get-NetboxSiteInformation -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" -SiteId 62

.EXAMPLE
Get-NetboxSiteInformation -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" -SiteId 62 -Verbose
#>
function Get-NetboxSiteInformation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$NetboxApiKey,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$SiteId
    )

    $headers = @{
        "Authorization" = "Token $NetboxApiKey"
        "Accept"        = "application/json"
    }

    $baseUrl = $NetboxBaseUrl.TrimEnd('/')
    $uri = "$baseUrl/api/dcim/sites/$SiteId/"

    try {
        Write-Verbose "Requesting site information from NetBox: $uri"

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop

        if (-not $response) {
            throw "No response received from NetBox."
        }

        $valuemationSiteMandant = $null
        if ($response.custom_fields -and $response.custom_fields.PSObject.Properties.Name -contains 'valuemation_site_mandant') {
            $valuemationSiteMandant = $response.custom_fields.valuemation_site_mandant
        }

        $siteInfo = [PSCustomObject]@{
            Id                    = $response.id
            Display               = $response.display
            Name                  = $response.name
            ValuemationSiteMandant = $valuemationSiteMandant
        }

        Write-Verbose "Successfully retrieved site information (Id=$($siteInfo.Id), Name=$($siteInfo.Name))."
        return $siteInfo
    }
    catch {
        throw "Failed to retrieve site information from NetBox (SiteId=$SiteId): $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Retrieves the most specific (direct) prefix(es) in NetBox that contain a given IP address or prefix.

.DESCRIPTION
Queries the NetBox /api/ipam/prefixes/ endpoint with the 'contains' filter.
All matching prefixes are collected (handling pagination). The function returns all
top level prefixes ordered by MaskLength.

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

.PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER AddressOrPrefix
The IP address (e.g., 192.0.2.5) or a CIDR (e.g., 192.0.2.0/24) that should be contained.

.OUTPUTS
PSCustomObject[] - Contains Id, Prefix, MaskLength, Domain.

.EXAMPLE
Get-PrefixesForAddress -NetboxBaseUrl "https://netbox.example.com" `
    -NetboxApiKey "abc123" -AddressOrPrefix "192.0.2.5"
#>
function Get-PrefixesForAddress {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$NetboxApiKey,

        [Parameter(Mandatory = $true)]
        [string]$AddressOrPrefix
    )

    $headers = @{
        "Authorization" = "Token $NetboxApiKey"
        "Accept"        = "application/json"
    }

    $uri = "$NetboxBaseUrl/api/ipam/prefixes/?limit=0&contains=$([uri]::EscapeDataString($AddressOrPrefix))"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -ErrorAction Stop

        $output = $response.results | ForEach-Object {
            [pscustomobject]@{
                Id         = $_.id
                MaskLength = [int](($_.prefix -split "/")[1])
                Prefix     = $_.prefix
                Domain     = $_.custom_fields.domain
            } | Sort-Object -Property MaskLength -Descending
        }

        return $output
    }
    catch {
        throw "Failed to retrieve containing prefix for '$AddressOrPrefix': $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Updates a network prefix in NetBox using the provided update data.

.DESCRIPTION
This function sends a PATCH request to the NetBox API to update a specific network prefix identified by its ID. The update data is passed as a hashtable and converted to JSON.

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

.PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER NetworkNumber
The ID of the network prefix to update in NetBox.

.PARAMETER UpdateObject
A hashtable containing the fields and values to update in the network prefix.

.OUTPUTS
Object - The updated network prefix object returned by the NetBox API.

.EXAMPLE
Update-NetboxNetwork -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" -NetworkNumber "101" -UpdateObject @{ description = "Updated network" }
#>
function Update-NetboxNetwork {
    param(
        [Parameter(Mandatory=$true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory=$true)]
        [string]$NetboxApiKey,
        [Parameter(Mandatory=$true)]
        [string]$NetworkNumber,

        [Parameter(Mandatory=$true)]
        [hashtable]$UpdateObject

    )

    $url = "$NetboxBaseUrl/api/ipam/prefixes/$NetworkNumber/"
    $headers = @{
        "Authorization" = "Token $NetboxApiKey"
        "Content-Type"  = "application/json"
    }

    $body = $UpdateObject | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $url -Method Patch -Headers $headers -Body $body -ErrorAction Stop
        return $response
    }
    catch {
        throw "Failed to update the network information in netbox (Prefix ID: $($NetworkNumber)): $_"
    }
}

<#
.SYNOPSIS
Updates the status of a network prefix in NetBox to indicate onboarding is complete.

.DESCRIPTION
This function sets the status of a specified network prefix in NetBox to "onboarding_done_dns_dhcp" by calling the Update-NetboxNetwork function.

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

.PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER NetworkNumber
The ID of the network prefix to update in NetBox.

.OUTPUTS
String - JSON representation of the updated network prefix object.

.EXAMPLE
Update-NetboxNetworkPrefixStatusOnboardingDone -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" -NetworkNumber "101"
#>
function Update-NetboxNetworkPrefixStatusOnboardingDone {
    param (
        [Parameter(Mandatory=$true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory=$true)]
        [string]$NetboxApiKey,

        [Parameter(Mandatory=$true)]
        [string]$NetworkNumber
    )

    $updateObject = @{
        "status" = "onboarding_done_dns_dhcp"
    }

    $response = Update-NetboxNetwork -NetworkNumber $NetworkNumber -UpdateObject $updateObject -NetboxApiKey $NetboxApiKey -NetboxBaseUrl $NetboxBaseUrl

    Write-Host "    Updated status of network in NetBox to onboarding done." -ForegroundColor Green
    return $response | ConvertTo-Json
}


<#
.SYNOPSIS
Updates a NetBox IP address using the provided update data.

.DESCRIPTION
This function sends a PATCH request to the NetBox API to update a specific IP address identified by its ID.
The update data is passed as a hashtable and converted to JSON.

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

.PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER IpAddressId
The ID of the IP address to update in NetBox.

.PARAMETER UpdateObject
A hashtable containing the fields and values to update in the IP address object.

.OUTPUTS
Object - The updated IP address object returned by the NetBox API.

.EXAMPLE
Update-NetboxIPAddress -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" -IpAddressId "2954" -UpdateObject @{ description = "Updated IP address"; dns_name = "host01.example.com" }
#>
function Update-NetboxIPAddress {
    param(
        [Parameter(Mandatory=$true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory=$true)]
        [string]$NetboxApiKey,

        [Parameter(Mandatory=$true)]
        [string]$IpAddressId,

        [Parameter(Mandatory=$true)]
        [hashtable]$UpdateObject
    )

    $url = "$NetboxBaseUrl/api/ipam/ip-addresses/$IpAddressId/"
    $headers = @{
        "Authorization" = "Token $NetboxApiKey"
        "Content-Type"  = "application/json"
    }

    $body = $UpdateObject | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $url -Method Patch -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "    IP address updated successfully (ID: $IpAddressId)." -ForegroundColor Green
        return $response
    }
    catch {
        Write-Host "    Failed to update IP address (ID: $IpAddressId). $_" -ForegroundColor Red
        throw "Failed to update the IP address in NetBox (IPAddress ID: $($IpAddressId)): $_"
    }
}

<#
.SYNOPSIS
Adds a journal entry in NetBox for a specific Prefix or IP Address.

.DESCRIPTION
This function posts a journal entry to the NetBox API endpoint /api/extras/journal-entries/
for a specified object (Prefix or IP Address). It uses the Django content type strings
(ipam.prefix or ipam.ipaddress) to associate the entry with the target object.

.PARAMETER NetboxBaseUrl
The base URL of the NetBox instance (e.g., https://netbox.example.com).

PARAMETER NetboxApiKey
The API token used to authenticate with the NetBox API.

.PARAMETER TargetType
The type of target object for the journal entry. Supported values: Prefix, IPAddress.

.PARAMETER TargetId
The ID of the target object (e.g., Prefix ID or IP Address ID in NetBox).

.PARAMETER Message
The journal entry text to write.

.PARAMETER Kind
Optional journal kind/classification (e.g., default, info, warning, success, danger). If not specified, defaults to 'default' (subject to NetBox version).

.OUTPUTS
PSCustomObject - The created journal entry as returned by NetBox.

.EXAMPLE
Add-NetboxJournalEntry -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" `
    -TargetType Prefix -TargetId 101 -Message "Onboarding completed by automation."

.EXAMPLE
Add-NetboxJournalEntry -NetboxBaseUrl "https://netbox.example.com" -NetboxApiKey "abc123" `
    -TargetType IPAddress -TargetId 42 -Message "Default gateway DNS validated." -Kind info

.NOTES
- Requires API permissions to create journal entries.
#>
function Add-NetboxJournalEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NetboxBaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$NetboxApiKey,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Prefix', 'IPAddress')]
        [string]$TargetType,

        [Parameter(Mandatory = $true)]
        [int]$TargetId,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('default','info','warning','success','danger')]
        [string]$Kind = 'default'
    )

    $contentTypeMap = @{
        'Prefix'    = 'ipam.prefix'
        'IPAddress' = 'ipam.ipaddress'
    }

    $headers = @{
        'Authorization' = "Token $NetboxApiKey"
        'Content-Type'  = 'application/json'
    }

    $endpoint = "$NetboxBaseUrl/api/extras/journal-entries/"

    if ([string]::IsNullOrWhiteSpace($NetboxBaseUrl)) {
        throw "NetboxBaseUrl must not be empty."
    }
    if ([string]::IsNullOrWhiteSpace($NetboxApiKey)) {
        throw "NetboxApiKey must not be empty."
    }
    if ($TargetId -le 0) {
        throw "TargetId must be a positive integer."
    }
    if ([string]::IsNullOrWhiteSpace($Message)) {
        throw "Message must not be empty."
    }

    $assignedObjectType = $contentTypeMap[$TargetType]
    if (-not $assignedObjectType) {
        throw "Unsupported TargetType '$TargetType'."
    }

    $bodyObject = [ordered]@{
        assigned_object_type = $assignedObjectType
        assigned_object_id   = $TargetId
        comments             = $Message
        kind                 = $Kind
    }

    $bodyJson = $bodyObject | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $bodyJson -ErrorAction Stop | Out-Null
    }
    catch {
        throw "Failed to create journal entry in NetBox for $TargetType (ID $TargetId): $_"
    }
}
