# Selects the target DHCP server for a prefix based on environment, site, and directory context.
class DhcpServerSelectionService {
    [DhcpServerAdapter] $DhcpServerAdapter

    DhcpServerSelectionService([DhcpServerAdapter] $dhcpServerAdapter) {
        $this.DhcpServerAdapter = $dhcpServerAdapter
    }

    [string] SelectServer([EnvironmentContext] $environment, [string] $adSite) {
        if ($environment.IsDevelopment()) {
            return $this.DhcpServerAdapter.GetPrimaryServerForSite('muc', $true)
        }

        if ($environment.IsTest()) {
            return $this.DhcpServerAdapter.GetPrimaryServerForSite('muc', $false)
        }

        return $this.DhcpServerAdapter.GetPrimaryServerForSite($adSite, $false)
    }
}
