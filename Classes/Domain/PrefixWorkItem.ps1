# Maps a NetBox prefix payload into the domain shape required for prefix onboarding.
class PrefixWorkItem {
    [int] $Id
    [IPv4Subnet] $PrefixSubnet
    [string] $Description
    [string] $DHCPType
    [string] $Domain
    [string] $SiteName
    [int] $SiteId
    [int] $DefaultGatewayId
    [IPv4Address] $DefaultGatewayAddress
    [string] $DnsName
    [string] $ValuemationSiteMandant
    [string] $ExistingTicketUrl

    PrefixWorkItem(
        [int] $id,
        [string] $prefix,
        [string] $description,
        [string] $dhcpType,
        [string] $domain,
        [string] $siteName,
        [int] $siteId,
        [int] $defaultGatewayId,
        [string] $defaultGatewayAddress,
        [string] $dnsName,
        [string] $valuemationSiteMandant,
        [string] $existingTicketUrl
    ) {
        if ($id -le 0) { throw [System.ArgumentOutOfRangeException]::new('id', 'Id must be positive.') }
        if ([string]::IsNullOrWhiteSpace($description)) { throw [System.ArgumentException]::new('Description is required.') }
        if ([string]::IsNullOrWhiteSpace($dhcpType)) { throw [System.ArgumentException]::new('DHCPType is required.') }
        if ([string]::IsNullOrWhiteSpace($domain)) { throw [System.ArgumentException]::new('Domain is required.') }
        if ([string]::IsNullOrWhiteSpace($siteName)) { throw [System.ArgumentException]::new('SiteName is required.') }
        if ($siteId -le 0) { throw [System.ArgumentOutOfRangeException]::new('siteId', 'SiteId must be positive.') }
        if ($defaultGatewayId -le 0) { throw [System.ArgumentOutOfRangeException]::new('defaultGatewayId', 'DefaultGatewayId must be positive.') }
        if ([string]::IsNullOrWhiteSpace($dnsName)) { throw [System.ArgumentException]::new('DnsName is required.') }
        if ([string]::IsNullOrWhiteSpace($valuemationSiteMandant)) { throw [System.ArgumentException]::new('ValuemationSiteMandant is required.') }

        $this.Id = $id
        $this.PrefixSubnet = [IPv4Subnet]::new($prefix)
        $this.Description = $description.Trim()
        $this.DHCPType = $dhcpType.Trim()
        $this.Domain = $domain.Trim().ToLowerInvariant()
        $this.SiteName = $siteName.Trim()
        $this.SiteId = $siteId
        $this.DefaultGatewayId = $defaultGatewayId
        $this.DefaultGatewayAddress = [IPv4Address]::new($defaultGatewayAddress)
        $this.DnsName = $dnsName.Trim()
        $this.ValuemationSiteMandant = $valuemationSiteMandant.Trim()
        $this.ExistingTicketUrl = $existingTicketUrl
    }

    [string] GetGatewayFqdn() {
        if ($this.DnsName.ToLowerInvariant().EndsWith($this.Domain.ToLowerInvariant())) {
            return $this.DnsName
        }

        return '{0}.{1}' -f $this.DnsName, $this.Domain
    }

    [string] GetIdentifier() {
        return $this.PrefixSubnet.Cidr
    }
}
