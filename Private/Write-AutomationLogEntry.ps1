<#
.SYNOPSIS
Writes a structured audit entry to the matching PowerShell stream.

.DESCRIPTION
Maps `OperationAuditEntry.Level` to the corresponding PowerShell output stream so
that callers can control visibility through standard preference variables.

.PARAMETER Entry
Structured audit entry to emit.

.OUTPUTS
None.

.EXAMPLE
Write-AutomationLogEntry -Entry $entry
#>
function Write-AutomationLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [OperationAuditEntry] $Entry
    )

    $message = '[{0:u}] [{1}] {2}' -f $Entry.TimestampUtc, $Entry.Level, $Entry.Message

    switch ($Entry.Level) {
        'Debug' {
            Write-Debug -Message $message
            break
        }
        'Verbose' {
            Write-Verbose -Message $message
            break
        }
        'Information' {
            Write-Information -MessageData $message
            break
        }
        'Warning' {
            Write-Warning -Message $message
            break
        }
        'Error' {
            Write-Error -Message $message
            break
        }
        default {
            Write-Verbose -Message $message
            break
        }
    }
}
