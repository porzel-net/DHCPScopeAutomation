# Captures a single structured audit event for logs, summaries, and user-facing output.
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
