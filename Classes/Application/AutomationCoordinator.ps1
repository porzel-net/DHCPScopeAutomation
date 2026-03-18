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

        if (-not $skipPrefixOnboarding) {
            $summaries += $this.PrefixOnboardingService.ProcessBatch($environment)
        }

        if (-not $skipIpDnsOnboarding) {
            $summaries += $this.IpDnsOnboardingService.ProcessBatch($environment)
        }

        if (-not $skipIpDnsDecommissioning) {
            $summaries += $this.IpDnsDecommissioningService.ProcessBatch($environment)
        }

        if ($sendFailureMail) {
            try {
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
                        [IssueHandlingContext]::CreateUnassigned()
                    )
                )
                $notificationSummary.Complete()
                $summaries += $notificationSummary
            }
        }

        return $summaries
    }
}
