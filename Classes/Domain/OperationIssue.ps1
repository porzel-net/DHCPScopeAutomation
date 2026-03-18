# Represents a recoverable processing failure with enough context for mailing, journaling, and reporting.
<#
.SYNOPSIS
Represents one failed work item in a normalized operational format.

.DESCRIPTION
Captures the failing work item, human-readable message, detailed error text,
optional routing metadata, and an optional deep link back to NetBox.

.NOTES
Methods:
- OperationIssue(...) constructor overloads
- Initialize(...)
- GetHandlingDepartment()
- GetHandlingHandler()
- HasResourceUrl()

.EXAMPLE
[OperationIssue]::new('Prefix', '10.20.30.0/24', 'Failed', 'Detailed exception')
#>
class OperationIssue {
    [datetime] $TimestampUtc
    [string] $WorkItemType
    [string] $WorkItemIdentifier
    [string] $Message
    [string] $Details
    [IssueHandlingContext] $HandlingContext
    [string] $ResourceUrl

    OperationIssue([string] $workItemType, [string] $workItemIdentifier, [string] $message, [string] $details) {
        $this.Initialize($workItemType, $workItemIdentifier, $message, $details, [IssueHandlingContext]::CreateUnassigned(), $null)
    }

    OperationIssue([string] $workItemType, [string] $workItemIdentifier, [string] $message, [string] $details, [IssueHandlingContext] $issueHandlingContext) {
        $this.Initialize($workItemType, $workItemIdentifier, $message, $details, $issueHandlingContext, $null)
    }

    OperationIssue(
        [string] $workItemType,
        [string] $workItemIdentifier,
        [string] $message,
        [string] $details,
        [IssueHandlingContext] $issueHandlingContext,
        [string] $resourceUrl
    ) {
        $this.Initialize($workItemType, $workItemIdentifier, $message, $details, $issueHandlingContext, $resourceUrl)
    }

    <#
    .SYNOPSIS
    Initializes the normalized operation issue.
    .OUTPUTS
    System.Void
    #>
    hidden [void] Initialize(
        [string] $workItemType,
        [string] $workItemIdentifier,
        [string] $message,
        [string] $details,
        [IssueHandlingContext] $issueHandlingContext,
        [string] $resourceUrl
    ) {
        if ([string]::IsNullOrWhiteSpace($workItemType)) {
            throw [System.ArgumentException]::new('WorkItemType is required.')
        }

        if ([string]::IsNullOrWhiteSpace($message)) {
            throw [System.ArgumentException]::new('Message is required.')
        }

        if ($null -eq $issueHandlingContext) {
            $issueHandlingContext = [IssueHandlingContext]::CreateUnassigned()
        }

        $this.TimestampUtc = [datetime]::UtcNow
        $this.WorkItemType = $workItemType
        $this.WorkItemIdentifier = $workItemIdentifier
        $this.Message = $message
        $this.Details = $details
        $this.HandlingContext = $issueHandlingContext
        $this.ResourceUrl = $resourceUrl
    }

    <#
    .SYNOPSIS
    Returns the effective handling department.
    .OUTPUTS
    System.String
    #>
    [string] GetHandlingDepartment() {
        return $this.HandlingContext.GetDepartmentOrDefault()
    }

    <#
    .SYNOPSIS
    Returns the effective handling handler.
    .OUTPUTS
    System.String
    #>
    [string] GetHandlingHandler() {
        return $this.HandlingContext.GetHandlerOrDefault()
    }

    <#
    .SYNOPSIS
    Indicates whether the issue exposes a deep link.
    .OUTPUTS
    System.Boolean
    #>
    [bool] HasResourceUrl() {
        return -not [string]::IsNullOrWhiteSpace($this.ResourceUrl)
    }
}
