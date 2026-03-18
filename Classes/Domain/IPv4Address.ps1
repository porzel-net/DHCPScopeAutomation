# Wraps a validated IPv4 address and provides conversion helpers for subnet calculations.
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

    [uint32] GetUInt32() {
        return [IPv4Address]::ConvertToUInt32($this.Value)
    }

    [IPv4Address] AddOffset([int] $offset) {
        $target = [uint32]([int64] $this.GetUInt32() + [int64] $offset)
        return [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($target))
    }

    [string] ToString() {
        return $this.Value
    }
}
