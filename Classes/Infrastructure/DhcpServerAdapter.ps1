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
    hidden [void] AppendLine([System.Collections.Generic.List[string]] $lines, [string] $message) {
        if ($null -ne $lines -and -not [string]::IsNullOrWhiteSpace($message)) {
            $null = $lines.Add($message)
        }
    }

    <#
    .SYNOPSIS
    Maps a site code to the DHCP server naming pattern.
    .OUTPUTS
    System.String
    #>
    hidden [string] GetSitePattern([string] $site, [bool] $isDevelopment) {
        $normalizedSite = $site.Trim().ToLowerInvariant()
        $pattern = $null
        Write-Debug -Message ("Resolving DHCP site pattern for site '{0}' (normalized '{1}'), development={2}." -f $site, $normalizedSite, $isDevelopment)
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
            $developmentPattern = 'dev{0}' -f $pattern
            Write-Verbose -Message ("Using development DHCP site pattern '{0}' for site '{1}'." -f $developmentPattern, $normalizedSite)
            return $developmentPattern
        }

        Write-Verbose -Message ("Using DHCP site pattern '{0}' for site '{1}'." -f $pattern, $normalizedSite)
        return $pattern
    }

    <#
    .SYNOPSIS
    Indicates whether a DHCP server is the primary node.
    .OUTPUTS
    System.Boolean
    #>
    hidden [bool] IsPrimaryServer([string] $dhcpServer) {
        Write-Debug -Message ("Checking DHCP primary marker on server '{0}'." -f $dhcpServer)
        $result = Invoke-Command -ComputerName $dhcpServer -ScriptBlock {
            try {
                $value = Get-ItemProperty -Path 'HKLM:\SOFTWARE\ACW\DHCP' -Name 'Primary' -ErrorAction Stop
                return [bool] $value.Primary
            }
            catch {
                return $false
            }
        }

        Write-Debug -Message ("DHCP server '{0}' primary marker result: {1}" -f $dhcpServer, [bool] $result)
        return [bool] $result
    }

    <#
    .SYNOPSIS
    Returns the current AD domain suffix for server filtering.
    .OUTPUTS
    System.String
    #>
    hidden [string] GetCurrentDomainSuffix() {
        $domainSuffix = [string] (Get-ADDomainController).Domain
        Write-Verbose -Message ("Resolved DHCP domain suffix '{0}' for server filtering." -f $domainSuffix)
        return $domainSuffix
    }

    <#
    .SYNOPSIS
    Returns the preferred DHCP server for a site and environment.
    .OUTPUTS
    System.String
    #>
    [string] GetPrimaryServerForSite([string] $site, [bool] $isDevelopment) {
        Write-Verbose -Message ("Selecting primary DHCP server for site '{0}', development={1}." -f $site, $isDevelopment)
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
        Write-Debug -Message ("Filtered DHCP server candidates for site '{0}' and suffix '{1}': {2}" -f $site, $domainSuffix, ($servers -join ', '))

        if (-not $servers) {
            throw [System.InvalidOperationException]::new("No DHCP servers found for site '$site'.")
        }

        foreach ($server in $servers) {
            if ($this.IsPrimaryServer($server)) {
                Write-Verbose -Message ("Selected primary DHCP server '{0}' for site '{1}'." -f $server, $site)
                return $server
            }
        }

        Write-Verbose -Message ("No primary DHCP server flag found for site '{0}'. Falling back to '{1}'." -f $site, [string] $servers[0])
        return [string] $servers[0]
    }

    <#
    .SYNOPSIS
    Ensures that a DHCP scope exists with the expected settings.
    .OUTPUTS
    System.Void
    #>
    [void] EnsureScope([string] $dhcpServer, [DhcpScopeDefinition] $definition, [System.Collections.Generic.List[string]] $lines = $null) {
        $scopeId = $definition.Subnet.NetworkAddress.Value
        Write-Verbose -Message ("Ensuring DHCP scope '{0}' on server '{1}'." -f $scopeId, $dhcpServer)
        Write-Debug -Message ("Scope details: Name='{0}', Range='{1}-{2}', Mask='{3}', LeaseDays={4}, DynamicDns={5}, Exclusions={6}" -f $definition.Name, $definition.Range.StartAddress.Value, $definition.Range.EndAddress.Value, $definition.SubnetMask, $definition.LeaseDurationDays, $definition.ConfigureDynamicDns, @($definition.ExclusionRanges).Count)
        $this.AppendLine($lines, ('Ensuring DHCP scope {0} on server {1}.' -f $scopeId, $dhcpServer))
        $this.AppendLine($lines, ('Scope details: Name={0}, Range={1}-{2}, Mask={3}, LeaseDays={4}, DynamicDns={5}, Exclusions={6}' -f $definition.Name, $definition.Range.StartAddress.Value, $definition.Range.EndAddress.Value, $definition.SubnetMask, $definition.LeaseDurationDays, $definition.ConfigureDynamicDns, @($definition.ExclusionRanges).Count))
        $existingScope = Get-DhcpServerv4Scope -ComputerName $dhcpServer -ScopeId $scopeId -ErrorAction SilentlyContinue

        if (-not $existingScope) {
            Write-Verbose -Message ("Creating new DHCP scope '{0}' on '{1}'." -f $scopeId, $dhcpServer)
            $this.AppendLine($lines, ('Creating new DHCP scope {0} on {1}.' -f $scopeId, $dhcpServer))
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
        else {
            Write-Verbose -Message ("DHCP scope '{0}' already exists on '{1}', reusing existing scope." -f $scopeId, $dhcpServer)
            $this.AppendLine($lines, ('DHCP scope {0} already exists on {1}, reusing existing scope.' -f $scopeId, $dhcpServer))
        }

        if ($definition.ConfigureDynamicDns) {
            Write-Verbose -Message ("Configuring dynamic DNS settings for scope '{0}' on '{1}'." -f $scopeId, $dhcpServer)
            $this.AppendLine($lines, ('Configuring dynamic DNS settings for scope {0} on {1}.' -f $scopeId, $dhcpServer))
            Set-DhcpServerv4DnsSetting `
                -ComputerName $dhcpServer `
                -ScopeId $scopeId `
                -DynamicUpdates OnClientRequest `
                -DeleteDnsRRonLeaseExpiry $true `
                -UpdateDnsRRForOlderClients $true `
                -DisableDnsPtrRRUpdate $false `
                -ErrorAction Stop
        }

        Write-Verbose -Message ("Applying DHCP option values for scope '{0}' on '{1}'." -f $scopeId, $dhcpServer)
        $this.AppendLine($lines, ('Applying DHCP option values for scope {0} on {1}.' -f $scopeId, $dhcpServer))
        Set-DhcpServerv4OptionValue -ComputerName $dhcpServer -ScopeId $scopeId -DnsDomain $definition.DnsDomain -Router $definition.Range.GatewayAddress.Value -ErrorAction Stop
        Set-DhcpServerv4OptionValue -ComputerName $dhcpServer -ScopeId $scopeId -OptionId 28 -Value $definition.Range.BroadcastAddress.Value -ErrorAction Stop

        # Exclusions can be either strict or best-effort depending on the DHCP model.
        foreach ($range in @($definition.ExclusionRanges)) {
            if ($range.MustSucceed) {
                Write-Debug -Message ("Adding mandatory DHCP exclusion range '{0}-{1}' to scope '{2}' on '{3}'." -f $range.StartAddress.Value, $range.EndAddress.Value, $scopeId, $dhcpServer)
                $this.AppendLine($lines, ('Adding mandatory DHCP exclusion range {0}-{1} to scope {2} on {3}.' -f $range.StartAddress.Value, $range.EndAddress.Value, $scopeId, $dhcpServer))
                Add-DhcpServerv4ExclusionRange `
                    -ComputerName $dhcpServer `
                    -ScopeId $scopeId `
                    -StartRange $range.StartAddress.Value `
                    -EndRange $range.EndAddress.Value `
                    -ErrorAction Stop | Out-Null
                continue
            }

            Write-Debug -Message ("Adding best-effort DHCP exclusion range '{0}-{1}' to scope '{2}' on '{3}'." -f $range.StartAddress.Value, $range.EndAddress.Value, $scopeId, $dhcpServer)
            $this.AppendLine($lines, ('Adding best-effort DHCP exclusion range {0}-{1} to scope {2} on {3}.' -f $range.StartAddress.Value, $range.EndAddress.Value, $scopeId, $dhcpServer))
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
    [void] EnsureScopeFailover([string] $dhcpServer, [IPv4Subnet] $subnet, [System.Collections.Generic.List[string]] $lines = $null) {
        Write-Verbose -Message ("Ensuring DHCP failover linkage for scope '{0}' on server '{1}'." -f $subnet.NetworkAddress.Value, $dhcpServer)
        $this.AppendLine($lines, ('Ensuring DHCP failover linkage for scope {0} on server {1}.' -f $subnet.NetworkAddress.Value, $dhcpServer))
        try {
            $failover = Get-DhcpServerv4Failover -ComputerName $dhcpServer -ErrorAction Stop | Select-Object -First 1
        }
        catch {
            # Missing failover is not fatal for provisioning; the scope itself is still valid.
            Write-Verbose -Message ("No DHCP failover configuration available on '{0}'. Scope '{1}' remains without failover link." -f $dhcpServer, $subnet.NetworkAddress.Value)
            $this.AppendLine($lines, ('No DHCP failover configuration available on {0}. Scope {1} remains without failover link.' -f $dhcpServer, $subnet.NetworkAddress.Value))
            return
        }

        if ($null -eq $failover -or [string]::IsNullOrWhiteSpace($failover.Name)) {
            Write-Verbose -Message ("Failover query returned no usable failover name on '{0}'." -f $dhcpServer)
            $this.AppendLine($lines, ('Failover query returned no usable failover name on {0}.' -f $dhcpServer))
            return
        }

        Write-Verbose -Message ("Linking scope '{0}' to failover '{1}' on '{2}'." -f $subnet.NetworkAddress.Value, $failover.Name, $dhcpServer)
        $this.AppendLine($lines, ('Linking scope {0} to failover {1} on {2}.' -f $subnet.NetworkAddress.Value, $failover.Name, $dhcpServer))
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
