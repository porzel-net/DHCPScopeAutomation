# Describes a DHCP exclusion range and whether failing to apply it should abort the scope setup.
class DhcpExclusionRange {
    [IPv4Address] $StartAddress
    [IPv4Address] $EndAddress
    [bool] $MustSucceed

    DhcpExclusionRange([IPv4Address] $startAddress, [IPv4Address] $endAddress) {
        $this.Initialize($startAddress, $endAddress, $true)
    }

    DhcpExclusionRange([IPv4Address] $startAddress, [IPv4Address] $endAddress, [bool] $mustSucceed) {
        $this.Initialize($startAddress, $endAddress, $mustSucceed)
    }

    hidden [void] Initialize([IPv4Address] $startAddress, [IPv4Address] $endAddress, [bool] $mustSucceed) {
        if ($null -eq $startAddress) {
            throw [System.ArgumentNullException]::new('startAddress')
        }

        if ($null -eq $endAddress) {
            throw [System.ArgumentNullException]::new('endAddress')
        }

        if ($startAddress.GetUInt32() -gt $endAddress.GetUInt32()) {
            throw [System.ArgumentException]::new('Start address must be less than or equal to end address.')
        }

        $this.StartAddress = $startAddress
        $this.EndAddress = $endAddress
        $this.MustSucceed = $mustSucceed
    }
}
