$moduleRoot = $PSScriptRoot

. (Join-Path -Path $moduleRoot -ChildPath 'Classes/AllClasses.ps1')

. (Join-Path -Path $moduleRoot -ChildPath 'Private/Import-AutomationDependencies.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Private/Write-AutomationLogEntry.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Private/Write-AutomationRunLog.ps1')
. (Join-Path -Path $moduleRoot -ChildPath 'Private/Convert-BatchRunSummaryToPublicObject.ps1')

. (Join-Path -Path $moduleRoot -ChildPath 'Public/Start-DhcpScopeAutomation.ps1')

Export-ModuleMember -Function 'Start-DhcpScopeAutomation'
