# Applies gateway and host DNS changes for prefix and IP lifecycle operations.
class GatewayDnsService {
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter
    [DnsServerAdapter] $DnsServerAdapter

    GatewayDnsService([ActiveDirectoryAdapter] $activeDirectoryAdapter, [DnsServerAdapter] $dnsServerAdapter) {
        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
        $this.DnsServerAdapter = $dnsServerAdapter
    }

    # Internal facade step that resolves all DNS execution dependencies once and hides AD/DNS lookup choreography from use cases.
    hidden [DnsExecutionContext] ResolveDnsExecutionContext([IPv4Subnet] $subnet) {
        $domainController = $this.ActiveDirectoryAdapter.GetDomainControllerName()
        $reverseZone = $this.DnsServerAdapter.FindBestReverseZoneName($subnet, $domainController)

        if ([string]::IsNullOrWhiteSpace($reverseZone)) {
            throw [System.InvalidOperationException]::new("No reverse zone found for prefix '$($subnet.Cidr)'.")
        }

        return [DnsExecutionContext]::new($domainController, $reverseZone)
    }

    # Facade method for prefix onboarding: the application layer asks for gateway DNS as one intent, not as individual DNS operations.
    [void] EnsurePrefixGatewayDns([PrefixWorkItem] $workItem) {
        $dnsContext = $this.ResolveDnsExecutionContext($workItem.PrefixSubnet)

        $this.DnsServerAdapter.EnsureDnsRecordsForIp(
            $dnsContext.DomainController,
            $workItem.Domain,
            $workItem.DnsName,
            $workItem.DefaultGatewayAddress,
            $dnsContext.ReverseZone,
            $workItem.GetGatewayFqdn()
        )
    }

    # Facade method for IP onboarding so future DNS-specific extensions stay behind one stable boundary.
    [void] EnsureIpDns([IpAddressWorkItem] $workItem) {
        if ([string]::IsNullOrWhiteSpace($workItem.DnsName)) {
            throw [System.InvalidOperationException]::new("DNS name is missing for IP '$($workItem.IpAddress.Value)'.")
        }

        $dnsContext = $this.ResolveDnsExecutionContext($workItem.PrefixSubnet)

        $this.DnsServerAdapter.EnsureDnsRecordsForIp(
            $dnsContext.DomainController,
            $workItem.Domain,
            $workItem.DnsName,
            $workItem.IpAddress,
            $dnsContext.ReverseZone,
            $workItem.GetFqdn()
        )
    }

    # Facade method for IP decommissioning; keeps deletion semantics centralized for later lifecycle growth.
    [void] RemoveIpDns([IpAddressWorkItem] $workItem) {
        $dnsContext = $this.ResolveDnsExecutionContext($workItem.PrefixSubnet)

        $this.DnsServerAdapter.RemoveDnsRecordsForIp(
            $dnsContext.DomainController,
            $workItem.Domain,
            $dnsContext.ReverseZone,
            $workItem.IpAddress
        )
    }
}
