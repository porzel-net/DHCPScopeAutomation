<#
.SYNOPSIS
Evaluates whether a prefix is ready for automated provisioning.

.DESCRIPTION
Runs the read-only prerequisite checks for AD site placement, site/mandant
matching, reverse-zone presence, DNS delegation, and Jira closure. The result is
returned as a domain object so the caller can decide the next action.

.NOTES
Methods:
- PrerequisiteValidationService(activeDirectoryAdapter, dnsServerAdapter, jiraClient)
- Evaluate(workItem, environment)

.EXAMPLE
$evaluation = $validator.Evaluate($workItem, $environment)
#>
class PrerequisiteValidationService {
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter
    [DnsServerAdapter] $DnsServerAdapter
    [JiraClient] $JiraClient

    PrerequisiteValidationService(
        [ActiveDirectoryAdapter] $activeDirectoryAdapter,
        [DnsServerAdapter] $dnsServerAdapter,
        [JiraClient] $jiraClient
    ) {
        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
        $this.DnsServerAdapter = $dnsServerAdapter
        $this.JiraClient = $jiraClient
    }

    <#
    .SYNOPSIS
    Evaluates all onboarding prerequisites for one prefix.

    .DESCRIPTION
    Performs the prerequisite pipeline as a read-only validation step. It
    returns early when a blocking precondition is missing so the caller can
    either create manual-work tickets or stop automated provisioning.

    .PARAMETER workItem
    Prefix work item whose prerequisites should be checked.

    .PARAMETER environment
    The resolved execution environment.

    .OUTPUTS
    PrerequisiteEvaluation
    #>
    # Runs the prerequisite pipeline as a pure validation step so callers can decide how to react to blocked work.
    [PrerequisiteEvaluation] Evaluate([PrefixWorkItem] $workItem, [EnvironmentContext] $environment) {
        # The evaluation object is the single carrier for all prerequisite outcomes so the caller does not need to interpret partial booleans.
        $evaluation = [PrerequisiteEvaluation]::new()
        $domainController = $this.ActiveDirectoryAdapter.GetDomainControllerName()
        $evaluation.ObservedDomainController = $domainController
        $evaluation.ObservedAdSite = $this.ActiveDirectoryAdapter.GetSubnetSite($workItem.PrefixSubnet, $domainController)

        if ([string]::IsNullOrWhiteSpace($evaluation.ObservedAdSite)) {
            $evaluation.AddReason('Network is not assigned to any AD site.')
            $evaluation.RequiresNewJiraTicket = [string]::IsNullOrWhiteSpace($workItem.ExistingTicketUrl)
            $evaluation.RequiresExistingJiraWait = -not $evaluation.RequiresNewJiraTicket
            return $evaluation
        }

        $evaluation.HasAdSite = $true

        if ($evaluation.ObservedAdSite.ToUpperInvariant() -ne $workItem.ValuemationSiteMandant.ToUpperInvariant()) {
            $evaluation.AddReason("Network is assigned to AD site '$($evaluation.ObservedAdSite)', but expected '$($workItem.ValuemationSiteMandant)'.")
            return $evaluation
        }

        $evaluation.HasMatchingMandant = $true
        $evaluation.ReverseZoneName = $this.DnsServerAdapter.FindBestReverseZoneName($workItem.PrefixSubnet, $domainController)

        if ([string]::IsNullOrWhiteSpace($evaluation.ReverseZoneName)) {
            $evaluation.AddReason('Expected a reverse DNS zone, but none was found.')
            $evaluation.RequiresNewJiraTicket = [string]::IsNullOrWhiteSpace($workItem.ExistingTicketUrl)
            $evaluation.RequiresExistingJiraWait = -not $evaluation.RequiresNewJiraTicket
            return $evaluation
        }

        $evaluation.HasReverseZone = $true
        $delegationValidationDomain = $environment.GetDelegationValidationDomain()
        $evaluation.DelegationValidationDomain = $delegationValidationDomain
        $evaluation.HasDnsDelegation = $this.DnsServerAdapter.TestReverseZoneDelegation($workItem.PrefixSubnet, $delegationValidationDomain)

        if (-not $evaluation.HasDnsDelegation) {
            $evaluation.AddReason('Expected a DNS delegation, but none was found.')
            $evaluation.RequiresNewJiraTicket = [string]::IsNullOrWhiteSpace($workItem.ExistingTicketUrl)
            $evaluation.RequiresExistingJiraWait = -not $evaluation.RequiresNewJiraTicket
            return $evaluation
        }

        if (-not [string]::IsNullOrWhiteSpace($workItem.ExistingTicketUrl)) {
            $this.JiraClient.EnsureTicketClosed($workItem.ExistingTicketUrl)
        }

        $evaluation.CanContinue = $true
        return $evaluation
    }
}
