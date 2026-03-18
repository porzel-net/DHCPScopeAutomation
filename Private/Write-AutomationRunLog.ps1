<#
.SYNOPSIS
Persists a run-wide summary log for the current automation execution.

.DESCRIPTION
Builds the aggregated `StartingProcess` log file from the runtime context and the
batch summaries returned by the application services.

.PARAMETER Runtime
Resolved runtime container that provides environment metadata and log services.

.PARAMETER Summaries
Batch results that should be written to the run summary log.

.OUTPUTS
System.String

.EXAMPLE
Write-AutomationRunLog -Runtime $runtime -Summaries $summaries
#>
function Write-AutomationRunLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AutomationRuntime] $Runtime,

        [Parameter(Mandatory = $true)]
        [BatchRunSummary[]] $Summaries
    )

    $logPath = $Runtime.LogService.CreateLogPath('StartingProcess', $Runtime.Environment.Name)
    $lines = @(
        'DHCPScopeAutomation run summary'
        'Environment: {0}' -f $Runtime.Environment.Name
        'DnsZone: {0}' -f $Runtime.Environment.DnsZone
        'EmailRecipients: {0}' -f ($Runtime.EmailRecipients -join ', ')
        'GeneratedAtUtc: {0:u}' -f [datetime]::UtcNow
    )

    foreach ($summary in @($Summaries)) {
        $lines += ''
        $lines += 'Process: {0}' -f $summary.ProcessName
        $lines += 'StartedUtc: {0:u}' -f $summary.StartedUtc
        $lines += 'FinishedUtc: {0:u}' -f $summary.FinishedUtc
        $lines += 'SuccessCount: {0}' -f $summary.SuccessCount
        $lines += 'FailureCount: {0}' -f $summary.FailureCount

        foreach ($entry in @($summary.AuditEntries)) {
            $lines += '[{0:u}] [{1}] {2}' -f $entry.TimestampUtc, $entry.Level, $entry.Message
        }
    }

    $Runtime.LogService.WriteLog($logPath, $lines)
    return $logPath
}
