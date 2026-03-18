# Bundles resolved DNS execution dependencies so downstream services do not repeat lookups.
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
