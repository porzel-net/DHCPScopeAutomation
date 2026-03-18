<#
.SYNOPSIS
Represents one structured audit entry emitted during a batch run.

.DESCRIPTION
Stores timestamp, severity level, and message text for audit output. This class is
used by summaries, logging helpers, and public result conversion.

.NOTES
Methods:
- OperationAuditEntry(level, message): validates and creates the entry.

.EXAMPLE
[OperationAuditEntry]::new('Information', 'Prefix completed.')
#>
class OperationAuditEntry {
    [datetime] $TimestampUtc
    [string] $Level
    [string] $Message

    OperationAuditEntry([string] $level, [string] $message) {
        if ([string]::IsNullOrWhiteSpace($level)) {
            throw [System.ArgumentException]::new('Level is required.')
        }

        if ([string]::IsNullOrWhiteSpace($message)) {
            throw [System.ArgumentException]::new('Message is required.')
        }

        $normalizedLevel = $level.Trim()
        $allowedLevels = @('Debug', 'Information', 'Warning', 'Error', 'Verbose')
        if ($normalizedLevel -notin $allowedLevels) {
            throw [System.ArgumentOutOfRangeException]::new('level', "Unsupported log level '$level'.")
        }

        $this.TimestampUtc = [datetime]::UtcNow
        $this.Level = $normalizedLevel
        $this.Message = $message
    }
}
