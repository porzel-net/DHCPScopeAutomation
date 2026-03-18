<#
.SYNOPSIS
Wraps NetBox REST access and maps raw payloads to work items.

.DESCRIPTION
Provides paging, lookup, status update, and journaling operations against NetBox
while hiding endpoint details from the application layer.

.NOTES
Methods:
- NetBoxClient(credential)
- GetJsonHeaders()
- BuildQueryString(filter)
- GetPaged(relativePath, filter)
- GetIpAddressById(ipAddressId)
- GetSiteById(siteId)
- GetOpenPrefixWorkItems(environment)
- GetMostSpecificPrefixForAddress(address)
- GetIpWorkItems(environment, statuses)
- UpdatePrefixTicketUrl(prefixId, ticketUrl)
- MarkPrefixOnboardingDone(prefixId)
- UpdateIpStatus(ipId, status)
- AddJournalEntry(targetType, targetId, message, kind)
- GetPrefixUrl(prefixId)
- GetIpAddressUrl(ipAddressId)

.EXAMPLE
$client = [NetBoxClient]::new($netBoxCredential)
$client.GetOpenPrefixWorkItems([EnvironmentContext]::new('prod'))
#>
class NetBoxClient {
    [string] $BaseUrl
    [AutomationCredential] $Credential

    NetBoxClient([AutomationCredential] $credential) {
        if ($null -eq $credential) {
            throw [System.ArgumentNullException]::new('credential')
        }

        $this.Credential = $credential
        $this.BaseUrl = $credential.Appliance.TrimEnd('/')
    }

    <#
    .SYNOPSIS
    Returns the JSON headers for NetBox REST calls.
    .OUTPUTS
    System.Collections.Hashtable
    #>
    hidden [hashtable] GetJsonHeaders() {
        return @{
            Authorization = ('Token {0}' -f $this.Credential.GetPlainApiKey())
            Accept        = 'application/json'
            'Content-Type' = 'application/json'
        }
    }

    <#
    .SYNOPSIS
    Builds a NetBox query string from a filter hashtable.
    .OUTPUTS
    System.String
    #>
    hidden [string] BuildQueryString([hashtable] $filter) {
        if ($null -eq $filter -or $filter.Count -eq 0) {
            return ''
        }

        $parts = @()
        foreach ($key in $filter.Keys) {
            $value = $filter[$key]
            if ($null -eq $value) { continue }

            # NetBox accepts repeated query parameters, so enumerable values fan out into multiple key/value pairs.
            if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                foreach ($item in $value) {
                    if ($null -ne $item) {
                        $parts += '{0}={1}' -f [uri]::EscapeDataString([string] $key), [uri]::EscapeDataString([string] $item)
                    }
                }
            }
            else {
                $parts += '{0}={1}' -f [uri]::EscapeDataString([string] $key), [uri]::EscapeDataString([string] $value)
            }
        }

        return ($parts -join '&')
    }

    <#
    .SYNOPSIS
    Follows paged NetBox REST responses until all results are loaded.
    .OUTPUTS
    System.Object[]
    #>
    hidden [object[]] GetPaged([string] $relativePath, [hashtable] $filter) {
        $headers = $this.GetJsonHeaders()
        $queryString = $this.BuildQueryString($filter)
        $uri = '{0}{1}' -f $this.BaseUrl, $relativePath

        if (-not [string]::IsNullOrWhiteSpace($queryString)) {
            if ($uri.Contains('?')) {
                $uri = '{0}&{1}' -f $uri, $queryString
            }
            else {
                $uri = '{0}?{1}' -f $uri, $queryString
            }
        }

        $results = @()
        $nextUri = $uri

        while (-not [string]::IsNullOrWhiteSpace($nextUri)) {
            # Keep following NetBox pagination until the API stops returning a next link.
            $response = Invoke-RestMethod -Uri $nextUri -Method Get -Headers $headers -ErrorAction Stop
            $results += @($response.results)
            $nextUri = $response.next
        }

        return $results
    }

    <#
    .SYNOPSIS
    Loads one NetBox IP address object by id.
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    hidden [pscustomobject] GetIpAddressById([int] $ipAddressId) {
        $uri = '{0}/api/ipam/ip-addresses/{1}/' -f $this.BaseUrl, $ipAddressId
        return Invoke-RestMethod -Uri $uri -Method Get -Headers $this.GetJsonHeaders() -ErrorAction Stop
    }

    <#
    .SYNOPSIS
    Loads one NetBox site object by id.
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    hidden [pscustomobject] GetSiteById([int] $siteId) {
        $uri = '{0}/api/dcim/sites/{1}/' -f $this.BaseUrl, $siteId
        return Invoke-RestMethod -Uri $uri -Method Get -Headers $this.GetJsonHeaders() -ErrorAction Stop
    }

    <#
    .SYNOPSIS
    Loads open prefix onboarding work items from NetBox.
    .OUTPUTS
    PrefixWorkItem[]
    #>
    [PrefixWorkItem[]] GetOpenPrefixWorkItems([EnvironmentContext] $environment) {
        $filter = @{
            status    = 'onboarding_open_dns_dhcp'
            cf_domain = $environment.DnsZone
        }

        $prefixes = $this.GetPaged('/api/ipam/prefixes/', $filter)
        $workItems = @()

        foreach ($prefix in $prefixes) {
            # NetBox stores some required fields behind linked objects, so resolve them before constructing the work item.
            $defaultGateway = $this.GetIpAddressById([int] $prefix.custom_fields.default_gateway.id)
            $site = $this.GetSiteById([int] $prefix.scope.id)

            $workItems += [PrefixWorkItem]::new(
                [int] $prefix.id,
                [string] $prefix.prefix,
                [string] $prefix.description,
                [string] $prefix.custom_fields.dhcp_type,
                [string] $prefix.custom_fields.domain,
                [string] $prefix.scope.name,
                [int] $prefix.scope.id,
                [int] $prefix.custom_fields.default_gateway.id,
                [string] (($defaultGateway.address -split '/')[0]),
                [string] $defaultGateway.dns_name,
                [string] $site.custom_fields.valuemation_site_mandant,
                [string] $prefix.custom_fields.ad_sites_and_services_ticket_url
            )
        }

        return $workItems
    }

    <#
    .SYNOPSIS
    Returns the most specific prefix containing an IP address.
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    #>
    hidden [pscustomobject] GetMostSpecificPrefixForAddress([string] $address) {
        $filter = @{ contains = $address; limit = 0 }
        $prefixes = $this.GetPaged('/api/ipam/prefixes/', $filter)
        if (-not $prefixes) {
            return $null
        }

        return $prefixes |
            Sort-Object -Property @{ Expression = { [int] (($_.prefix -split '/')[1]) } } -Descending |
            Select-Object -First 1
    }

    <#
    .SYNOPSIS
    Loads IP work items for the requested statuses and environment.
    .OUTPUTS
    IpAddressWorkItem[]
    #>
    [IpAddressWorkItem[]] GetIpWorkItems([EnvironmentContext] $environment, [string[]] $statuses) {
        $filter = @{ status = $statuses }
        $ipAddresses = $this.GetPaged('/api/ipam/ip-addresses/', $filter)
        $workItems = @()

        foreach ($ipAddress in $ipAddresses) {
            $hostIp = ($ipAddress.address -split '/')[0]
            $prefix = $this.GetMostSpecificPrefixForAddress($hostIp)
            if ($null -eq $prefix) {
                continue
            }

            $domain = [string] $prefix.custom_fields.domain
            if ([string]::IsNullOrWhiteSpace($domain)) {
                continue
            }

            # Only return work items that belong to the active environment's DNS zone.
            if ($domain.ToLowerInvariant() -ne $environment.DnsZone.ToLowerInvariant()) {
                continue
            }

            $workItems += [IpAddressWorkItem]::new(
                [int] $ipAddress.id,
                $hostIp,
                [string] $ipAddress.status.value,
                [string] $ipAddress.dns_name,
                $domain,
                [string] $prefix.prefix
            )
        }

        return $workItems
    }

    <#
    .SYNOPSIS
    Updates the Jira ticket URL stored on a prefix.
    .OUTPUTS
    System.Void
    #>
    [void] UpdatePrefixTicketUrl([int] $prefixId, [string] $ticketUrl) {
        $uri = '{0}/api/ipam/prefixes/{1}/' -f $this.BaseUrl, $prefixId
        $body = @{
            custom_fields = @{
                ad_sites_and_services_ticket_url = $ticketUrl
            }
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $uri -Method Patch -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    <#
    .SYNOPSIS
    Marks a prefix as fully onboarded in NetBox.
    .OUTPUTS
    System.Void
    #>
    [void] MarkPrefixOnboardingDone([int] $prefixId) {
        $uri = '{0}/api/ipam/prefixes/{1}/' -f $this.BaseUrl, $prefixId
        $body = @{ status = 'onboarding_done_dns_dhcp' } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri $uri -Method Patch -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    <#
    .SYNOPSIS
    Updates the NetBox status of an IP address.
    .OUTPUTS
    System.Void
    #>
    [void] UpdateIpStatus([int] $ipId, [string] $status) {
        $uri = '{0}/api/ipam/ip-addresses/{1}/' -f $this.BaseUrl, $ipId
        $body = @{ status = $status } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri $uri -Method Patch -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    <#
    .SYNOPSIS
    Adds a journal entry to a NetBox prefix or IP address.
    .OUTPUTS
    System.Void
    #>
    [void] AddJournalEntry([string] $targetType, [int] $targetId, [string] $message, [string] $kind) {
        $contentTypeMap = @{
            Prefix    = 'ipam.prefix'
            IPAddress = 'ipam.ipaddress'
        }

        $uri = '{0}/api/extras/journal-entries/' -f $this.BaseUrl
        $body = @{
            assigned_object_type = $contentTypeMap[$targetType]
            assigned_object_id   = $targetId
            comments             = $message
            kind                 = $kind
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $uri -Method Post -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    <#
    .SYNOPSIS
    Builds the direct NetBox URL for a prefix.
    .OUTPUTS
    System.String
    #>
    [string] GetPrefixUrl([int] $prefixId) {
        return '{0}/ipam/prefixes/{1}/' -f $this.BaseUrl, $prefixId
    }

    <#
    .SYNOPSIS
    Builds the direct NetBox URL for an IP address.
    .OUTPUTS
    System.String
    #>
    [string] GetIpAddressUrl([int] $ipAddressId) {
        return '{0}/ipam/ip-addresses/{1}/' -f $this.BaseUrl, $ipAddressId
    }
}
