<#
.SYNOPSIS
Sends aggregated failure notifications for completed batch runs.

.DESCRIPTION
Collects all operation issues from the batch summaries, formats them into a
human-readable grouped mail body, and delegates delivery to the SMTP adapter.

.NOTES
Methods:
- BatchNotificationService(mailClient, mailFormatter)
- CollectIssues(summaries)
- SendFailureSummary(recipients, summaries)

.EXAMPLE
$notificationService.SendFailureSummary(@('ops@example.com'), $summaries)
#>
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

    <#
    .SYNOPSIS
    Flattens issues from multiple batch summaries.

    .DESCRIPTION
    Collects the operation issues from every summary so the mail formatter can
    work on one consistent list regardless of how many workflows were executed.

    .PARAMETER summaries
    Batch summaries that may contain failures.

    .OUTPUTS
    OperationIssue[]
    #>
    hidden [OperationIssue[]] CollectIssues([BatchRunSummary[]] $summaries) {
        $issues = @()

        foreach ($summary in @($summaries)) {
            foreach ($issue in @($summary.Issues)) {
                $issues = @($issues + $issue)
            }
        }

        return $issues
    }

    <#
    .SYNOPSIS
    Sends the grouped failure mail when issues are present.

    .DESCRIPTION
    Performs the minimal orchestration needed for the notification boundary:
    collect failures, format the HTML body, and send the message. Empty inputs
    short-circuit so the caller does not need to pre-check for failures.

    .PARAMETER recipients
    Mail recipients that should receive the summary.

    .PARAMETER summaries
    Batch summaries to inspect for failures.

    .EXAMPLE
    $service.SendFailureSummary(@('noc@example.com'), $summaries)
    #>
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
