# Converts a prefix work item into the DHCP-specific configuration needed by the infrastructure adapter.
class DhcpScopeDefinition {
    [string] $Name
    [IPv4Subnet] $Subnet
    [string] $SubnetMask
    [DhcpRange] $Range
    [string] $DnsDomain
    [int] $LeaseDurationDays
    [bool] $ConfigureDynamicDns
    [DhcpExclusionRange[]] $ExclusionRanges

    DhcpScopeDefinition(
        [string] $name,
        [IPv4Subnet] $subnet,
        [string] $subnetMask,
        [DhcpRange] $range,
        [string] $dnsDomain,
        [int] $leaseDurationDays,
        [bool] $configureDynamicDns,
        [DhcpExclusionRange[]] $exclusionRanges
    ) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw [System.ArgumentException]::new('Name is required.') }
        if ($null -eq $subnet) { throw [System.ArgumentNullException]::new('subnet') }
        if ([string]::IsNullOrWhiteSpace($subnetMask)) { throw [System.ArgumentException]::new('SubnetMask is required.') }
        if ($null -eq $range) { throw [System.ArgumentNullException]::new('range') }
        if ([string]::IsNullOrWhiteSpace($dnsDomain)) { throw [System.ArgumentException]::new('DnsDomain is required.') }

        $this.Name = $name
        $this.Subnet = $subnet
        $this.SubnetMask = $subnetMask
        $this.Range = $range
        $this.DnsDomain = $dnsDomain
        $this.LeaseDurationDays = $leaseDurationDays
        $this.ConfigureDynamicDns = $configureDynamicDns
        $this.ExclusionRanges = $exclusionRanges
    }

    static [DhcpScopeDefinition] FromPrefixWorkItem([PrefixWorkItem] $workItem) {
        if ($null -eq $workItem) {
            throw [System.ArgumentNullException]::new('workItem')
        }

        $mappedType = ''
        switch ($workItem.DHCPType) {
            'dhcp_static' { $mappedType = 'STATIC' }
            'dhcp_dynamic' { $mappedType = 'DYNAMIC' }
            'no_dhcp' { $mappedType = 'NODHCP' }
            default { throw [System.InvalidOperationException]::new("Unsupported DHCP type '$($workItem.DHCPType)'.") }
        }

        $scopeName = '{0} {1} {2} {3}' -f $mappedType, $workItem.PrefixSubnet.Cidr, $workItem.SiteName, $workItem.Description
        $calculatedRange = [DhcpRange]::FromSubnet($workItem.PrefixSubnet, $workItem.DHCPType)
        $exclusions = @()
        $strictDynamicExclusions = $workItem.PrefixSubnet.PrefixLength -eq 24

        if ($workItem.DHCPType -eq 'dhcp_static') {
            $exclusions += [DhcpExclusionRange]::new($calculatedRange.StartAddress, $calculatedRange.EndAddress, $true)
        }
        elseif ($workItem.DHCPType -eq 'dhcp_dynamic' -and $workItem.PrefixSubnet.PrefixLength -le 24) {
            foreach ($blockBase in $workItem.PrefixSubnet.Get24BlockBaseAddresses()) {
                $blockAddress = [IPv4Address]::new($blockBase)
                $blockNumber = $blockAddress.GetUInt32()
                $exclusions += [DhcpExclusionRange]::new(
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($blockNumber)),
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($blockNumber)),
                    $strictDynamicExclusions
                )
                $exclusions += [DhcpExclusionRange]::new(
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32([uint32] ($blockNumber + 1))),
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32([uint32] ($blockNumber + 1))),
                    $strictDynamicExclusions
                )
                $exclusions += [DhcpExclusionRange]::new(
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32([uint32] ($blockNumber + 249))),
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32([uint32] ($blockNumber + 255))),
                    $strictDynamicExclusions
                )
            }
        }

        return [DhcpScopeDefinition]::new(
            $scopeName,
            $workItem.PrefixSubnet,
            $workItem.PrefixSubnet.GetSubnetMaskString(),
            $calculatedRange,
            $workItem.Domain,
            3,
            $workItem.DHCPType -eq 'dhcp_dynamic',
            $exclusions
        )
    }
}
