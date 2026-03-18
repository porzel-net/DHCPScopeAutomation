<#
.SYNOPSIS
Converts an internal batch summary into a public PowerShell object.

.DESCRIPTION
Projects internal class instances into `PSCustomObject` values so module callers do
not need to import or understand the internal type system.

.PARAMETER Summary
Internal batch summary returned by the application layer.

.OUTPUTS
PSCustomObject

.EXAMPLE
Convert-BatchRunSummaryToPublicObject -Summary $summary
#>
function Convert-BatchRunSummaryToPublicObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [BatchRunSummary] $Summary
    )

    $publicIssues = @()
    foreach ($issue in @($Summary.Issues)) {
        $publicIssues += [pscustomobject]@{
            TimestampUtc       = $issue.TimestampUtc
            WorkItemType       = $issue.WorkItemType
            WorkItemIdentifier = $issue.WorkItemIdentifier
            Message            = $issue.Message
            Details            = $issue.Details
            HandlingDepartment = $issue.GetHandlingDepartment()
            HandlingHandler    = $issue.GetHandlingHandler()
            ResourceUrl        = $issue.ResourceUrl
        }
    }

    $publicAuditEntries = @()
    foreach ($entry in @($Summary.AuditEntries)) {
        $publicAuditEntries += [pscustomobject]@{
            TimestampUtc = $entry.TimestampUtc
            Level        = $entry.Level
            Message      = $entry.Message
        }
    }

    return [pscustomobject]@{
        ProcessName  = $Summary.ProcessName
        StartedUtc   = $Summary.StartedUtc
        FinishedUtc  = $Summary.FinishedUtc
        SuccessCount = $Summary.SuccessCount
        FailureCount = $Summary.FailureCount
        Issues       = $publicIssues
        AuditEntries = $publicAuditEntries
    }
}
