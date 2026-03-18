# Isolates DNS server queries and record management behind a testable adapter boundary.
class DnsServerAdapter {
    [string] FindBestReverseZoneName([IPv4Subnet] $subnet, [string] $dnsComputerName) {
        $zoneName = $subnet.GetReverseZoneName()
        $reverseZones = Get-DnsServerZone -ComputerName $dnsComputerName -ErrorAction Stop | Where-Object { $_.IsReverseLookupZone -eq $true }
        $matchedZone = $null

        foreach ($zone in $reverseZones) {
            if ($zone.ZoneName -ieq $zoneName) {
                return [string] $zone.ZoneName
            }

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

    [bool] TestReverseZoneDelegation([IPv4Subnet] $subnet, [string] $domain) {
        $prefix = $subnet.PrefixLength
        while ($prefix -ge 8) {
            $candidateSubnet = [IPv4Subnet]::new('{0}/{1}' -f $subnet.NetworkAddress.Value, $prefix)
            $reverseZone = $candidateSubnet.GetReverseZoneName()

            try {
                $nsResult = Resolve-DnsName -Name $reverseZone -Type NS -ErrorAction SilentlyContinue
            }
            catch {
                $nsResult = $null
            }

            foreach ($record in @($nsResult)) {
                if ($record.NameHost -and $record.NameHost.ToLowerInvariant().EndsWith('.{0}' -f $domain.ToLowerInvariant())) {
                    return $true
                }
            }

            $prefix -= 8
        }

        return $false
    }

    hidden [string] GetRelativeDnsName([string] $dnsName, [string] $dnsZone) {
        if ($dnsName.ToLowerInvariant().EndsWith('.{0}' -f $dnsZone.ToLowerInvariant())) {
            return ($dnsName -replace ('\.{0}$' -f [regex]::Escape($dnsZone)), '')
        }

        return $dnsName
    }

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

    [void] EnsureDnsRecordsForIp(
        [string] $dnsServer,
        [string] $dnsZone,
        [string] $dnsName,
        [IPv4Address] $ipAddress,
        [string] $reverseZone,
        [string] $ptrDomainName
    ) {
        $relativeDnsName = $this.GetRelativeDnsName($dnsName, $dnsZone)
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
