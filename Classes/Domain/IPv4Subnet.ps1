# Models an IPv4 network and centralizes address arithmetic used across the domain layer.
class IPv4Subnet {
    [string] $Cidr
    [IPv4Address] $NetworkAddress
    [int] $PrefixLength

    IPv4Subnet([string] $cidr) {
        if ([string]::IsNullOrWhiteSpace($cidr)) {
            throw [System.ArgumentException]::new('CIDR value is required.')
        }

        $parts = $cidr.Trim().Split('/')
        if ($parts.Length -ne 2) {
            throw [System.ArgumentException]::new("Invalid CIDR '$cidr'.")
        }

        $prefix = 0
        if (-not [int]::TryParse($parts[1], [ref] $prefix)) {
            throw [System.ArgumentException]::new("Invalid prefix length in '$cidr'.")
        }

        if ($prefix -lt 0 -or $prefix -gt 32) {
            throw [System.ArgumentOutOfRangeException]::new('cidr', "Prefix length must be between 0 and 32. Found '$prefix'.")
        }

        $baseAddress = [IPv4Address]::new($parts[0])
        $networkNumber = [IPv4Subnet]::MaskAddress($baseAddress.GetUInt32(), $prefix)

        $this.NetworkAddress = [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($networkNumber))
        $this.PrefixLength = $prefix
        $this.Cidr = '{0}/{1}' -f $this.NetworkAddress.Value, $prefix
    }

    hidden static [uint32] GetMask([int] $prefixLength) {
        if ($prefixLength -eq 0) {
            return [uint32] 0
        }

        return [uint32] ([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefixLength))
    }

    hidden static [uint32] MaskAddress([uint32] $address, [int] $prefixLength) {
        $mask = [IPv4Subnet]::GetMask($prefixLength)
        return [uint32] ($address -band $mask)
    }

    [string] GetSubnetMaskString() {
        return [IPv4Address]::ConvertFromUInt32([IPv4Subnet]::GetMask($this.PrefixLength))
    }

    [IPv4Address] GetBroadcastAddress() {
        $hostBits = 32 - $this.PrefixLength
        $broadcastNumber = [uint32] ($this.NetworkAddress.GetUInt32() + [uint32]([math]::Pow(2, $hostBits) - 1))
        return [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($broadcastNumber))
    }

    [IPv4Address] GetAddressAtOffset([int] $offset) {
        return $this.NetworkAddress.AddOffset($offset)
    }

    [string] GetReverseZoneName() {
        $fullOctets = [math]::Floor($this.PrefixLength / 8)
        if ($fullOctets -lt 1 -or $fullOctets -gt 4) {
            throw [System.InvalidOperationException]::new("Prefix '$($this.Cidr)' does not map to an octet-based reverse zone.")
        }

        $octets = $this.NetworkAddress.Value.Split('.')
        switch ($fullOctets) {
            1 { return '{0}.in-addr.arpa' -f $octets[0] }
            2 { return '{0}.{1}.in-addr.arpa' -f $octets[1], $octets[0] }
            3 { return '{0}.{1}.{2}.in-addr.arpa' -f $octets[2], $octets[1], $octets[0] }
            4 { return '{0}.{1}.{2}.{3}.in-addr.arpa' -f $octets[3], $octets[2], $octets[1], $octets[0] }
        }

        throw [System.InvalidOperationException]::new("Unable to derive reverse zone for '$($this.Cidr)'.")
    }

    [string[]] GetAdLookupCandidates() {
        $candidates = @($this.Cidr)
        $octets = $this.NetworkAddress.Value.Split('.')
        $levels = @(24, 16, 8)

        foreach ($level in $levels) {
            if ($level -gt $this.PrefixLength) {
                continue
            }

            $candidate = $null
            switch ($level) {
                24 { $candidate = '{0}.{1}.{2}.0/24' -f $octets[0], $octets[1], $octets[2] }
                16 { $candidate = '{0}.{1}.0.0/16' -f $octets[0], $octets[1] }
                8 { $candidate = '{0}.0.0.0/8' -f $octets[0] }
            }

            if ($candidate -notin $candidates) {
                $candidates += $candidate
            }
        }

        return $candidates
    }

    [string[]] Get24BlockBaseAddresses() {
        $blocks = @()
        $startNumber = $this.NetworkAddress.GetUInt32()
        $endNumber = $this.GetBroadcastAddress().GetUInt32()
        $blockBase = [uint32] ($startNumber - ($startNumber % 256))

        while ($blockBase -le $endNumber) {
            $blocks += [IPv4Address]::ConvertFromUInt32($blockBase)
            $blockBase = [uint32] ($blockBase + 256)
        }

        return $blocks
    }

    [string] ToString() {
        return $this.Cidr
    }
}
