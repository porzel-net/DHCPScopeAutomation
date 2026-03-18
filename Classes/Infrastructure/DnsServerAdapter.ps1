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
    <#
    .SYNOPSIS
    Finds the best matching reverse zone for a subnet.
    .OUTPUTS
    System.String
    #>
    [string] FindBestReverseZoneName([IPv4Subnet] $subnet, [string] $dnsComputerName) {
        $zoneName = $subnet.GetReverseZoneName()
        $reverseZones = Get-DnsServerZone -ComputerName $dnsComputerName -ErrorAction Stop | Where-Object { $_.IsReverseLookupZone -eq $true }
        $matchedZone = $null

        foreach ($zone in $reverseZones) {
            if ($zone.ZoneName -ieq $zoneName) {
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
                    }
                }
            }
        }

        if ($null -eq $matchedZone) {
            return $null
        }

        return [string] $matchedZone.ZoneName
    }

    <#
    .SYNOPSIS
    Tests whether reverse DNS delegation exists for a subnet.
    .OUTPUTS
    System.Boolean
    #>
    [bool] TestReverseZoneDelegation([IPv4Subnet] $subnet, [string] $domain) {
        $prefix = $subnet.PrefixLength
        while ($prefix -ge 8) {
            # Walk outward in /8 steps until a delegated reverse zone is found or the search is exhausted.
            $candidateSubnet = [IPv4Subnet]::new(('{0}/{1}' -f $subnet.NetworkAddress.Value, $prefix))
            $reverseZone = $candidateSubnet.GetReverseZoneName()

            try {
                $nsResult = Resolve-DnsName -Name $reverseZone -Type NS -ErrorAction SilentlyContinue
            }
            catch {
                $nsResult = $null
            }

            foreach ($record in @($nsResult)) {
                if ($record.NameHost -and $record.NameHost.ToLowerInvariant().EndsWith(('.{0}' -f $domain.ToLowerInvariant()))) {
                    return $true
                }
            }

            $prefix -= 8
        }

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
    [void] RemoveDnsRecordsForIp([string] $dnsServer, [string] $dnsZone, [string] $reverseZone, [IPv4Address] $ipAddress) {
        $ipValue = $ipAddress.Value

        $matchingARecords = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $dnsZone -RRType A -ErrorAction SilentlyContinue |
            Where-Object { $_.RecordData.IPv4Address.IPAddressToString -eq $ipValue }

        foreach ($record in @($matchingARecords)) {
            Remove-DnsServerResourceRecord -ZoneName $dnsZone -Name $record.HostName -RRType A -RecordData $ipValue -ComputerName $dnsServer -Force -ErrorAction Stop
        }

        $ptrOwnerName = $this.GetPtrOwnerName($reverseZone, $ipAddress)
        $matchingPtrRecords = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $reverseZone -RRType PTR -ErrorAction SilentlyContinue |
            Where-Object { $_.HostName -eq $ptrOwnerName }

        foreach ($ptrRecord in @($matchingPtrRecords)) {
            Remove-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $reverseZone -InputObject $ptrRecord -Force -ErrorAction Stop
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
        [string] $ptrDomainName
    ) {
        $relativeDnsName = $this.GetRelativeDnsName($dnsName, $dnsZone)
        # Remove first so onboarding is idempotent even when stale records already exist.
        $this.RemoveDnsRecordsForIp($dnsServer, $dnsZone, $reverseZone, $ipAddress)

        $existingARecord = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $dnsZone -Name $relativeDnsName -RRType A -ErrorAction SilentlyContinue
        if (-not $existingARecord) {
            Add-DnsServerResourceRecordA -ComputerName $dnsServer -ZoneName $dnsZone -Name $relativeDnsName -IPv4Address $ipAddress.Value -ErrorAction Stop
        }

        $ptrOwnerName = $this.GetPtrOwnerName($reverseZone, $ipAddress)
        $existingPtrRecord = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $reverseZone -Name $ptrOwnerName -RRType PTR -ErrorAction SilentlyContinue
        if (-not $existingPtrRecord) {
            Add-DnsServerResourceRecordPtr -ComputerName $dnsServer -ZoneName $reverseZone -Name $ptrOwnerName -PtrDomainName $ptrDomainName -ErrorAction Stop
        }
    }
}
