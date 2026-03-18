# Maps a NetBox IP address payload into the domain shape required for DNS lifecycle processing.
class IpAddressWorkItem {
    [int] $Id
    [IPv4Address] $IpAddress
    [string] $Status
    [string] $DnsName
    [string] $Domain
    [IPv4Subnet] $PrefixSubnet

    IpAddressWorkItem(
        [int] $id,
        [string] $ipAddress,
        [string] $status,
        [string] $dnsName,
        [string] $domain,
        [string] $prefix
    ) {
        if ($id -le 0) { throw [System.ArgumentOutOfRangeException]::new('id', 'Id must be positive.') }
        if ([string]::IsNullOrWhiteSpace($status)) { throw [System.ArgumentException]::new('Status is required.') }
        if ([string]::IsNullOrWhiteSpace($domain)) { throw [System.ArgumentException]::new('Domain is required.') }
        if ([string]::IsNullOrWhiteSpace($prefix)) { throw [System.ArgumentException]::new('Prefix is required.') }

        $this.Id = $id
        $this.IpAddress = [IPv4Address]::new($ipAddress)
        $this.Status = $status.Trim()
        $this.DnsName = $dnsName
        $this.Domain = $domain.Trim().ToLowerInvariant()
        $this.PrefixSubnet = [IPv4Subnet]::new($prefix)
    }

    [string] GetIdentifier() {
        return $this.IpAddress.Value
    }

    [string] GetFqdn() {
        if ([string]::IsNullOrWhiteSpace($this.DnsName)) {
            return $null
        }

        if ($this.DnsName.ToLowerInvariant().EndsWith($this.Domain)) {
            return $this.DnsName
        }

        return '{0}.{1}' -f $this.DnsName, $this.Domain
    }
}
