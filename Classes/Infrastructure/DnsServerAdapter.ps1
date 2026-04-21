# Isolates DNS server queries and record management behind a testable adapter boundary.
<#
.SYNOPSIS
Wraps DNS zone discovery and DNS record management.

.DESCRIPTION
Centralizes reverse-zone lookup, reverse-delegation checks, and forward/reverse
record management so application services interact with DNS through one adapter.

.NOTES
Methods:
- FindBestReverseZoneName(subnet, dnsComputerName)
- TestReverseZoneDelegation(subnet, domain)
- GetRelativeDnsName(dnsName, dnsZone)
- GetPtrOwnerName(reverseZone, ipAddress)
- RemoveDnsRecordsForIp(dnsServer, dnsZone, reverseZone, ipAddress)
- EnsureDnsRecordsForIp(dnsServer, dnsZone, dnsName, ipAddress, reverseZone, ptrDomainName)

.EXAMPLE
$adapter = [DnsServerAdapter]::new()
$adapter.FindBestReverseZoneName([IPv4Subnet]::new('10.20.30.0/24'), 'dc01.example.test')
#>
class DnsServerAdapter {
    hidden [void] AppendLine([System.Collections.Generic.List[string]] $lines, [string] $message) {
        if ($null -ne $lines -and -not [string]::IsNullOrWhiteSpace($message)) {
            $null = $lines.Add($message)
        }
    }

    <#
    .SYNOPSIS
    Finds the best matching reverse zone for a subnet.
    .OUTPUTS
    System.String
    #>
    [string] FindBestReverseZoneName([IPv4Subnet] $subnet, [string] $dnsComputerName) {
        $zoneName = $subnet.GetReverseZoneName()
        Write-Verbose -Message ("Resolving reverse zone for subnet '{0}' on DNS server '{1}'. Target zone '{2}'." -f $subnet.Cidr, $dnsComputerName, $zoneName)
        $reverseZones = Get-DnsServerZone -ComputerName $dnsComputerName -ErrorAction Stop | Where-Object { $_.IsReverseLookupZone -eq $true }
        $matchedZone = $null

        foreach ($zone in $reverseZones) {
            if ($zone.ZoneName -ieq $zoneName) {
                Write-Verbose -Message ("Found exact reverse zone match '{0}' for subnet '{1}'." -f $zone.ZoneName, $subnet.Cidr)
                return [string] $zone.ZoneName
            }

            # Prefer the longest suffix match when an exact reverse zone is not present.
            $zoneLabels = $zone.ZoneName -split '\.'
            $targetLabels = $zoneName -split '\.'
            if ($targetLabels.Length -ge $zoneLabels.Length) {
                $endingLabels = $targetLabels[-$zoneLabels.Length..-1]
                if (($endingLabels -join '.') -ieq $zone.ZoneName) {
                    if ($null -eq $matchedZone -or $zoneLabels.Length -gt (($matchedZone.ZoneName -split '\.').Length)) {
                        $matchedZone = $zone
                        Write-Debug -Message ("Tracking best reverse-zone suffix match candidate '{0}' for subnet '{1}'." -f $zone.ZoneName, $subnet.Cidr)
                    }
                }
            }
        }

        if ($null -eq $matchedZone) {
            Write-Verbose -Message ("No reverse zone match found for subnet '{0}' on DNS server '{1}'." -f $subnet.Cidr, $dnsComputerName)
            return $null
        }

        Write-Verbose -Message ("Using best reverse-zone suffix match '{0}' for subnet '{1}'." -f $matchedZone.ZoneName, $subnet.Cidr)
        return [string] $matchedZone.ZoneName
    }

    <#
    .SYNOPSIS
    Tests whether reverse DNS delegation exists for a subnet.
    .OUTPUTS
    System.Boolean
    #>
    [bool] TestReverseZoneDelegation([IPv4Subnet] $subnet, [string] $domain) {
        Write-Verbose -Message ("Validating reverse DNS delegation for subnet '{0}' against domain '{1}'." -f $subnet.Cidr, $domain)
        $prefix = $subnet.PrefixLength
        while ($prefix -ge 8) {
            # Walk outward in /8 steps until a delegated reverse zone is found or the search is exhausted.
            $candidateSubnet = [IPv4Subnet]::new(('{0}/{1}' -f $subnet.NetworkAddress.Value, $prefix))
            $reverseZone = $candidateSubnet.GetReverseZoneName()
            Write-Debug -Message ("Checking NS delegation on reverse zone candidate '{0}'." -f $reverseZone)

            try {
                $nsResult = Resolve-DnsName -Name $reverseZone -Type NS -ErrorAction SilentlyContinue
            }
            catch {
                $nsResult = $null
            }

            foreach ($record in @($nsResult)) {
                if ($record.NameHost -and $record.NameHost.ToLowerInvariant().EndsWith(('.{0}' -f $domain.ToLowerInvariant()))) {
                    Write-Verbose -Message ("Found delegated reverse DNS NS host '{0}' for zone '{1}'." -f $record.NameHost, $reverseZone)
                    return $true
                }
            }

            $prefix -= 8
        }

        Write-Verbose -Message ("No matching reverse DNS delegation found for subnet '{0}'." -f $subnet.Cidr)
        return $false
    }

    <#
    .SYNOPSIS
    Returns the record-relative DNS name for a zone.
    .OUTPUTS
    System.String
    #>
    hidden [string] GetRelativeDnsName([string] $dnsName, [string] $dnsZone) {
        if ($dnsName.ToLowerInvariant().EndsWith(('.{0}' -f $dnsZone.ToLowerInvariant()))) {
            return ($dnsName -replace ('\.{0}$' -f [regex]::Escape($dnsZone)), '')
        }

        return $dnsName
    }

    <#
    .SYNOPSIS
    Returns the PTR owner name inside a reverse zone.
    .OUTPUTS
    System.String
    #>
    hidden [string] GetPtrOwnerName([string] $reverseZone, [IPv4Address] $ipAddress) {
        $zonePart = ($reverseZone.TrimEnd('.').ToLowerInvariant() -replace '\.?in-addr\.arpa$', '').Trim('.')
        $labels = @()
        if (-not [string]::IsNullOrWhiteSpace($zonePart)) {
            $labels = @($zonePart.Split('.') | Where-Object { $_ })
        }

        $octets = $ipAddress.Value.Split('.')
        $ownerName = $null
        switch ($labels.Count) {
            1 { $ownerName = '{0}.{1}.{2}' -f $octets[3], $octets[2], $octets[1] }
            2 { $ownerName = '{0}.{1}' -f $octets[3], $octets[2] }
            3 { $ownerName = '{0}' -f $octets[3] }
            default { throw [System.InvalidOperationException]::new("Unsupported reverse zone '$reverseZone'.") }
        }

        return $ownerName
    }

    <#
    .SYNOPSIS
    Removes forward and reverse DNS records for an IP address.
    .OUTPUTS
    System.Void
    #>
    [void] RemoveDnsRecordsForIp(
        [string] $dnsServer,
        [string] $dnsZone,
        [string] $reverseZone,
        [IPv4Address] $ipAddress,
        [System.Collections.Generic.List[string]] $lines = $null
    ) {
        $ipValue = $ipAddress.Value
        Write-Verbose -Message ("Removing DNS records for IP '{0}' on server '{1}' (zone='{2}', reverseZone='{3}')." -f $ipValue, $dnsServer, $dnsZone, $reverseZone)
        $this.AppendLine($lines, ('Removing DNS records for IP {0} on server {1} (zone={2}, reverseZone={3}).' -f $ipValue, $dnsServer, $dnsZone, $reverseZone))

        $matchingARecords = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $dnsZone -RRType A -ErrorAction SilentlyContinue |
            Where-Object { $_.RecordData.IPv4Address.IPAddressToString -eq $ipValue }
        Write-Debug -Message ("Found {0} matching A record(s) for IP '{1}' in zone '{2}'." -f @($matchingARecords).Count, $ipValue, $dnsZone)
        $this.AppendLine($lines, ('Found {0} matching A record(s) for IP {1} in zone {2}.' -f @($matchingARecords).Count, $ipValue, $dnsZone))

        foreach ($record in @($matchingARecords)) {
            $this.AppendLine($lines, ('Removing A record {0}.{1} -> {2}.' -f $record.HostName, $dnsZone, $ipValue))
            Remove-DnsServerResourceRecord -ZoneName $dnsZone -Name $record.HostName -RRType A -RecordData $ipValue -ComputerName $dnsServer -Force -ErrorAction Stop
            $this.AppendLine($lines, ('Removed A record {0}.{1} -> {2}.' -f $record.HostName, $dnsZone, $ipValue))
        }

        $ptrOwnerName = $this.GetPtrOwnerName($reverseZone, $ipAddress)
        $matchingPtrRecords = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $reverseZone -RRType PTR -ErrorAction SilentlyContinue |
            Where-Object { $_.HostName -eq $ptrOwnerName }
        Write-Debug -Message ("Found {0} matching PTR record(s) for owner '{1}' in reverse zone '{2}'." -f @($matchingPtrRecords).Count, $ptrOwnerName, $reverseZone)
        $this.AppendLine($lines, ('Found {0} matching PTR record(s) for owner {1} in reverse zone {2}.' -f @($matchingPtrRecords).Count, $ptrOwnerName, $reverseZone))

        foreach ($ptrRecord in @($matchingPtrRecords)) {
            $currentTarget = $ptrRecord.RecordData.PtrDomainName
            if ($currentTarget) { $currentTarget = $currentTarget.TrimEnd('.') }
            $currentTargetSuffix = ''
            if ($currentTarget) {
                $currentTargetSuffix = ' -> {0}' -f $currentTarget
            }
            $this.AppendLine($lines, ('Removing PTR record owner {0} in reverse zone {1}{2}.' -f $ptrOwnerName, $reverseZone, $currentTargetSuffix))
            Remove-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $reverseZone -InputObject $ptrRecord -Force -ErrorAction Stop
            if ($currentTarget) {
                $this.AppendLine($lines, ('Removed PTR record owner {0} in reverse zone {1} -> {2}.' -f $ptrOwnerName, $reverseZone, $currentTarget))
            }
            else {
                $this.AppendLine($lines, ('Removed PTR record owner {0} in reverse zone {1}.' -f $ptrOwnerName, $reverseZone))
            }
        }
    }

    <#
    .SYNOPSIS
    Ensures forward and reverse DNS records for an IP address.
    .OUTPUTS
    System.Void
    #>
    [void] EnsureDnsRecordsForIp(
        [string] $dnsServer,
        [string] $dnsZone,
        [string] $dnsName,
        [IPv4Address] $ipAddress,
        [string] $reverseZone,
        [string] $ptrDomainName,
        [System.Collections.Generic.List[string]] $lines = $null
    ) {
        $relativeDnsName = $this.GetRelativeDnsName($dnsName, $dnsZone)
        Write-Verbose -Message ("Ensuring DNS records for '{0}' ({1}) on server '{2}' with reverse zone '{3}'." -f $dnsName, $ipAddress.Value, $dnsServer, $reverseZone)
        Write-Debug -Message ("Computed relative DNS name '{0}' for zone '{1}'." -f $relativeDnsName, $dnsZone)
        $this.AppendLine($lines, ('Ensuring DNS records for {0} ({1}) on server {2} with reverse zone {3}.' -f $dnsName, $ipAddress.Value, $dnsServer, $reverseZone))
        $this.AppendLine($lines, ('Computed relative DNS name {0} for zone {1}.' -f $relativeDnsName, $dnsZone))
        # Remove first so onboarding is idempotent even when stale records already exist.
        $this.AppendLine($lines, ('Removing existing DNS records for IP {0} before ensuring new records.' -f $ipAddress.Value))
        $this.RemoveDnsRecordsForIp($dnsServer, $dnsZone, $reverseZone, $ipAddress, $lines)

        $existingARecord = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $dnsZone -Name $relativeDnsName -RRType A -ErrorAction SilentlyContinue
        if (-not $existingARecord) {
            Write-Debug -Message ("Creating A record '{0}' in zone '{1}' with IP '{2}'." -f $relativeDnsName, $dnsZone, $ipAddress.Value)
            $this.AppendLine($lines, ('Creating A record {0}.{1} -> {2}.' -f $relativeDnsName, $dnsZone, $ipAddress.Value))
            Add-DnsServerResourceRecordA -ComputerName $dnsServer -ZoneName $dnsZone -Name $relativeDnsName -IPv4Address $ipAddress.Value -ErrorAction Stop
            $this.AppendLine($lines, ('Created A record {0}.{1} -> {2}.' -f $relativeDnsName, $dnsZone, $ipAddress.Value))
        }
        else {
            Write-Debug -Message ("A record '{0}' in zone '{1}' already exists." -f $relativeDnsName, $dnsZone)
            $this.AppendLine($lines, ('A record {0}.{1} already exists.' -f $relativeDnsName, $dnsZone))
        }

        $ptrOwnerName = $this.GetPtrOwnerName($reverseZone, $ipAddress)
        $existingPtrRecord = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $reverseZone -Name $ptrOwnerName -RRType PTR -ErrorAction SilentlyContinue
        if (-not $existingPtrRecord) {
            Write-Debug -Message ("Creating PTR record owner '{0}' in reverse zone '{1}' -> '{2}'." -f $ptrOwnerName, $reverseZone, $ptrDomainName)
            $this.AppendLine($lines, ('Creating PTR record owner {0} in reverse zone {1} -> {2}.' -f $ptrOwnerName, $reverseZone, $ptrDomainName))
            Add-DnsServerResourceRecordPtr -ComputerName $dnsServer -ZoneName $reverseZone -Name $ptrOwnerName -PtrDomainName $ptrDomainName -ErrorAction Stop
            $this.AppendLine($lines, ('Created PTR record owner {0} in reverse zone {1} -> {2}.' -f $ptrOwnerName, $reverseZone, $ptrDomainName))
        }
        else {
            Write-Debug -Message ("PTR record owner '{0}' in reverse zone '{1}' already exists." -f $ptrOwnerName, $reverseZone)
            $this.AppendLine($lines, ('PTR record owner {0} in reverse zone {1} already exists.' -f $ptrOwnerName, $reverseZone))
        }
    }
}
