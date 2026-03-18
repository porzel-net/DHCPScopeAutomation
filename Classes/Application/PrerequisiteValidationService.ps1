# Evaluates whether a prefix is ready for provisioning without performing side effects.
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

    # Runs the prerequisite pipeline as a pure validation step so callers can decide how to react to blocked work.
    [PrerequisiteEvaluation] Evaluate([PrefixWorkItem] $workItem, [EnvironmentContext] $environment) {
        $evaluation = [PrerequisiteEvaluation]::new()
        $domainController = $this.ActiveDirectoryAdapter.GetDomainControllerName()
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
        $evaluation.HasDnsDelegation = $this.DnsServerAdapter.TestReverseZoneDelegation($workItem.PrefixSubnet, $environment.GetDelegationValidationDomain())

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
