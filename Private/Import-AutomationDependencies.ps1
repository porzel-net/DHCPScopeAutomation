<#
.SYNOPSIS
Imports the Windows infrastructure modules required by the automation.

.DESCRIPTION
Loads the `ActiveDirectory`, `DhcpServer`, and `DnsServer` modules and fails fast
with a descriptive exception when a dependency is not available in the session.

.OUTPUTS
None.

.EXAMPLE
Import-AutomationDependencies
#>
function Import-AutomationDependencies {
    [CmdletBinding()]
    param()

    $requiredModules = @(
        'ActiveDirectory'
        'DhcpServer'
        'DnsServer'
    )

    foreach ($moduleName in $requiredModules) {
        try {
            Import-Module -Name $moduleName -ErrorAction Stop
        }
        catch {
            throw [System.InvalidOperationException]::new(
                ("Required PowerShell module '{0}' could not be imported. Install or enable the dependency before running DHCPScopeAutomation. {1}" -f $moduleName, $_.Exception.Message)
            )
        }
    }
}
