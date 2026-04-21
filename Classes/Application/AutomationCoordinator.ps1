<#
.SYNOPSIS
Coordinates all enabled batch use cases for one automation run.

.DESCRIPTION
Acts as the facade over the application layer. The caller invokes one run
operation while the coordinator sequences prefix onboarding, IP DNS onboarding,
IP DNS decommissioning, and optional failure notification handling.

.NOTES
Methods:
- AutomationCoordinator(prefixOnboardingService, ipDnsOnboardingService, ipDnsDecommissioningService, batchNotificationService)
- Run(environment, emailRecipients, sendFailureMail, skipPrefixOnboarding, skipIpDnsOnboarding, skipIpDnsDecommissioning)

.EXAMPLE
$summaries = $coordinator.Run($environment, $recipients, $true, $false, $false, $false)
#>
class AutomationCoordinator {
    [PrefixOnboardingService] $PrefixOnboardingService
    [IpDnsLifecycleService] $IpDnsOnboardingService
    [IpDnsLifecycleService] $IpDnsDecommissioningService
    [BatchNotificationService] $BatchNotificationService

    AutomationCoordinator(
        [PrefixOnboardingService] $prefixOnboardingService,
        [IpDnsLifecycleService] $ipDnsOnboardingService,
        [IpDnsLifecycleService] $ipDnsDecommissioningService,
        [BatchNotificationService] $batchNotificationService
    ) {
        $this.PrefixOnboardingService = $prefixOnboardingService
        $this.IpDnsOnboardingService = $ipDnsOnboardingService
        $this.IpDnsDecommissioningService = $ipDnsDecommissioningService
        $this.BatchNotificationService = $batchNotificationService
    }

    <#
    .SYNOPSIS
    Executes all enabled application workflows for the current runtime.

    .DESCRIPTION
    Invokes the configured batch services in their operational order and,
    optionally, sends a grouped failure summary mail. Notification failures are
    converted into an additional batch summary so the run remains observable.

    .PARAMETER environment
    Runtime environment that scopes the work item queries and infrastructure behavior.

    .PARAMETER emailRecipients
    Recipients for grouped failure notifications.

    .PARAMETER sendFailureMail
    Controls whether the failure summary mail should be sent after processing.

    .PARAMETER skipPrefixOnboarding
    Skips prefix onboarding when set to `$true`.

    .PARAMETER skipIpDnsOnboarding
    Skips IP DNS onboarding when set to `$true`.

    .PARAMETER skipIpDnsDecommissioning
    Skips IP DNS decommissioning when set to `$true`.

    .OUTPUTS
    BatchRunSummary[]

    .EXAMPLE
    $coordinator.Run($environment, @('ops@example.com'), $true, $false, $true, $false)
    #>
    # Facade over the enabled use cases. The caller sees one run method while the coordinator sequences the internal workflows.
    [BatchRunSummary[]] Run(
        [EnvironmentContext] $environment,
        [string[]] $emailRecipients,
        [bool] $sendFailureMail,
        [bool] $skipPrefixOnboarding,
        [bool] $skipIpDnsOnboarding,
        [bool] $skipIpDnsDecommissioning
    ) {
        $summaries = @()
        $runConfigurationMessage = "Coordinator run configuration: Environment='$($environment.Name)', SendFailureMail=$sendFailureMail, SkipPrefixOnboarding=$skipPrefixOnboarding, SkipIpDnsOnboarding=$skipIpDnsOnboarding, SkipIpDnsDecommissioning=$skipIpDnsDecommissioning."
        Write-Verbose -Message $runConfigurationMessage

        if (-not $skipPrefixOnboarding) {
            $prefixSummary = $this.PrefixOnboardingService.ProcessBatch($environment)
            $prefixSummary.AddAudit('Debug', $runConfigurationMessage)
            $prefixSummary.AddAudit('Debug', "Coordinator executed PrefixOnboarding with SuccessCount=$($prefixSummary.SuccessCount), FailureCount=$($prefixSummary.FailureCount).")
            $summaries += $prefixSummary
        }
        else {
            Write-Verbose -Message 'Skipping PrefixOnboarding service execution.'
        }

        if (-not $skipIpDnsOnboarding) {
            $ipOnboardingSummary = $this.IpDnsOnboardingService.ProcessBatch($environment)
            $ipOnboardingSummary.AddAudit('Debug', $runConfigurationMessage)
            $ipOnboardingSummary.AddAudit('Debug', "Coordinator executed IpDnsOnboarding with SuccessCount=$($ipOnboardingSummary.SuccessCount), FailureCount=$($ipOnboardingSummary.FailureCount).")
            $summaries += $ipOnboardingSummary
        }
        else {
            Write-Verbose -Message 'Skipping IpDnsOnboarding service execution.'
        }

        if (-not $skipIpDnsDecommissioning) {
            $ipDecommissioningSummary = $this.IpDnsDecommissioningService.ProcessBatch($environment)
            $ipDecommissioningSummary.AddAudit('Debug', $runConfigurationMessage)
            $ipDecommissioningSummary.AddAudit('Debug', "Coordinator executed IpDnsDecommissioning with SuccessCount=$($ipDecommissioningSummary.SuccessCount), FailureCount=$($ipDecommissioningSummary.FailureCount).")
            $summaries += $ipDecommissioningSummary
        }
        else {
            Write-Verbose -Message 'Skipping IpDnsDecommissioning service execution.'
        }

        if ($sendFailureMail) {
            try {
                $issueCount = @(
                    foreach ($summary in @($summaries)) {
                        foreach ($issue in @($summary.Issues)) {
                            $issue
                        }
                    }
                ).Count
                Write-Verbose -Message ("Sending failure summary mail evaluation with {0} issue(s)." -f $issueCount)
                $this.BatchNotificationService.SendFailureSummary($emailRecipients, $summaries)
            }
            catch {
                $notificationSummary = [BatchRunSummary]::new('FailureNotification')
                $notificationSummary.AddFailure(
                    [OperationIssue]::new(
                        'Notification',
                        'FailureSummaryMail',
                        "Failed to send failure summary mail. $($_.Exception.Message)",
                        $_.Exception.ToString(),
                        [IssueHandlingContext]::new('Script Developer', $null)
                    )
                )
                $notificationSummary.Complete()
                $summaries += $notificationSummary
            }
        }
        else {
            Write-Verbose -Message 'Failure summary mail dispatch is disabled for this run.'
        }

        return $summaries
    }
}
