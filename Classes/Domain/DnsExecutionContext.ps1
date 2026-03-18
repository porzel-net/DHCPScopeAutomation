# Bundles resolved DNS execution dependencies so downstream services do not repeat lookups.
<#
.SYNOPSIS
Stores the resolved DNS execution context for one subnet.

.DESCRIPTION
Carries the domain controller and reverse zone that downstream DNS operations
need so those lookups happen once at the facade boundary.

.NOTES
Methods:
- DnsExecutionContext(domainController, reverseZone)

.EXAMPLE
[DnsExecutionContext]::new('dc01.example.test', '30.20.10.in-addr.arpa')
#>
class DnsExecutionContext {
    [string] $DomainController
    [string] $ReverseZone

    DnsExecutionContext([string] $domainController, [string] $reverseZone) {
        if ([string]::IsNullOrWhiteSpace($domainController)) {
            throw [System.ArgumentException]::new('DomainController is required.')
        }

        if ([string]::IsNullOrWhiteSpace($reverseZone)) {
            throw [System.ArgumentException]::new('ReverseZone is required.')
        }

        $this.DomainController = $domainController
        $this.ReverseZone = $reverseZone
    }
}
