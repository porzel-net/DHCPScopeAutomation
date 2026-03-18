# Sends aggregated failure notifications after all enabled batch processes finished.
class BatchNotificationService {
    [SmtpMailClient] $MailClient
    [OperationIssueMailFormatter] $MailFormatter

    BatchNotificationService([SmtpMailClient] $mailClient, [OperationIssueMailFormatter] $mailFormatter) {
        if ($null -eq $mailClient) {
            throw [System.ArgumentNullException]::new('mailClient')
        }

        if ($null -eq $mailFormatter) {
            throw [System.ArgumentNullException]::new('mailFormatter')
        }

        $this.MailClient = $mailClient
        $this.MailFormatter = $mailFormatter
    }

    hidden [OperationIssue[]] CollectIssues([BatchRunSummary[]] $summaries) {
        $issues = @()

        foreach ($summary in @($summaries)) {
            foreach ($issue in @($summary.Issues)) {
                $issues = @($issues + $issue)
            }
        }

        return $issues
    }

    [void] SendFailureSummary([string[]] $recipients, [BatchRunSummary[]] $summaries) {
        $issues = $this.CollectIssues($summaries)

        if (-not $issues) {
            return
        }

        $body = $this.MailFormatter.BuildFailureSummaryBody($issues)
        if ([string]::IsNullOrWhiteSpace($body)) {
            return
        }

        $this.MailClient.SendHtmlMail($recipients, 'DHCPScopeAutomation', $body)
    }
}
