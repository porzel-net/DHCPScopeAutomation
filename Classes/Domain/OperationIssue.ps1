# Represents a recoverable processing failure with enough context for mailing, journaling, and reporting.
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

    [string] GetHandlingDepartment() {
        return $this.HandlingContext.GetDepartmentOrDefault()
    }

    [string] GetHandlingHandler() {
        return $this.HandlingContext.GetHandlerOrDefault()
    }

    [bool] HasResourceUrl() {
        return -not [string]::IsNullOrWhiteSpace($this.ResourceUrl)
    }
}
