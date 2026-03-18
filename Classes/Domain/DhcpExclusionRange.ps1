# Describes a DHCP exclusion range and whether failing to apply it should abort the scope setup.
<#
.SYNOPSIS
Represents a DHCP exclusion range.

.DESCRIPTION
Stores the excluded address interval together with a flag that defines whether
the exclusion must succeed or may be treated as best effort.

.NOTES
Methods:
- DhcpExclusionRange(startAddress, endAddress)
- DhcpExclusionRange(startAddress, endAddress, mustSucceed)
- Initialize(startAddress, endAddress, mustSucceed)

.EXAMPLE
[DhcpExclusionRange]::new([IPv4Address]::new('10.20.30.1'), [IPv4Address]::new('10.20.30.1'), $true)
#>
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

    <#
    .SYNOPSIS
    Initializes the exclusion range and strictness flag.
    .OUTPUTS
    System.Void
    #>
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
