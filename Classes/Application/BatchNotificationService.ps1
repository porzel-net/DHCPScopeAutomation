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
            Write-Debug -Message ("Collecting issues from summary '{0}' (count={1})." -f $summary.ProcessName, @($summary.Issues).Count)
            foreach ($issue in @($summary.Issues)) {
                $issues = @($issues + $issue)
            }
        }

        Write-Verbose -Message ("Collected {0} issue(s) across {1} summary/summaries." -f @($issues).Count, @($summaries).Count)
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
        Write-Verbose -Message ("Preparing failure summary mail for {0} recipient(s)." -f @($recipients).Count)
        $issues = $this.CollectIssues($summaries)

        if (-not $issues) {
            Write-Verbose -Message 'No issues found; failure summary mail is skipped.'
            return
        }

        $body = $this.MailFormatter.BuildFailureSummaryBody($issues)
        if ([string]::IsNullOrWhiteSpace($body)) {
            Write-Warning -Message 'Failure summary mail body is empty; mail delivery is skipped.'
            return
        }

        Write-Verbose -Message ("Sending failure summary mail with {0} issue(s)." -f @($issues).Count)
        $this.MailClient.SendHtmlMail($recipients, 'DHCPScopeAutomation', $body)
    }
}
