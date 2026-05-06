<#
.SYNOPSIS
Orchestrates the end-to-end prefix onboarding use case.

.DESCRIPTION
Implements the application-service workflow for provisioning new prefixes. The
service validates prerequisites, branches between manual-work and automated
paths, applies DHCP and DNS changes, updates NetBox, and translates failures
into a consistent reporting model.

.NOTES
Methods:
- PrefixOnboardingService(netBoxClient, activeDirectoryAdapter, jiraClient, prerequisiteValidationService, dhcpServerSelectionService, dhcpServerAdapter, gatewayDnsService, journalService, logService)
- ProcessBatch(environment)
- ProcessWorkItems(environment, workItems)
- ProcessWorkItem(environment, workItem, summary)
- HandleBlockedPrerequisites(workItem, evaluation, lines, summary)
- CompleteNoDhcpPrefix(workItem, lines, summary)
- CompleteDhcpBackedPrefix(environment, workItem, evaluation, lines, summary)
- HandleProcessingFailure(workItem, lines, summary, exception)
- BuildFailureHandlingContext(workItem, exception)
- WriteExecutionLog(workItem, lines)

.EXAMPLE
$summary = $service.ProcessBatch([EnvironmentContext]::new('prod'))
#>
class PrefixOnboardingService {
    [NetBoxClient] $NetBoxClient
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter
    [JiraClient] $JiraClient
    [PrerequisiteValidationService] $PrerequisiteValidationService
    [DhcpServerSelectionService] $DhcpServerSelectionService
    [DhcpServerAdapter] $DhcpServerAdapter
    [GatewayDnsService] $GatewayDnsService
    [WorkItemJournalService] $JournalService
    [WorkItemLogService] $LogService

    PrefixOnboardingService(
        [NetBoxClient] $netBoxClient,
        [ActiveDirectoryAdapter] $activeDirectoryAdapter,
        [JiraClient] $jiraClient,
        [PrerequisiteValidationService] $prerequisiteValidationService,
        [DhcpServerSelectionService] $dhcpServerSelectionService,
        [DhcpServerAdapter] $dhcpServerAdapter,
        [GatewayDnsService] $gatewayDnsService,
        [WorkItemJournalService] $journalService,
        [WorkItemLogService] $logService
    ) {
        $this.NetBoxClient = $netBoxClient
        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
        $this.JiraClient = $jiraClient
        $this.PrerequisiteValidationService = $prerequisiteValidationService
        $this.DhcpServerSelectionService = $dhcpServerSelectionService
        $this.DhcpServerAdapter = $dhcpServerAdapter
        $this.GatewayDnsService = $gatewayDnsService
        $this.JournalService = $journalService
        $this.LogService = $logService
    }

    hidden [void] AppendLine([System.Collections.Generic.List[string]] $lines, [string] $message) {
        if ($null -ne $lines -and -not [string]::IsNullOrWhiteSpace($message)) {
            $null = $lines.Add($message)
        }
    }

    hidden [IPv4Address] ResolveDhcpGatewayAddress([DhcpScopeDefinition] $scopeDefinition, [PrefixWorkItem] $workItem) {
        $derivedGatewayAddress = $scopeDefinition.Range.GatewayAddress
        $firstUsableAddress = $scopeDefinition.Range.StartAddress

        if ($workItem.DefaultGatewayAddress.Value -eq $derivedGatewayAddress.Value) {
            return $derivedGatewayAddress
        }

        if ($workItem.DefaultGatewayAddress.Value -eq $firstUsableAddress.Value) {
            return $workItem.DefaultGatewayAddress
        }

        throw [System.InvalidOperationException]::new(
            "Gateway mismatch for prefix '$($workItem.GetIdentifier())'. Expected '$($derivedGatewayAddress.Value)' or '$($firstUsableAddress.Value)', NetBox provides '$($workItem.DefaultGatewayAddress.Value)'."
        )
    }

    <#
    .SYNOPSIS
    Loads open prefixes from NetBox and processes them.

    .DESCRIPTION
    Serves as the main entry point for the prefix onboarding use case and keeps
    repository access separate from the reusable batch shell.

    .PARAMETER environment
    The resolved execution environment.

    .OUTPUTS
    BatchRunSummary
    #>
    # Batch entry point for the use case. It acts as the application-service orchestrator and keeps iteration outside the domain model.
    [BatchRunSummary] ProcessBatch([EnvironmentContext] $environment) {
        $workItems = $this.NetBoxClient.GetOpenPrefixWorkItems($environment)
        return $this.ProcessWorkItems($environment, $workItems)
    }

    <#
    .SYNOPSIS
    Processes explicitly supplied prefix work items.

    .DESCRIPTION
    Executes the invariant batch shell with caller-provided work items. This
    seam exists to make the orchestration deterministic and easy to test.

    .PARAMETER environment
    The resolved execution environment.

    .PARAMETER workItems
    Prefix work items that should be handled in this batch.

    .OUTPUTS
    BatchRunSummary
    #>
    # Exposes the invariant batch shell separately from data loading so tests can drive the use case with explicit work items.
    [BatchRunSummary] ProcessWorkItems([EnvironmentContext] $environment, [PrefixWorkItem[]] $workItems) {
        $summary = [BatchRunSummary]::new('PrefixOnboarding')
        $loadedWorkItems = @($workItems)
        $summary.AddAudit('Debug', "Loaded $($loadedWorkItems.Count) prefix work item(s) for environment '$($environment.Name)'.")

        foreach ($workItem in $loadedWorkItems) {
            $this.ProcessWorkItem($environment, $workItem, $summary)
        }

        $summary.Complete()
        return $summary
    }

    <#
    .SYNOPSIS
    Processes one prefix through the onboarding workflow.

    .DESCRIPTION
    Executes the template-style work-item flow of prerequisite validation,
    policy branching, side-effecting provisioning, and failure translation.

    .PARAMETER environment
    The resolved execution environment.

    .PARAMETER workItem
    Prefix work item that should be provisioned.

    .PARAMETER summary
    Batch summary that records audit information and outcomes.
    #>
    # Template-style work-item flow: validate, branch by policy, execute provisioning, translate all failures into one reporting model.
    hidden [void] ProcessWorkItem([EnvironmentContext] $environment, [PrefixWorkItem] $workItem, [BatchRunSummary] $summary) {
        $lines = [System.Collections.Generic.List[string]]::new()
        $this.AppendLine($lines, ('Processing prefix {0}' -f $workItem.GetIdentifier()))
        $this.AppendLine($lines, ('Environment: {0}' -f $environment.Name))
        $this.AppendLine($lines, ('DHCPType: {0}' -f $workItem.DHCPType))
        $this.AppendLine($lines, ('Domain: {0}' -f $workItem.Domain))
        $this.AppendLine($lines, ('ValuemationSiteMandant: {0}' -f $workItem.ValuemationSiteMandant))
        $this.AppendLine($lines, ('PrefixRole: {0}' -f $workItem.PrefixRole))
        $summary.AddAudit('Debug', "Starting prefix work item '$($workItem.GetIdentifier())'.")

        try {
            $evaluation = $this.PrerequisiteValidationService.Evaluate($workItem, $environment)
            if (-not [string]::IsNullOrWhiteSpace($evaluation.ObservedDomainController)) {
                $this.AppendLine($lines, ('Selected domain controller: {0}' -f $evaluation.ObservedDomainController))
                $summary.AddAudit('Debug', "Selected domain controller '$($evaluation.ObservedDomainController)' for prefix '$($workItem.GetIdentifier())'.")
            }

            if (-not [string]::IsNullOrWhiteSpace($evaluation.ObservedAdSite)) {
                $this.AppendLine($lines, ('Observed AD site: {0}' -f $evaluation.ObservedAdSite))
            }
            else {
                $this.AppendLine($lines, 'Observed AD site: <none>')
            }

            if (-not [string]::IsNullOrWhiteSpace($evaluation.ReverseZoneName)) {
                $this.AppendLine($lines, ('Resolved reverse zone: {0}' -f $evaluation.ReverseZoneName))
            }
            else {
                $this.AppendLine($lines, 'Resolved reverse zone: <none>')
            }

            if (-not [string]::IsNullOrWhiteSpace($evaluation.DelegationValidationDomain)) {
                $this.AppendLine($lines, ('Delegation validation domain: {0}' -f $evaluation.DelegationValidationDomain))
            }

            $this.AppendLine($lines, ('Prerequisite flags: HasAdSite={0}, HasMatchingMandant={1}, HasReverseZone={2}, HasDnsDelegation={3}, CanContinue={4}' -f $evaluation.HasAdSite, $evaluation.HasMatchingMandant, $evaluation.HasReverseZone, $evaluation.HasDnsDelegation, $evaluation.CanContinue))
            $summary.AddAudit('Debug', "Prerequisite evaluation for prefix '$($workItem.GetIdentifier())': CanContinue=$($evaluation.CanContinue), HasAdSite=$($evaluation.HasAdSite), HasMatchingMandant=$($evaluation.HasMatchingMandant), HasReverseZone=$($evaluation.HasReverseZone), HasDnsDelegation=$($evaluation.HasDnsDelegation).")
            foreach ($reason in @($evaluation.Reasons)) {
                $this.AppendLine($lines, $reason)
            }

            if (-not $evaluation.CanContinue) {
                $this.HandleBlockedPrerequisites($workItem, $evaluation, $lines, $summary)
                return
            }

            if ($workItem.DHCPType -eq 'no_dhcp') {
                $this.CompleteNoDhcpPrefix($workItem, $lines, $summary)
                return
            }

            $this.CompleteDhcpBackedPrefix($environment, $workItem, $evaluation, $lines, $summary)
        }
        catch {
            $this.HandleProcessingFailure($workItem, $lines, $summary, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
    Handles prefixes whose prerequisites are not yet satisfied.

    .DESCRIPTION
    Applies the manual-work policy for blocked prefixes. Depending on the
    evaluation result it either creates a Jira ticket and records progress, or
    raises a blocking exception for the caller to translate into an issue.
    #>
    # Separates prerequisite handling from provisioning so the Jira/manual-work policy can evolve without touching DHCP or DNS steps.
    hidden [void] HandleBlockedPrerequisites(
        [PrefixWorkItem] $workItem,
        [PrerequisiteEvaluation] $evaluation,
        [System.Collections.Generic.List[string]] $lines,
        [BatchRunSummary] $summary
    ) {
        if ($evaluation.RequiresNewJiraTicket) {
            $forestShortName = $this.ActiveDirectoryAdapter.GetForestShortName($workItem.Domain)
            $this.AppendLine($lines, 'Prerequisites blocked; creating Jira prerequisite ticket.')
            $this.AppendLine($lines, ('Resolved forest short name: {0}' -f $forestShortName))
            $this.AppendLine($lines, ('Reverse DNS delegation detected: {0}' -f $evaluation.HasDnsDelegation))
            $ticketUrl = $this.JiraClient.CreatePrerequisiteTicket($workItem, $forestShortName, $evaluation.HasDnsDelegation)
            $this.NetBoxClient.UpdatePrefixTicketUrl($workItem.Id, $ticketUrl)
            $this.AppendLine($lines, ('Created Jira ticket {0}' -f $ticketUrl))
            $lines = $this.WriteExecutionLog($workItem, $lines)
            $this.JournalService.WritePrefixInfo($workItem, $lines)
            $summary.AddAudit('Information', "Created Jira ticket for prefix '$($workItem.GetIdentifier())'.")
            $summary.AddSuccess(('Created Jira ticket for prefix {0}' -f $workItem.GetIdentifier()))
            return
        }

        $message = ($evaluation.Reasons -join ' ')
        $this.AppendLine($lines, 'Prerequisites blocked; existing Jira ticket detected, onboarding remains blocked.')
        if (-not [string]::IsNullOrWhiteSpace($workItem.ExistingTicketUrl)) {
            $this.AppendLine($lines, ('Existing Jira ticket: {0}' -f $workItem.ExistingTicketUrl))
        }
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = 'Prefix prerequisites are not satisfied.'
        }

        throw [System.InvalidOperationException]::new($message)
    }

    <#
    .SYNOPSIS
    Completes the onboarding path for prefixes without DHCP provisioning.

    .DESCRIPTION
    Applies gateway DNS and marks the prefix as completed in NetBox without
    creating a DHCP scope.
    #>
    hidden [void] CompleteNoDhcpPrefix([PrefixWorkItem] $workItem, [System.Collections.Generic.List[string]] $lines, [BatchRunSummary] $summary) {
        if ($workItem.ShouldEnsureGatewayDns()) {
            $this.AppendLine($lines, ('Gateway DNS requested for prefix {0}.' -f $workItem.GetIdentifier()))
            $dnsContext = $this.GatewayDnsService.GetDnsExecutionContext($workItem.PrefixSubnet, $lines)
            $this.AppendLine($lines, ('Gateway DNS context: DC={0}, ReverseZone={1}' -f $dnsContext.DomainController, $dnsContext.ReverseZone))
            $summary.AddAudit('Debug', "Gateway DNS context for prefix '$($workItem.GetIdentifier())': DC='$($dnsContext.DomainController)', ReverseZone='$($dnsContext.ReverseZone)'.")
            $this.GatewayDnsService.EnsurePrefixGatewayDns($workItem, $lines)
            $this.AppendLine($lines, 'Gateway DNS updated.')
        }
        else {
            $this.AppendLine($lines, 'Gateway DNS skipped because the prefix is marked as not_routed.')
        }

        $this.AppendLine($lines, 'Updating NetBox prefix status to onboarding_done_dns_dhcp.')
        $this.NetBoxClient.MarkPrefixOnboardingDone($workItem.Id)
        $this.AppendLine($lines, 'Prefix status updated to onboarding_done_dns_dhcp.')
        $lines = $this.WriteExecutionLog($workItem, $lines)
        $this.JournalService.WritePrefixInfo($workItem, $lines)
        $summary.AddAudit('Information', "Completed prefix work item '$($workItem.GetIdentifier())'.")
        $summary.AddSuccess(('Completed no_dhcp prefix {0}' -f $workItem.GetIdentifier()))
    }

    <#
    .SYNOPSIS
    Completes the full DHCP-backed provisioning path for a prefix.

    .DESCRIPTION
    Creates the DHCP scope, applies gateway DNS, ensures failover linkage, and
    updates NetBox once all infrastructure steps have completed successfully.
    #>
    # Orchestrates the full side-effecting provisioning path; this is intentionally an application-level workflow, not domain logic.
    hidden [void] CompleteDhcpBackedPrefix(
        [EnvironmentContext] $environment,
        [PrefixWorkItem] $workItem,
        [PrerequisiteEvaluation] $evaluation,
        [System.Collections.Generic.List[string]] $lines,
        [BatchRunSummary] $summary
    ) {
        $scopeDefinition = [DhcpScopeDefinition]::FromPrefixWorkItem($workItem)
        $scopeDefinition.Range.GatewayAddress = $this.ResolveDhcpGatewayAddress($scopeDefinition, $workItem)
        $this.AppendLine($lines, ('Calculated DHCP scope name: {0}' -f $scopeDefinition.Name))
        $this.AppendLine($lines, ('Calculated DHCP subnet mask: {0}' -f $scopeDefinition.SubnetMask))
        $this.AppendLine($lines, ('Calculated DHCP range: {0} - {1}' -f $scopeDefinition.Range.StartAddress.Value, $scopeDefinition.Range.EndAddress.Value))
        $this.AppendLine($lines, ('Calculated DHCP gateway: {0}' -f $scopeDefinition.Range.GatewayAddress.Value))
        $this.AppendLine($lines, ('Calculated DHCP broadcast: {0}' -f $scopeDefinition.Range.BroadcastAddress.Value))
        $this.AppendLine($lines, ('Calculated DHCP lease duration (days): {0}' -f $scopeDefinition.LeaseDurationDays))
        $this.AppendLine($lines, ('Calculated DHCP dynamic DNS enabled: {0}' -f $scopeDefinition.ConfigureDynamicDns))
        $exclusionRanges = @($scopeDefinition.ExclusionRanges)
        $this.AppendLine($lines, ('Calculated DHCP exclusion ranges: {0}' -f $exclusionRanges.Count))
        if ($exclusionRanges.Count -eq 0) {
            $this.AppendLine($lines, 'Calculated DHCP exclusion range details: <none>')
        }
        else {
            foreach ($range in $exclusionRanges) {
                $rangeMode = if ($range.MustSucceed) { 'mandatory' } else { 'best-effort' }
                $this.AppendLine($lines, ('Calculated DHCP exclusion range: {0} - {1} ({2})' -f $range.StartAddress.Value, $range.EndAddress.Value, $rangeMode))
            }
        }

        # Server selection is environment-aware and intentionally delegated so onboarding does not encode routing policy itself.
        $this.AppendLine($lines, ('Selecting DHCP server for environment ''{0}'' and AD site ''{1}''.' -f $environment.Name, $evaluation.ObservedAdSite))
        $selectedServer = $this.DhcpServerSelectionService.SelectServer($environment, $evaluation.ObservedAdSite)
        $this.AppendLine($lines, ('Selected DHCP server: {0}' -f $selectedServer))
        $summary.AddAudit('Debug', "Selected DHCP server '$selectedServer' for prefix '$($workItem.GetIdentifier())' (Environment='$($environment.Name)', AdSite='$($evaluation.ObservedAdSite)').")

        $this.AppendLine($lines, ('Ensuring DHCP scope on server {0}.' -f $selectedServer))
        $this.DhcpServerAdapter.EnsureScope($selectedServer, $scopeDefinition, $lines)
        $this.AppendLine($lines, ('DHCP scope ensured on server {0}.' -f $selectedServer))

        $this.AppendLine($lines, ('Gateway DNS requested for prefix {0}.' -f $workItem.GetIdentifier()))
        $dnsContext = $this.GatewayDnsService.GetDnsExecutionContext($workItem.PrefixSubnet, $lines)
        $this.AppendLine($lines, ('Gateway DNS context: DC={0}, ReverseZone={1}' -f $dnsContext.DomainController, $dnsContext.ReverseZone))
        $summary.AddAudit('Debug', "Gateway DNS context for prefix '$($workItem.GetIdentifier())': DC='$($dnsContext.DomainController)', ReverseZone='$($dnsContext.ReverseZone)'.")
        $this.GatewayDnsService.EnsurePrefixGatewayDns($workItem, $lines)
        $this.AppendLine($lines, 'Gateway DNS updated.')

        $this.AppendLine($lines, ('Ensuring DHCP failover linkage for scope {0}.' -f $scopeDefinition.Subnet.Cidr))
        $this.DhcpServerAdapter.EnsureScopeFailover($selectedServer, $scopeDefinition.Subnet, $lines)
        $this.AppendLine($lines, ('Failover linkage ensured on server {0} for scope {1}.' -f $selectedServer, $scopeDefinition.Subnet.Cidr))

        $this.AppendLine($lines, 'Updating NetBox prefix status to onboarding_done_dns_dhcp.')
        $this.NetBoxClient.MarkPrefixOnboardingDone($workItem.Id)
        $this.AppendLine($lines, 'Prefix status updated to onboarding_done_dns_dhcp.')

        $lines = $this.WriteExecutionLog($workItem, $lines)
        $this.JournalService.WritePrefixInfo($workItem, $lines)
        $summary.AddAudit('Information', "Completed prefix work item '$($workItem.GetIdentifier())'.")
        $summary.AddSuccess(('Completed prefix onboarding for {0}' -f $workItem.GetIdentifier()))
    }

    <#
    .SYNOPSIS
    Translates a prefix provisioning failure into logs, journal entries, and an issue.

    .DESCRIPTION
    Ensures that exceptions from the onboarding workflow become visible to
    operators even when the NetBox error journal write itself fails.
    #>
    hidden [void] HandleProcessingFailure(
        [PrefixWorkItem] $workItem,
        [System.Collections.Generic.List[string]] $lines,
        [BatchRunSummary] $summary,
        [System.Exception] $exception
    ) {
        $message = "Failed to process prefix '$($workItem.GetIdentifier())'. $($exception.Message)"
        $this.AppendLine($lines, $message)
        $this.AppendLine($lines, ('Exception type: {0}' -f $exception.GetType().FullName))
        $lines = $this.WriteExecutionLog($workItem, $lines)

        try {
            $this.JournalService.WritePrefixError($workItem, $lines)
        }
        catch {
            $summary.AddAudit('Warning', "Failed to write NetBox error journal for prefix '$($workItem.GetIdentifier())'. $($_.Exception.Message)")
        }

        $summary.AddFailure(
            [OperationIssue]::new(
                'Prefix',
                $workItem.GetIdentifier(),
                $message,
                $exception.ToString(),
                $this.BuildFailureHandlingContext($workItem, $exception),
                $this.NetBoxClient.GetPrefixUrl($workItem.Id)
            )
        )
    }

    <#
    .SYNOPSIS
    Builds the failure ownership context for a prefix issue.

    .DESCRIPTION
    Provides the extension seam for assigning departments or handlers to
    operational failures in a later iteration.

    .OUTPUTS
    IssueHandlingContext
    #>
    hidden [IssueHandlingContext] BuildFailureHandlingContext([PrefixWorkItem] $workItem, [System.Exception] $exception) {
        $department = $this.ResolveHandlingDepartment($exception.Message)
        if ([string]::IsNullOrWhiteSpace($department)) {
            return [IssueHandlingContext]::CreateUnassigned()
        }

        return [IssueHandlingContext]::new($department, $null)
    }

    <#
    .SYNOPSIS
    Maps prefix failures to the responsible department.
    .OUTPUTS
    System.String
    #>
    hidden [string] ResolveHandlingDepartment([string] $message) {
        switch -regex ($message) {
            '^Network is not assigned to any AD site\.' { return 'Tier-0/Admin Court' }
            '^Network is assigned to AD site .*\, but expected .*\.?$' { return 'Tier-0/Admin Court' }
            '^Expected a reverse DNS zone, but none was found\.' { return 'Tier-0/Admin Court' }
            '^Expected a DNS delegation, but none was found\.' { return 'Tier-0/Admin Court' }
            '^Prefix prerequisites are not satisfied\.' { return 'Network Engineer' }
            '^No valid Jira ticket key found in .*\.$' { return 'Script Developer' }
            '^Jira did not return a ticket key\.$' { return 'Script Developer' }
            '^Target status .* is not available for ticket .*\.$' { return 'Tier-0/Admin Court' }
            '^Jira ticket .* is not closed yet\. Current status is .*' { return 'Tier-0/Admin Court' }
            '^Gateway mismatch for prefix .*\. Expected .*\, NetBox provides .*\.?$' { return 'Network Engineer' }
            '^No reverse zone found for prefix .*\.$' { return 'Tier-0/Admin Court' }
            '^Unsupported site .*\.$' { return 'Admin Court' }
            '^No DHCP servers found for site .*\.$' { return 'Admin Court' }
            '^Unsupported DHCP type .*\.$' { return 'Network Engineer' }
            '^Unsupported reverse zone .*\.$' { return 'Tier-0/Admin Court' }
        }

        return $null
    }

    <#
    .SYNOPSIS
    Writes the execution log for one prefix work item.

    .DESCRIPTION
    Persists the collected log lines and appends the relative log path so the
    same line set can be reused in NetBox journals and failure reports.

    .OUTPUTS
    System.String[]
    #>
    hidden [string[]] WriteExecutionLog([PrefixWorkItem] $workItem, [System.Collections.Generic.List[string]] $lines) {
        $logPath = $this.LogService.CreateLogPath('network', $workItem.GetIdentifier())
        $linesWithLogPath = @($lines.ToArray() + ('Log file: {0}' -f $logPath))
        $this.LogService.WriteLog($logPath, $linesWithLogPath)
        return $linesWithLogPath
    }
}
