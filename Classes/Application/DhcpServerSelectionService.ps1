<#
.SYNOPSIS
Selects the effective DHCP server for prefix provisioning.

.DESCRIPTION
Encapsulates the environment-specific selection policy so the onboarding use
case asks for one server choice instead of knowing development, test, and
production routing rules.

.NOTES
Methods:
- DhcpServerSelectionService(dhcpServerAdapter)
- SelectServer(environment, adSite)

.EXAMPLE
$server = $selector.SelectServer($environment, 'muc-prod')
#>
class DhcpServerSelectionService {
    [DhcpServerAdapter] $DhcpServerAdapter

    DhcpServerSelectionService([DhcpServerAdapter] $dhcpServerAdapter) {
        $this.DhcpServerAdapter = $dhcpServerAdapter
    }

    <#
    .SYNOPSIS
    Resolves the DHCP target server for the current work item.

    .DESCRIPTION
    Applies the selection policy for development, test, and production. This
    keeps environment branching out of the prefix onboarding workflow.

    .PARAMETER environment
    The resolved execution environment.

    .PARAMETER adSite
    Observed AD site used for production routing.

    .OUTPUTS
    System.String
    #>
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
