<#
.SYNOPSIS
Represents the fully resolved runtime container for one execution.

.DESCRIPTION
Holds the environment, recipients, coordinator, and cross-cutting services that
were assembled by the composition root. The runtime provides a narrow execution
surface to the public entry point.

.NOTES
Methods:
- AutomationRuntime(environment, emailRecipients, coordinator, logService)
- Execute(sendFailureMail, skipPrefixOnboarding, skipIpDnsOnboarding, skipIpDnsDecommissioning)

.EXAMPLE
$summaries = $runtime.Execute($true, $false, $false, $false)
#>
class AutomationRuntime {
    [EnvironmentContext] $Environment
    [string[]] $EmailRecipients
    [AutomationCoordinator] $Coordinator
    [WorkItemLogService] $LogService

    AutomationRuntime(
        [EnvironmentContext] $environment,
        [string[]] $emailRecipients,
        [AutomationCoordinator] $coordinator,
        [WorkItemLogService] $logService
    ) {
        $normalizedRecipients = @($emailRecipients | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })

        if ($null -eq $environment) {
            throw [System.ArgumentNullException]::new('environment')
        }

        if (-not $normalizedRecipients -or $normalizedRecipients.Count -eq 0) {
            throw [System.ArgumentException]::new('EmailRecipients are required.')
        }

        if ($null -eq $coordinator) {
            throw [System.ArgumentNullException]::new('coordinator')
        }

        if ($null -eq $logService) {
            throw [System.ArgumentNullException]::new('logService')
        }

        $this.Environment = $environment
        $this.EmailRecipients = $normalizedRecipients
        $this.Coordinator = $coordinator
        $this.LogService = $logService
    }

    <#
    .SYNOPSIS
    Executes the configured automation runtime.

    .DESCRIPTION
    Delegates to the application coordinator while binding in the resolved
    runtime environment and notification recipients.

    .OUTPUTS
    BatchRunSummary[]
    #>
    # Thin runtime facade that binds resolved configuration to the coordinator without exposing object-graph construction to callers.
    [BatchRunSummary[]] Execute(
        [bool] $sendFailureMail,
        [bool] $skipPrefixOnboarding,
        [bool] $skipIpDnsOnboarding,
        [bool] $skipIpDnsDecommissioning
    ) {
        return $this.Coordinator.Run(
            $this.Environment,
            $this.EmailRecipients,
            $sendFailureMail,
            $skipPrefixOnboarding,
            $skipIpDnsOnboarding,
            $skipIpDnsDecommissioning
        )
    }
}
