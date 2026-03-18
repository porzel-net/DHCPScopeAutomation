# Wraps NetBox API access and shields the application layer from raw REST details.
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

    hidden [hashtable] GetJsonHeaders() {
        return @{
            Authorization = ('Token {0}' -f $this.Credential.GetPlainApiKey())
            Accept        = 'application/json'
            'Content-Type' = 'application/json'
        }
    }

    hidden [string] BuildQueryString([hashtable] $filter) {
        if ($null -eq $filter -or $filter.Count -eq 0) {
            return ''
        }

        $parts = @()
        foreach ($key in $filter.Keys) {
            $value = $filter[$key]
            if ($null -eq $value) { continue }

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
            $response = Invoke-RestMethod -Uri $nextUri -Method Get -Headers $headers -ErrorAction Stop
            $results += @($response.results)
            $nextUri = $response.next
        }

        return $results
    }

    hidden [pscustomobject] GetIpAddressById([int] $ipAddressId) {
        $uri = '{0}/api/ipam/ip-addresses/{1}/' -f $this.BaseUrl, $ipAddressId
        return Invoke-RestMethod -Uri $uri -Method Get -Headers $this.GetJsonHeaders() -ErrorAction Stop
    }

    hidden [pscustomobject] GetSiteById([int] $siteId) {
        $uri = '{0}/api/dcim/sites/{1}/' -f $this.BaseUrl, $siteId
        return Invoke-RestMethod -Uri $uri -Method Get -Headers $this.GetJsonHeaders() -ErrorAction Stop
    }

    [PrefixWorkItem[]] GetOpenPrefixWorkItems([EnvironmentContext] $environment) {
        $filter = @{
            status    = 'onboarding_open_dns_dhcp'
            cf_domain = $environment.DnsZone
        }

        $prefixes = $this.GetPaged('/api/ipam/prefixes/', $filter)
        $workItems = @()

        foreach ($prefix in $prefixes) {
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

    [void] UpdatePrefixTicketUrl([int] $prefixId, [string] $ticketUrl) {
        $uri = '{0}/api/ipam/prefixes/{1}/' -f $this.BaseUrl, $prefixId
        $body = @{
            custom_fields = @{
                ad_sites_and_services_ticket_url = $ticketUrl
            }
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $uri -Method Patch -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    [void] MarkPrefixOnboardingDone([int] $prefixId) {
        $uri = '{0}/api/ipam/prefixes/{1}/' -f $this.BaseUrl, $prefixId
        $body = @{ status = 'onboarding_done_dns_dhcp' } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri $uri -Method Patch -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    [void] UpdateIpStatus([int] $ipId, [string] $status) {
        $uri = '{0}/api/ipam/ip-addresses/{1}/' -f $this.BaseUrl, $ipId
        $body = @{ status = $status } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri $uri -Method Patch -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

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

    [string] GetPrefixUrl([int] $prefixId) {
        return '{0}/ipam/prefixes/{1}/' -f $this.BaseUrl, $prefixId
    }

    [string] GetIpAddressUrl([int] $ipAddressId) {
        return '{0}/ipam/ip-addresses/{1}/' -f $this.BaseUrl, $ipAddressId
    }
}
