# Represents the usable address range that should be handed out by a DHCP scope.
<#
.SYNOPSIS
Represents the usable DHCP address range for a subnet.

.DESCRIPTION
Combines start, end, gateway, broadcast, and reserved address information in one
value object so DHCP provisioning code receives fully derived input.

.NOTES
Methods:
- DhcpRange(startAddress, endAddress, gatewayAddress, broadcastAddress, reservedAfterGateway)
- FromSubnet(subnet, dhcpType)

.EXAMPLE
[DhcpRange]::FromSubnet([IPv4Subnet]::new('10.20.30.0/24'), 'dhcp_dynamic')
#>
class DhcpRange {
    [IPv4Address] $StartAddress
    [IPv4Address] $EndAddress
    [IPv4Address] $GatewayAddress
    [IPv4Address] $BroadcastAddress
    [int] $ReservedAfterGateway

    DhcpRange(
        [IPv4Address] $startAddress,
        [IPv4Address] $endAddress,
        [IPv4Address] $gatewayAddress,
        [IPv4Address] $broadcastAddress,
        [int] $reservedAfterGateway
    ) {
        if ($null -eq $startAddress) { throw [System.ArgumentNullException]::new('startAddress') }
        if ($null -eq $endAddress) { throw [System.ArgumentNullException]::new('endAddress') }
        if ($null -eq $gatewayAddress) { throw [System.ArgumentNullException]::new('gatewayAddress') }
        if ($null -eq $broadcastAddress) { throw [System.ArgumentNullException]::new('broadcastAddress') }
        if ($startAddress.GetUInt32() -gt $endAddress.GetUInt32()) {
            throw [System.ArgumentException]::new('StartAddress must be less than or equal to EndAddress.')
        }

        $this.StartAddress = $startAddress
        $this.EndAddress = $endAddress
        $this.GatewayAddress = $gatewayAddress
        $this.BroadcastAddress = $broadcastAddress
        $this.ReservedAfterGateway = $reservedAfterGateway
    }

    <#
    .SYNOPSIS
    Derives the DHCP range for a subnet and DHCP type.

    .DESCRIPTION
    Calculates the first usable address, last assignable address, gateway, and
    reserved capacity according to the DHCP model.

    .OUTPUTS
    DhcpRange
    #>
    static [DhcpRange] FromSubnet([IPv4Subnet] $subnet, [string] $dhcpType) {
        if ($null -eq $subnet) {
            throw [System.ArgumentNullException]::new('subnet')
        }

        if ([string]::IsNullOrWhiteSpace($dhcpType)) {
            throw [System.ArgumentException]::new('dhcpType is required.')
        }

        $hostBits = 32 - $subnet.PrefixLength
        $totalAddresses = [uint32] [math]::Pow(2, $hostBits)

        $networkNumber = $subnet.NetworkAddress.GetUInt32()
        $broadcastNumber = [uint32] ($networkNumber + $totalAddresses - 1)
        $gatewayNumber = [uint32] ($broadcastNumber - 1)
        $reservedCount = 0

        if ($subnet.PrefixLength -ge 22 -and $subnet.PrefixLength -le 25) {
            $reservedCount = 5
        }

        $startNumber = [uint32] ($networkNumber + 1)
        $endNumber = [uint32] ($gatewayNumber - $reservedCount - 1)

        if ($dhcpType -eq 'dhcp_static') {
            $endNumber = $startNumber
        }

        return [DhcpRange]::new(
            [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($startNumber)),
            [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($endNumber)),
            [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($gatewayNumber)),
            [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($broadcastNumber)),
            $reservedCount
        )
    }
}
