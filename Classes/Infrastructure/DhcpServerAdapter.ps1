# Isolates DHCP server discovery and scope provisioning behind a testable adapter boundary.
<#
.SYNOPSIS
Wraps DHCP server discovery and scope provisioning.

.DESCRIPTION
Encapsulates server selection helpers, scope creation, exclusion handling, and
failover linking so DHCP-specific PowerShell cmdlets stay out of the application layer.

.NOTES
Methods:
- GetSitePattern(site, isDevelopment)
- IsPrimaryServer(dhcpServer)
- GetCurrentDomainSuffix()
- GetPrimaryServerForSite(site, isDevelopment)
- EnsureScope(dhcpServer, definition)
- EnsureScopeFailover(dhcpServer, subnet)
- RemoveScope(dhcpServer, subnet)

.EXAMPLE
$adapter = [DhcpServerAdapter]::new()
$adapter.GetPrimaryServerForSite('muc', $false)
#>
class DhcpServerAdapter {
    <#
    .SYNOPSIS
    Maps a site code to the DHCP server naming pattern.
    .OUTPUTS
    System.String
    #>
    hidden [string] GetSitePattern([string] $site, [bool] $isDevelopment) {
        $normalizedSite = $site.Trim().ToLowerInvariant()
        $pattern = $null
        switch ($normalizedSite) {
            'eme' { $pattern = 'e*' }
            'rze' { $pattern = 'r*' }
            'haj' { $pattern = 'h*' }
            'muc' { $pattern = 'm*' }
            'mal' { $pattern = 'm*' }
            'beg' { $pattern = 'o*' }
            'yvr' { $pattern = 'v*' }
            'lud' { $pattern = 'l*' }
            default { throw [System.InvalidOperationException]::new("Unsupported site '$site'.") }
        }

        if ($isDevelopment) {
            return 'dev{0}' -f $pattern
        }

        return $pattern
    }

    <#
    .SYNOPSIS
    Indicates whether a DHCP server is the primary node.
    .OUTPUTS
    System.Boolean
    #>
    hidden [bool] IsPrimaryServer([string] $dhcpServer) {
        $result = Invoke-Command -ComputerName $dhcpServer -ScriptBlock {
            try {
                $value = Get-ItemProperty -Path 'HKLM:\SOFTWARE\ACW\DHCP' -Name 'Primary' -ErrorAction Stop
                return [bool] $value.Primary
            }
            catch {
                return $false
            }
        }

        return [bool] $result
    }

    <#
    .SYNOPSIS
    Returns the current AD domain suffix for server filtering.
    .OUTPUTS
    System.String
    #>
    hidden [string] GetCurrentDomainSuffix() {
        return [string] (Get-ADDomainController).Domain
    }

    <#
    .SYNOPSIS
    Returns the preferred DHCP server for a site and environment.
    .OUTPUTS
    System.String
    #>
    [string] GetPrimaryServerForSite([string] $site, [bool] $isDevelopment) {
        $pattern = $this.GetSitePattern($site, $isDevelopment)
        $domainSuffix = $this.GetCurrentDomainSuffix()
        $servers = @(
            Get-DhcpServerInDC |
                Where-Object {
                    $_.DnsName -ilike $pattern -and
                    $_.DnsName.ToLowerInvariant().EndsWith($domainSuffix.ToLowerInvariant())
                } |
                Select-Object -ExpandProperty DnsName
        )

        if (-not $servers) {
            throw [System.InvalidOperationException]::new("No DHCP servers found for site '$site'.")
        }

        foreach ($server in $servers) {
            if ($this.IsPrimaryServer($server)) {
                return $server
            }
        }

        return [string] $servers[0]
    }

    <#
    .SYNOPSIS
    Ensures that a DHCP scope exists with the expected settings.
    .OUTPUTS
    System.Void
    #>
    [void] EnsureScope([string] $dhcpServer, [DhcpScopeDefinition] $definition) {
        $scopeId = $definition.Subnet.NetworkAddress.Value
        $existingScope = Get-DhcpServerv4Scope -ComputerName $dhcpServer -ScopeId $scopeId -ErrorAction SilentlyContinue

        if (-not $existingScope) {
            Add-DhcpServerv4Scope `
                -ComputerName $dhcpServer `
                -Name $definition.Name `
                -StartRange $definition.Range.StartAddress.Value `
                -EndRange $definition.Range.EndAddress.Value `
                -SubnetMask $definition.SubnetMask `
                -State Active `
                -LeaseDuration (New-TimeSpan -Days $definition.LeaseDurationDays) `
                -ErrorAction Stop
        }

        if ($definition.ConfigureDynamicDns) {
            Set-DhcpServerv4DnsSetting `
                -ComputerName $dhcpServer `
                -ScopeId $scopeId `
                -DynamicUpdates OnClientRequest `
                -DeleteDnsRRonLeaseExpiry $true `
                -UpdateDnsRRForOlderClients $true `
                -DisableDnsPtrRRUpdate $false `
                -ErrorAction Stop
        }

        Set-DhcpServerv4OptionValue -ComputerName $dhcpServer -ScopeId $scopeId -DnsDomain $definition.DnsDomain -Router $definition.Range.GatewayAddress.Value -ErrorAction Stop
        Set-DhcpServerv4OptionValue -ComputerName $dhcpServer -ScopeId $scopeId -OptionId 28 -Value $definition.Range.BroadcastAddress.Value -ErrorAction Stop

        # Exclusions can be either strict or best-effort depending on the DHCP model.
        foreach ($range in @($definition.ExclusionRanges)) {
            if ($range.MustSucceed) {
                Add-DhcpServerv4ExclusionRange `
                    -ComputerName $dhcpServer `
                    -ScopeId $scopeId `
                    -StartRange $range.StartAddress.Value `
                    -EndRange $range.EndAddress.Value `
                    -ErrorAction Stop | Out-Null
                continue
            }

            Add-DhcpServerv4ExclusionRange `
                -ComputerName $dhcpServer `
                -ScopeId $scopeId `
                -StartRange $range.StartAddress.Value `
                -EndRange $range.EndAddress.Value `
                -ErrorAction SilentlyContinue | Out-Null
        }
    }

    <#
    .SYNOPSIS
    Ensures that the created scope is linked into failover when available.
    .OUTPUTS
    System.Void
    #>
    [void] EnsureScopeFailover([string] $dhcpServer, [IPv4Subnet] $subnet) {
        try {
            $failover = Get-DhcpServerv4Failover -ComputerName $dhcpServer -ErrorAction Stop | Select-Object -First 1
        }
        catch {
            # Missing failover is not fatal for provisioning; the scope itself is still valid.
            return
        }

        if ($null -eq $failover -or [string]::IsNullOrWhiteSpace($failover.Name)) {
            return
        }

        Add-DhcpServerv4FailoverScope -ComputerName $dhcpServer -Name $failover.Name -ScopeId $subnet.NetworkAddress.Value -ErrorAction SilentlyContinue | Out-Null
    }

    <#
    .SYNOPSIS
    Placeholder for future prefix decommissioning.
    .OUTPUTS
    System.Void
    #>
    [void] RemoveScope([string] $dhcpServer, [IPv4Subnet] $subnet) {
        throw [System.NotImplementedException]::new('Prefix decommissioning is intentionally not implemented yet.')
    }
}
