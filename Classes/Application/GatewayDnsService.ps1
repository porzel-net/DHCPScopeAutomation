<#
.SYNOPSIS
Applies gateway and host DNS changes for prefix and IP workflows.

.DESCRIPTION
Provides the application-layer facade for DNS operations. It resolves the
required AD and reverse-zone context once and delegates concrete record changes
to the DNS adapter.

.NOTES
Methods:
- GatewayDnsService(activeDirectoryAdapter, dnsServerAdapter)
- ResolveDnsExecutionContext(subnet)
- EnsurePrefixGatewayDns(workItem)
- EnsureIpDns(workItem)
- RemoveIpDns(workItem)

.EXAMPLE
$gatewayDnsService.EnsurePrefixGatewayDns($prefixWorkItem)
#>
class GatewayDnsService {
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter
    [DnsServerAdapter] $DnsServerAdapter

    GatewayDnsService([ActiveDirectoryAdapter] $activeDirectoryAdapter, [DnsServerAdapter] $dnsServerAdapter) {
        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
        $this.DnsServerAdapter = $dnsServerAdapter
    }

    <#
    .SYNOPSIS
    Exposes the resolved DNS execution context for diagnostic logging.

    .PARAMETER subnet
    Subnet for which DNS context should be resolved.

    .OUTPUTS
    DnsExecutionContext
    #>
    [DnsExecutionContext] GetDnsExecutionContext([IPv4Subnet] $subnet) {
        return $this.ResolveDnsExecutionContext($subnet)
    }

    <#
    .SYNOPSIS
    Resolves the DNS execution context for one subnet.

    .DESCRIPTION
    Retrieves the current domain controller and the best matching reverse zone
    so downstream DNS methods can work with one stable context object.

    .PARAMETER subnet
    Subnet for which reverse DNS should be resolved.

    .OUTPUTS
    DnsExecutionContext
    #>
    # Internal facade step that resolves all DNS execution dependencies once and hides AD/DNS lookup choreography from use cases.
    hidden [DnsExecutionContext] ResolveDnsExecutionContext([IPv4Subnet] $subnet) {
        Write-Verbose -Message ("Resolving DNS execution context for subnet '{0}'." -f $subnet.Cidr)
        $domainController = $this.ActiveDirectoryAdapter.GetDomainControllerName()
        Write-Verbose -Message ("Selected domain controller '{0}' for subnet '{1}'." -f $domainController, $subnet.Cidr)
        $reverseZone = $this.DnsServerAdapter.FindBestReverseZoneName($subnet, $domainController)

        if ([string]::IsNullOrWhiteSpace($reverseZone)) {
            Write-Debug -Message ("No reverse zone could be resolved for subnet '{0}' via domain controller '{1}'." -f $subnet.Cidr, $domainController)
            throw [System.InvalidOperationException]::new("No reverse zone found for prefix '$($subnet.Cidr)'.")
        }

        Write-Verbose -Message ("Resolved reverse zone '{0}' for subnet '{1}'." -f $reverseZone, $subnet.Cidr)
        return [DnsExecutionContext]::new($domainController, $reverseZone)
    }

    <#
    .SYNOPSIS
    Ensures gateway DNS records for a provisioned prefix.

    .DESCRIPTION
    Creates or refreshes the forward and reverse DNS records for the configured
    default gateway of a prefix.

    .PARAMETER workItem
    Prefix work item that carries gateway and naming data.
    #>
    # Facade method for prefix onboarding: the application layer asks for gateway DNS as one intent, not as individual DNS operations.
    [void] EnsurePrefixGatewayDns([PrefixWorkItem] $workItem) {
        $dnsContext = $this.ResolveDnsExecutionContext($workItem.PrefixSubnet)
        Write-Debug -Message ("Ensuring gateway DNS for prefix '{0}' using DC '{1}', reverse zone '{2}', gateway '{3}', dnsName '{4}'." -f $workItem.GetIdentifier(), $dnsContext.DomainController, $dnsContext.ReverseZone, $workItem.DefaultGatewayAddress.Value, $workItem.DnsName)

        $this.DnsServerAdapter.EnsureDnsRecordsForIp(
            $dnsContext.DomainController,
            $workItem.Domain,
            $workItem.DnsName,
            $workItem.DefaultGatewayAddress,
            $dnsContext.ReverseZone,
            $workItem.GetGatewayFqdn()
        )
    }

    <#
    .SYNOPSIS
    Ensures DNS records for an onboarded IP address.

    .DESCRIPTION
    Validates that the work item has a DNS name and then ensures the matching
    A and PTR records through the DNS facade boundary.

    .PARAMETER workItem
    IP address work item that should receive DNS records.
    #>
    # Facade method for IP onboarding so future DNS-specific extensions stay behind one stable boundary.
    [void] EnsureIpDns([IpAddressWorkItem] $workItem) {
        if ([string]::IsNullOrWhiteSpace($workItem.DnsName)) {
            throw [System.InvalidOperationException]::new("DNS name is missing for IP '$($workItem.IpAddress.Value)'.")
        }

        $dnsContext = $this.ResolveDnsExecutionContext($workItem.PrefixSubnet)
        Write-Debug -Message ("Ensuring IP DNS for '{0}' using DC '{1}', reverse zone '{2}', dnsName '{3}'." -f $workItem.GetIdentifier(), $dnsContext.DomainController, $dnsContext.ReverseZone, $workItem.DnsName)

        $this.DnsServerAdapter.EnsureDnsRecordsForIp(
            $dnsContext.DomainController,
            $workItem.Domain,
            $workItem.DnsName,
            $workItem.IpAddress,
            $dnsContext.ReverseZone,
            $workItem.GetFqdn()
        )
    }

    <#
    .SYNOPSIS
    Removes DNS records for a decommissioned IP address.

    .DESCRIPTION
    Resolves the DNS context and deletes the forward and reverse records that
    belong to the supplied IP address.

    .PARAMETER workItem
    IP address work item that should be removed from DNS.
    #>
    # Facade method for IP decommissioning; keeps deletion semantics centralized for later lifecycle growth.
    [void] RemoveIpDns([IpAddressWorkItem] $workItem) {
        $dnsContext = $this.ResolveDnsExecutionContext($workItem.PrefixSubnet)
        Write-Debug -Message ("Removing IP DNS for '{0}' using DC '{1}' and reverse zone '{2}'." -f $workItem.GetIdentifier(), $dnsContext.DomainController, $dnsContext.ReverseZone)

        $this.DnsServerAdapter.RemoveDnsRecordsForIp(
            $dnsContext.DomainController,
            $workItem.Domain,
            $dnsContext.ReverseZone,
            $workItem.IpAddress
        )
    }
}
