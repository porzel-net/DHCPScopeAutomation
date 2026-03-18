# Aggregates the outcome of one batch-style use case execution.
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

    [void] AddSuccess([string] $message) {
        $this.SuccessCount++
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            $this.AddAudit('Information', $message)
        }
    }

    [void] AddFailure([OperationIssue] $issue) {
        if ($null -eq $issue) {
            throw [System.ArgumentNullException]::new('issue')
        }

        $this.FailureCount++
        $this.Issues = @($this.Issues + $issue)
        $this.AddAudit('Error', $issue.Message)
    }

    [void] AddAudit([string] $level, [string] $message) {
        $entry = [OperationAuditEntry]::new($level, $message)
        $this.AuditEntries = @($this.AuditEntries + $entry)
    }

    [void] Complete() {
        $this.FinishedUtc = [datetime]::UtcNow
    }

    [bool] HasFailures() {
        return $this.FailureCount -gt 0
    }
}
