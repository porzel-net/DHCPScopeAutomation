# Holds the fully constructed runtime graph for execution and cross-cutting services.
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
