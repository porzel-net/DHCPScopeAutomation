# Aggregates the outcome of one batch-style use case execution.
<#
.SYNOPSIS
Aggregates the result of one batch process.

.DESCRIPTION
Tracks successes, failures, audit entries, and start/finish timestamps for one
use case such as prefix onboarding or IP DNS onboarding.

.NOTES
Methods:
- BatchRunSummary(processName)
- AddSuccess(message)
- AddFailure(issue)
- AddAudit(level, message)
- Complete()
- HasFailures()

.EXAMPLE
[BatchRunSummary]::new('PrefixOnboarding')
#>
class BatchRunSummary {
    [string] $ProcessName
    [datetime] $StartedUtc
    [datetime] $FinishedUtc
    [int] $SuccessCount
    [int] $FailureCount
    [OperationIssue[]] $Issues
    [OperationAuditEntry[]] $AuditEntries

    BatchRunSummary([string] $processName) {
        if ([string]::IsNullOrWhiteSpace($processName)) {
            throw [System.ArgumentException]::new('ProcessName is required.')
        }

        $this.ProcessName = $processName
        $this.StartedUtc = [datetime]::UtcNow
        $this.Issues = @()
        $this.AuditEntries = @()
    }

    <#
    .SYNOPSIS
    Records a successful work item result.
    .OUTPUTS
    System.Void
    #>
    [void] AddSuccess([string] $message) {
        $this.SuccessCount++
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            $this.AddAudit('Information', $message)
        }
    }

    <#
    .SYNOPSIS
    Records a failed work item result.
    .OUTPUTS
    System.Void
    #>
    [void] AddFailure([OperationIssue] $issue) {
        if ($null -eq $issue) {
            throw [System.ArgumentNullException]::new('issue')
        }

        $this.FailureCount++
        $this.Issues = @($this.Issues + $issue)
        $this.AddAudit('Error', $issue.Message)
    }

    <#
    .SYNOPSIS
    Appends one audit entry to the batch summary.
    .OUTPUTS
    System.Void
    #>
    [void] AddAudit([string] $level, [string] $message) {
        $entry = [OperationAuditEntry]::new($level, $message)
        $this.AuditEntries = @($this.AuditEntries + $entry)
    }

    <#
    .SYNOPSIS
    Stamps the completion time of the summary.
    .OUTPUTS
    System.Void
    #>
    [void] Complete() {
        $this.FinishedUtc = [datetime]::UtcNow
    }

    <#
    .SYNOPSIS
    Indicates whether the batch produced failures.
    .OUTPUTS
    System.Boolean
    #>
    [bool] HasFailures() {
        return $this.FailureCount -gt 0
    }
}
