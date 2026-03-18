# Captures the result of prerequisite checks before a prefix can move into provisioning.
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

    [void] AddReason([string] $reason) {
        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            $this.Reasons = @($this.Reasons + $reason)
        }
    }
}
