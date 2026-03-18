# Coordinates the enabled application services for one automation run.
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
