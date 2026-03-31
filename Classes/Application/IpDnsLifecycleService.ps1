<#
.SYNOPSIS
Processes IP DNS onboarding and decommissioning through one shared workflow shell.

.DESCRIPTION
Implements a mode-driven application service that reuses one orchestration flow
for both lifecycle directions. Mode-specific behavior is isolated behind small
helper methods so the main workflow remains linear and testable.

.NOTES
Methods:
- IpDnsLifecycleService(mode, netBoxClient, gatewayDnsService, journalService, logService)
- InitializeMode(mode)
- ProcessBatch(environment)
- ProcessWorkItems(environment, workItems)
- ProcessWorkItem(workItem, summary)
- ValidateWorkItem(workItem)
- ExecuteDnsLifecycle(workItem)
- HandleProcessingFailure(workItem, lines, summary, exception)
- BuildFailureHandlingContext(workItem, exception)
- WriteExecutionLog(workItem, lines)
- GetLifecycleDisplayName()
- GetProcessingLine(workItem)
- GetDnsLifecycleResultLine()
- GetSuccessSummaryMessage(workItem)
- GetFailureMessage(workItem, exception)

.EXAMPLE
$summary = $service.ProcessBatch([EnvironmentContext]::new('prod'))
#>
class IpDnsLifecycleService {
    [NetBoxClient] $NetBoxClient
    [GatewayDnsService] $GatewayDnsService
    [WorkItemJournalService] $JournalService
    [WorkItemLogService] $LogService
    [string] $Mode
    [string] $ProcessName
    [string[]] $SourceStatuses
    [string] $TargetStatus

    IpDnsLifecycleService(
        [string] $mode,
        [NetBoxClient] $netBoxClient,
        [GatewayDnsService] $gatewayDnsService,
        [WorkItemJournalService] $journalService,
        [WorkItemLogService] $logService
    ) {
        $this.InitializeMode($mode)
        $this.NetBoxClient = $netBoxClient
        $this.GatewayDnsService = $gatewayDnsService
        $this.JournalService = $journalService
        $this.LogService = $logService
    }

    <#
    .SYNOPSIS
    Initializes the lifecycle mode for the service instance.

    .DESCRIPTION
    Normalizes the supplied mode and configures the process name, source
    statuses, and target status used by the shared lifecycle workflow.

    .PARAMETER mode
    Supported values are `onboarding` and `decommissioning`.
    #>
    # Configures the service as a mode-based strategy object so onboarding and decommissioning can reuse one workflow shell.
    hidden [void] InitializeMode([string] $mode) {
        $normalizedMode = $mode
        if (-not [string]::IsNullOrWhiteSpace($normalizedMode)) {
            $normalizedMode = $normalizedMode.Trim().ToLowerInvariant()
        }

        switch ($normalizedMode) {
            'onboarding' {
                $this.Mode = $normalizedMode
                $this.ProcessName = 'IpDnsOnboarding'
                $this.SourceStatuses = @('onboarding_open_dns')
                $this.TargetStatus = 'onboarding_done_dns'
                break
            }
            'decommissioning' {
                $this.Mode = $normalizedMode
                $this.ProcessName = 'IpDnsDecommissioning'
                $this.SourceStatuses = @('decommissioning_open_dns')
                $this.TargetStatus = 'decommissioning_done_dns'
                break
            }
            default {
                throw [System.ArgumentOutOfRangeException]::new('mode', "Unsupported IP DNS lifecycle mode '$mode'.")
            }
        }
    }

    <#
    .SYNOPSIS
    Loads matching IP work items and processes them in batch.

    .DESCRIPTION
    Uses the configured source statuses for the current mode to load work items
    from NetBox and then delegates to the reusable batch shell.

    .PARAMETER environment
    The resolved execution environment.

    .OUTPUTS
    BatchRunSummary
    #>
    # Shared batch shell for both lifecycle variants; only the mode-specific strategy changes the business action.
    [BatchRunSummary] ProcessBatch([EnvironmentContext] $environment) {
        $workItems = $this.NetBoxClient.GetIpWorkItems($environment, $this.SourceStatuses)
        return $this.ProcessWorkItems($environment, $workItems)
    }

    <#
    .SYNOPSIS
    Processes explicitly supplied IP work items.

    .DESCRIPTION
    Runs the common lifecycle batch shell without performing repository access.
    This seam exists mainly to keep the orchestration easy to test.

    .PARAMETER environment
    The resolved execution environment.

    .PARAMETER workItems
    IP work items that should be processed in this batch.

    .OUTPUTS
    BatchRunSummary
    #>
    # Splits the reusable lifecycle shell from the repository fetch so tests can cover orchestration with synthetic work items.
    [BatchRunSummary] ProcessWorkItems([EnvironmentContext] $environment, [IpAddressWorkItem[]] $workItems) {
        $summary = [BatchRunSummary]::new($this.ProcessName)
        $loadedWorkItems = @($workItems)
        $summary.AddAudit('Debug', "Loaded $($loadedWorkItems.Count) $($this.GetLifecycleDisplayName()) work item(s) for environment '$($environment.Name)'.")
        $summary.AddAudit('Debug', "Lifecycle mode '$($this.Mode)' configured with source statuses '$($this.SourceStatuses -join ', ')' and target status '$($this.TargetStatus)'.")

        foreach ($workItem in $loadedWorkItems) {
            $this.ProcessWorkItem($workItem, $summary)
        }

        $summary.Complete()
        return $summary
    }

    <#
    .SYNOPSIS
    Processes one IP work item through the shared lifecycle flow.

    .DESCRIPTION
    Applies the template-method style sequence of validation, DNS action,
    NetBox status update, logging, journaling, and failure translation.

    .PARAMETER workItem
    The IP work item that is currently being handled.

    .PARAMETER summary
    Batch summary that aggregates audit and result information.
    #>
    # Template-method style execution: invariant steps stay fixed while mode-dependent behavior is delegated to helper methods.
    hidden [void] ProcessWorkItem([IpAddressWorkItem] $workItem, [BatchRunSummary] $summary) {
        $lines = @($this.GetProcessingLine($workItem))
        $lines += ('Lifecycle mode: {0}' -f $this.Mode)
        $lines += ('Source status: {0}' -f $workItem.Status)
        $lines += ('Target status: {0}' -f $this.TargetStatus)
        $lines += ('Domain: {0}' -f $workItem.Domain)
        $lines += ('Prefix subnet: {0}' -f $workItem.PrefixSubnet.Cidr)
        if (-not [string]::IsNullOrWhiteSpace($workItem.DnsName)) {
            $lines += ('DNS name: {0}' -f $workItem.DnsName)
        }
        else {
            $lines += 'DNS name: <none>'
        }
        $summary.AddAudit('Debug', "Starting $($this.GetLifecycleDisplayName()) work item '$($workItem.GetIdentifier())'.")

        try {
            $this.ValidateWorkItem($workItem)
            $dnsContext = $this.GatewayDnsService.GetDnsExecutionContext($workItem.PrefixSubnet)
            $lines += ('Selected domain controller: {0}' -f $dnsContext.DomainController)
            $lines += ('Resolved reverse zone: {0}' -f $dnsContext.ReverseZone)
            $summary.AddAudit('Debug', "Resolved DNS context for IP '$($workItem.GetIdentifier())': DC='$($dnsContext.DomainController)', ReverseZone='$($dnsContext.ReverseZone)'.")
            $this.ExecuteDnsLifecycle($workItem)
            $lines += $this.GetDnsLifecycleResultLine()

            $this.NetBoxClient.UpdateIpStatus($workItem.Id, $this.TargetStatus)
            $lines += ('IP status updated to {0}.' -f $this.TargetStatus)

            $lines = $this.WriteExecutionLog($workItem, $lines)
            $this.JournalService.WriteIpInfo($workItem, $lines)
            $summary.AddAudit('Information', "Completed $($this.GetLifecycleDisplayName()) work item '$($workItem.GetIdentifier())'.")
            $summary.AddSuccess($this.GetSuccessSummaryMessage($workItem))
        }
        catch {
            $this.HandleProcessingFailure($workItem, $lines, $summary, $_.Exception)
        }
    }

    <#
    .SYNOPSIS
    Validates lifecycle-specific work item requirements.

    .DESCRIPTION
    Enforces mode-specific preconditions before side effects are triggered. At
    the moment only onboarding requires a DNS name, but the seam is prepared
    for additional mode rules.

    .PARAMETER workItem
    Work item to validate before processing.
    #>
    hidden [void] ValidateWorkItem([IpAddressWorkItem] $workItem) {
        Write-Debug -Message ("Validating IP lifecycle work item '{0}' in mode '{1}'." -f $workItem.GetIdentifier(), $this.Mode)
        if ($this.Mode -eq 'onboarding' -and [string]::IsNullOrWhiteSpace($workItem.DnsName)) {
            throw [System.InvalidOperationException]::new("DNS name is missing for IP '$($workItem.GetIdentifier())'.")
        }

        Write-Debug -Message ("Validation passed for IP lifecycle work item '{0}'." -f $workItem.GetIdentifier())
    }

    <#
    .SYNOPSIS
    Executes the DNS action for the configured lifecycle mode.

    .DESCRIPTION
    Dispatches to the gateway DNS facade based on the active mode. New lifecycle
    variants should extend this method instead of copying the full workflow.

    .PARAMETER workItem
    Work item for which DNS should be changed.
    #>
    # Strategy dispatch for the lifecycle action; new modes should extend this seam instead of duplicating the service.
    hidden [void] ExecuteDnsLifecycle([IpAddressWorkItem] $workItem) {
        switch ($this.Mode) {
            'onboarding' {
                Write-Verbose -Message ("Executing IP DNS onboarding for '{0}'." -f $workItem.GetIdentifier())
                $this.GatewayDnsService.EnsureIpDns($workItem)
                break
            }
            'decommissioning' {
                Write-Verbose -Message ("Executing IP DNS decommissioning for '{0}'." -f $workItem.GetIdentifier())
                $this.GatewayDnsService.RemoveIpDns($workItem)
                break
            }
            default {
                throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.")
            }
        }
    }

    <#
    .SYNOPSIS
    Translates an IP processing exception into reporting artifacts.

    .DESCRIPTION
    Appends the failure to the execution log, attempts to write a NetBox error
    journal, and records the issue in the batch summary.

    .PARAMETER workItem
    Work item that failed.

    .PARAMETER lines
    Accumulated execution log lines.

    .PARAMETER summary
    Batch summary that receives warnings and failure records.

    .PARAMETER exception
    Exception that caused the failure.
    #>
    hidden [void] HandleProcessingFailure(
        [IpAddressWorkItem] $workItem,
        [string[]] $lines,
        [BatchRunSummary] $summary,
        [System.Exception] $exception
    ) {
        $message = $this.GetFailureMessage($workItem, $exception)
        $lines += $message
        $lines = $this.WriteExecutionLog($workItem, $lines)

        try {
            $this.JournalService.WriteIpError($workItem, $lines)
        }
        catch {
            $summary.AddAudit('Warning', "Failed to write NetBox error journal for IP '$($workItem.GetIdentifier())'. $($_.Exception.Message)")
        }

        $summary.AddFailure(
            [OperationIssue]::new(
                'IPAddress',
                $workItem.GetIdentifier(),
                $message,
                $exception.ToString(),
                $this.BuildFailureHandlingContext($workItem, $exception),
                $this.NetBoxClient.GetIpAddressUrl($workItem.Id)
            )
        )
    }

    <#
    .SYNOPSIS
    Builds the handling context for a failed IP work item.

    .DESCRIPTION
    Provides the future extension seam for assigning ownership to operational
    failures without coupling that policy to the main workflow.

    .OUTPUTS
    IssueHandlingContext
    #>
    hidden [IssueHandlingContext] BuildFailureHandlingContext([IpAddressWorkItem] $workItem, [System.Exception] $exception) {
        return [IssueHandlingContext]::CreateUnassigned()
    }

    <#
    .SYNOPSIS
    Writes the execution log for one IP work item.

    .DESCRIPTION
    Persists the accumulated log lines under the IP log category and appends the
    relative log path to the returned line set.

    .OUTPUTS
    System.String[]
    #>
    hidden [string[]] WriteExecutionLog([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $logPath = $this.LogService.CreateLogPath('ip', $workItem.GetIdentifier())
        $linesWithLogPath = @($lines + ('Log file: {0}' -f $logPath))
        $this.LogService.WriteLog($logPath, $linesWithLogPath)
        return $linesWithLogPath
    }

    <#
    .SYNOPSIS
    Returns a human-readable name for the configured lifecycle mode.

    .OUTPUTS
    System.String
    #>
    hidden [string] GetLifecycleDisplayName() {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = 'IP onboarding'; break }
            'decommissioning' { $result = 'IP decommissioning'; break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    <#
    .SYNOPSIS
    Returns the first execution-log line for a work item.

    .OUTPUTS
    System.String
    #>
    hidden [string] GetProcessingLine([IpAddressWorkItem] $workItem) {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = ('Processing IP onboarding {0}' -f $workItem.GetIdentifier()); break }
            'decommissioning' { $result = ('Processing IP decommissioning {0}' -f $workItem.GetIdentifier()); break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    <#
    .SYNOPSIS
    Returns the lifecycle-specific DNS result line.

    .OUTPUTS
    System.String
    #>
    hidden [string] GetDnsLifecycleResultLine() {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = 'DNS records ensured.'; break }
            'decommissioning' { $result = 'DNS records removed.'; break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    <#
    .SYNOPSIS
    Returns the success summary message for a completed work item.

    .OUTPUTS
    System.String
    #>
    hidden [string] GetSuccessSummaryMessage([IpAddressWorkItem] $workItem) {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = ('Completed IP DNS onboarding for {0}' -f $workItem.GetIdentifier()); break }
            'decommissioning' { $result = ('Completed IP DNS decommissioning for {0}' -f $workItem.GetIdentifier()); break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    <#
    .SYNOPSIS
    Returns the failure message for a failed work item.

    .OUTPUTS
    System.String
    #>
    hidden [string] GetFailureMessage([IpAddressWorkItem] $workItem, [System.Exception] $exception) {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = "Failed to process IP '$($workItem.GetIdentifier())'. $($exception.Message)"; break }
            'decommissioning' { $result = "Failed to decommission IP '$($workItem.GetIdentifier())'. $($exception.Message)"; break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }
}
