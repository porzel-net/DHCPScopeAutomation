# Wraps a validated IPv4 address and provides conversion helpers for subnet calculations.
<#
.SYNOPSIS
Represents a validated IPv4 address.

.DESCRIPTION
Provides a small value object around IPv4 strings together with numeric
conversion and offset helpers used by subnet and DHCP calculations.

.NOTES
Methods:
- IPv4Address(value)
- ConvertToUInt32(value)
- ConvertFromUInt32(value)
- GetUInt32()
- AddOffset(offset)
- ToString()

.EXAMPLE
[IPv4Address]::new('10.20.30.10')
#>
class IPv4Address {
    [string] $Value

    IPv4Address([string] $value) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw [System.ArgumentException]::new('IPv4 address value is required.')
        }

        $normalized = $value.Trim()
        $ip = [System.Net.IPAddress]::Parse($normalized)
        if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            throw [System.ArgumentException]::new("Only IPv4 addresses are supported. Found '$value'.")
        }

        $this.Value = $ip.ToString()
    }

    hidden static [uint32] ConvertToUInt32([string] $ipAddress) {
        $parsed = [System.Net.IPAddress]::Parse($ipAddress)
        $bytes = $parsed.GetAddressBytes()
        [Array]::Reverse($bytes)
        return [BitConverter]::ToUInt32($bytes, 0)
    }

    hidden static [string] ConvertFromUInt32([uint32] $value) {
        $bytes = [BitConverter]::GetBytes($value)
        [Array]::Reverse($bytes)
        return ([System.Net.IPAddress]::new($bytes)).ToString()
    }

    <#
    .SYNOPSIS
    Returns the numeric UInt32 representation of the IPv4 address.
    .OUTPUTS
    System.UInt32
    #>
    [uint32] GetUInt32() {
        return [IPv4Address]::ConvertToUInt32($this.Value)
    }

    <#
    .SYNOPSIS
    Returns a new IPv4 address with the supplied offset applied.
    .OUTPUTS
    IPv4Address
    #>
    [IPv4Address] AddOffset([int] $offset) {
        $target = [uint32]([int64] $this.GetUInt32() + [int64] $offset)
        return [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($target))
    }

    <#
    .SYNOPSIS
    Returns the canonical string form of the address.
    .OUTPUTS
    System.String
    #>
    [string] ToString() {
        return $this.Value
    }
}
