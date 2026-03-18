# Maps a NetBox IP address payload into the domain shape required for DNS lifecycle processing.
<#
.SYNOPSIS
Represents one IP address work item loaded from NetBox.

.DESCRIPTION
Stores the business data required for IP DNS onboarding and decommissioning,
including the IP address, DNS name, current status, and parent prefix.

.NOTES
Methods:
- IpAddressWorkItem(...)
- GetIdentifier()
- GetFqdn()

.EXAMPLE
[IpAddressWorkItem]::new(20, '10.20.30.10', 'onboarding_open_dns', 'host102030', 'de.mtu.corp', '10.20.30.0/24')
#>
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

    <#
    .SYNOPSIS
    Returns the stable identifier for the IP work item.
    .OUTPUTS
    System.String
    #>
    [string] GetIdentifier() {
        return $this.IpAddress.Value
    }

    <#
    .SYNOPSIS
    Returns the fully qualified DNS name for the IP work item.
    .OUTPUTS
    System.String
    #>
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
