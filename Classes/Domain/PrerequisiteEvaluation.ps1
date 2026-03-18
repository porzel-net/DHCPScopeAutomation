# Captures the result of prerequisite checks before a prefix can move into provisioning.
<#
.SYNOPSIS
Represents the validation result for one prefix before provisioning starts.

.DESCRIPTION
Collects prerequisite state, blocking reasons, and Jira-related decision flags so
the application layer can choose between continue, create-ticket, or fail paths.

.NOTES
Methods:
- PrerequisiteEvaluation()
- AddReason(reason)

.EXAMPLE
$evaluation = [PrerequisiteEvaluation]::new()
$evaluation.AddReason('Network is not assigned to any AD site.')
#>
class PrerequisiteEvaluation {
    [bool] $CanContinue
    [bool] $RequiresNewJiraTicket
    [bool] $RequiresExistingJiraWait
    [bool] $HasAdSite
    [bool] $HasMatchingMandant
    [bool] $HasReverseZone
    [bool] $HasDnsDelegation
    [string] $ObservedAdSite
    [string] $ReverseZoneName
    [string[]] $Reasons

    PrerequisiteEvaluation() {
        $this.CanContinue = $false
        $this.RequiresNewJiraTicket = $false
        $this.RequiresExistingJiraWait = $false
        $this.HasAdSite = $false
        $this.HasMatchingMandant = $false
        $this.HasReverseZone = $false
        $this.HasDnsDelegation = $false
        $this.Reasons = @()
    }

    <#
    .SYNOPSIS
    Appends one blocking reason to the evaluation.
    .OUTPUTS
    System.Void
    #>
    [void] AddReason([string] $reason) {
        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            $this.Reasons = @($this.Reasons + $reason)
        }
    }
}
