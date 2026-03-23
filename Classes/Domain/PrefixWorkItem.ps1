# Maps a NetBox prefix payload into the domain shape required for prefix onboarding.
<#
.SYNOPSIS
Represents one prefix work item loaded from NetBox.

.DESCRIPTION
Stores the business data required for prerequisite validation, DHCP provisioning,
gateway DNS handling, journaling, and status updates for a network prefix.

.NOTES
Methods:
- PrefixWorkItem(...)
- GetGatewayFqdn()
- GetIdentifier()

.EXAMPLE
[PrefixWorkItem]::new(7, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp', 'MUC', 17, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed')
#>
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
    [string] $RoutingType

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
        [string] $existingTicketUrl,
        [string] $routingType
    ) {
        if ($id -le 0) { throw [System.ArgumentOutOfRangeException]::new('id', 'Id must be positive.') }
        if ([string]::IsNullOrWhiteSpace($description)) { throw [System.ArgumentException]::new('Description is required.') }
        if ([string]::IsNullOrWhiteSpace($dhcpType)) { throw [System.ArgumentException]::new('DHCPType is required.') }
        if ([string]::IsNullOrWhiteSpace($domain)) { throw [System.ArgumentException]::new('Domain is required.') }
        if ([string]::IsNullOrWhiteSpace($siteName)) { throw [System.ArgumentException]::new('SiteName is required.') }
        if ($siteId -le 0) { throw [System.ArgumentOutOfRangeException]::new('siteId', 'SiteId must be positive.') }
        if ([string]::IsNullOrWhiteSpace($valuemationSiteMandant)) { throw [System.ArgumentException]::new('ValuemationSiteMandant is required.') }

        $this.Id = $id
        $this.PrefixSubnet = [IPv4Subnet]::new($prefix)
        $this.Description = $description.Trim()
        $this.DHCPType = $dhcpType.Trim()
        $this.Domain = $domain.Trim().ToLowerInvariant()
        $this.SiteName = $siteName.Trim()
        $this.SiteId = $siteId
        $this.ValuemationSiteMandant = $valuemationSiteMandant.Trim()
        $this.ExistingTicketUrl = $existingTicketUrl
        $this.RoutingType = $this.NormalizeRoutingType($routingType)
        $this.SetGatewayConfiguration($defaultGatewayId, $defaultGatewayAddress, $dnsName)
    }

    hidden [bool] IsNotRoutedNoDhcp() {
        return $this.DHCPType.ToLowerInvariant() -eq 'no_dhcp' -and $this.RoutingType -eq 'not_routed'
    }

    hidden [string] NormalizeRoutingType([string] $routingType) {
        if ([string]::IsNullOrWhiteSpace($routingType)) {
            return 'routed'
        }

        return $routingType.Trim().ToLowerInvariant()
    }

    hidden [void] SetGatewayConfiguration(
        [int] $defaultGatewayId,
        [string] $defaultGatewayAddress,
        [string] $dnsName
    ) {
        if (-not $this.RequiresDefaultGateway()) {
            return
        }

        if ($defaultGatewayId -le 0) { throw [System.ArgumentOutOfRangeException]::new('defaultGatewayId', 'DefaultGatewayId must be positive.') }
        if ([string]::IsNullOrWhiteSpace($defaultGatewayAddress)) { throw [System.ArgumentException]::new('DefaultGatewayAddress is required.') }
        if ([string]::IsNullOrWhiteSpace($dnsName)) { throw [System.ArgumentException]::new('DnsName is required.') }

        $this.DefaultGatewayId = $defaultGatewayId
        $this.DefaultGatewayAddress = [IPv4Address]::new($defaultGatewayAddress)
        $this.DnsName = $dnsName.Trim()
    }

    [bool] RequiresDefaultGateway() {
        return -not $this.IsNotRoutedNoDhcp()
    }

    [bool] ShouldEnsureGatewayDns() {
        return $this.RequiresDefaultGateway()
    }

    <#
    .SYNOPSIS
    Returns the fully qualified gateway DNS name.
    .OUTPUTS
    System.String
    #>
    [string] GetGatewayFqdn() {
        if (-not $this.ShouldEnsureGatewayDns() -or [string]::IsNullOrWhiteSpace($this.DnsName)) {
            return $null
        }

        if ($this.DnsName.ToLowerInvariant().EndsWith($this.Domain.ToLowerInvariant())) {
            return $this.DnsName
        }

        return '{0}.{1}' -f $this.DnsName, $this.Domain
    }

    <#
    .SYNOPSIS
    Returns the stable identifier for the prefix work item.
    .OUTPUTS
    System.String
    #>
    [string] GetIdentifier() {
        return $this.PrefixSubnet.Cidr
    }
}
