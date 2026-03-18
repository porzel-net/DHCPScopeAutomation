# Orchestrates the end-to-end prefix onboarding use case.
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

    # Batch entry point for the use case. It acts as the application-service orchestrator and keeps iteration outside the domain model.
    [BatchRunSummary] ProcessBatch([EnvironmentContext] $environment) {
        $workItems = $this.NetBoxClient.GetOpenPrefixWorkItems($environment)
        return $this.ProcessWorkItems($environment, $workItems)
    }

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

    # Template-style work-item flow: validate, branch by policy, execute provisioning, translate all failures into one reporting model.
    hidden [void] ProcessWorkItem([EnvironmentContext] $environment, [PrefixWorkItem] $workItem, [BatchRunSummary] $summary) {
        $lines = @(('Processing prefix {0}' -f $workItem.GetIdentifier()))
        $summary.AddAudit('Debug', "Starting prefix work item '$($workItem.GetIdentifier())'.")

        try {
            $evaluation = $this.PrerequisiteValidationService.Evaluate($workItem, $environment)
            $lines += $evaluation.Reasons

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

    # Separates prerequisite handling from provisioning so the Jira/manual-work policy can evolve without touching DHCP or DNS steps.
    hidden [void] HandleBlockedPrerequisites(
        [PrefixWorkItem] $workItem,
        [PrerequisiteEvaluation] $evaluation,
        [string[]] $lines,
        [BatchRunSummary] $summary
    ) {
        if ($evaluation.RequiresNewJiraTicket) {
            $forestShortName = $this.ActiveDirectoryAdapter.GetForestShortName($workItem.Domain)
            $ticketUrl = $this.JiraClient.CreatePrerequisiteTicket($workItem, $forestShortName, $evaluation.HasDnsDelegation)
            $this.NetBoxClient.UpdatePrefixTicketUrl($workItem.Id, $ticketUrl)
            $lines += 'Created Jira ticket {0}' -f $ticketUrl
            $lines = $this.WriteExecutionLog($workItem, $lines)
            $this.JournalService.WritePrefixInfo($workItem, $lines)
            $summary.AddAudit('Information', "Created Jira ticket for prefix '$($workItem.GetIdentifier())'.")
            $summary.AddSuccess(('Created Jira ticket for prefix {0}' -f $workItem.GetIdentifier()))
            return
        }

        $message = ($evaluation.Reasons -join ' ')
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = 'Prefix prerequisites are not satisfied.'
        }

        throw [System.InvalidOperationException]::new($message)
    }

    hidden [void] CompleteNoDhcpPrefix([PrefixWorkItem] $workItem, [string[]] $lines, [BatchRunSummary] $summary) {
        $this.GatewayDnsService.EnsurePrefixGatewayDns($workItem)
        $this.NetBoxClient.MarkPrefixOnboardingDone($workItem.Id)
        $lines += 'Gateway DNS updated.'
        $lines += 'Prefix status updated to onboarding_done_dns_dhcp.'
        $lines = $this.WriteExecutionLog($workItem, $lines)
        $this.JournalService.WritePrefixInfo($workItem, $lines)
        $summary.AddAudit('Information', "Completed prefix work item '$($workItem.GetIdentifier())'.")
        $summary.AddSuccess(('Completed no_dhcp prefix {0}' -f $workItem.GetIdentifier()))
    }

    # Orchestrates the full side-effecting provisioning path; this is intentionally an application-level workflow, not domain logic.
    hidden [void] CompleteDhcpBackedPrefix(
        [EnvironmentContext] $environment,
        [PrefixWorkItem] $workItem,
        [PrerequisiteEvaluation] $evaluation,
        [string[]] $lines,
        [BatchRunSummary] $summary
    ) {
        $scopeDefinition = [DhcpScopeDefinition]::FromPrefixWorkItem($workItem)

        if ($scopeDefinition.Range.GatewayAddress.Value -ne $workItem.DefaultGatewayAddress.Value) {
            throw [System.InvalidOperationException]::new(
                "Gateway mismatch for prefix '$($workItem.GetIdentifier())'. Expected '$($scopeDefinition.Range.GatewayAddress.Value)', NetBox provides '$($workItem.DefaultGatewayAddress.Value)'."
            )
        }

        $selectedServer = $this.DhcpServerSelectionService.SelectServer($environment, $evaluation.ObservedAdSite)
        $lines += 'Selected DHCP server: {0}' -f $selectedServer

        $this.DhcpServerAdapter.EnsureScope($selectedServer, $scopeDefinition)
        $lines += 'DHCP scope ensured.'

        $this.GatewayDnsService.EnsurePrefixGatewayDns($workItem)
        $lines += 'Gateway DNS updated.'

        $this.DhcpServerAdapter.EnsureScopeFailover($selectedServer, $scopeDefinition.Subnet)
        $lines += 'Failover linkage ensured.'

        $this.NetBoxClient.MarkPrefixOnboardingDone($workItem.Id)
        $lines += 'Prefix status updated to onboarding_done_dns_dhcp.'

        $lines = $this.WriteExecutionLog($workItem, $lines)
        $this.JournalService.WritePrefixInfo($workItem, $lines)
        $summary.AddAudit('Information', "Completed prefix work item '$($workItem.GetIdentifier())'.")
        $summary.AddSuccess(('Completed prefix onboarding for {0}' -f $workItem.GetIdentifier()))
    }

    hidden [void] HandleProcessingFailure(
        [PrefixWorkItem] $workItem,
        [string[]] $lines,
        [BatchRunSummary] $summary,
        [System.Exception] $exception
    ) {
        $message = "Failed to process prefix '$($workItem.GetIdentifier())'. $($exception.Message)"
        $lines += $message
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

    hidden [IssueHandlingContext] BuildFailureHandlingContext([PrefixWorkItem] $workItem, [System.Exception] $exception) {
        return [IssueHandlingContext]::CreateUnassigned()
    }

    hidden [string[]] WriteExecutionLog([PrefixWorkItem] $workItem, [string[]] $lines) {
        $logPath = $this.LogService.CreateLogPath('network', $workItem.GetIdentifier())
        $linesWithLogPath = @($lines + ('Log file: {0}' -f $logPath))
        $this.LogService.WriteLog($logPath, $linesWithLogPath)
        return $linesWithLogPath
    }
}
