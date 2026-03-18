# Reuses one workflow shell for IP DNS onboarding and decommissioning.
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

    # Shared batch shell for both lifecycle variants; only the mode-specific strategy changes the business action.
    [BatchRunSummary] ProcessBatch([EnvironmentContext] $environment) {
        $workItems = $this.NetBoxClient.GetIpWorkItems($environment, $this.SourceStatuses)
        return $this.ProcessWorkItems($environment, $workItems)
    }

    # Splits the reusable lifecycle shell from the repository fetch so tests can cover orchestration with synthetic work items.
    [BatchRunSummary] ProcessWorkItems([EnvironmentContext] $environment, [IpAddressWorkItem[]] $workItems) {
        $summary = [BatchRunSummary]::new($this.ProcessName)
        $loadedWorkItems = @($workItems)
        $summary.AddAudit('Debug', "Loaded $($loadedWorkItems.Count) $($this.GetLifecycleDisplayName()) work item(s) for environment '$($environment.Name)'.")

        foreach ($workItem in $loadedWorkItems) {
            $this.ProcessWorkItem($workItem, $summary)
        }

        $summary.Complete()
        return $summary
    }

    # Template-method style execution: invariant steps stay fixed while mode-dependent behavior is delegated to helper methods.
    hidden [void] ProcessWorkItem([IpAddressWorkItem] $workItem, [BatchRunSummary] $summary) {
        $lines = @($this.GetProcessingLine($workItem))
        $summary.AddAudit('Debug', "Starting $($this.GetLifecycleDisplayName()) work item '$($workItem.GetIdentifier())'.")

        try {
            $this.ValidateWorkItem($workItem)
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

    hidden [void] ValidateWorkItem([IpAddressWorkItem] $workItem) {
        if ($this.Mode -eq 'onboarding' -and [string]::IsNullOrWhiteSpace($workItem.DnsName)) {
            throw [System.InvalidOperationException]::new("DNS name is missing for IP '$($workItem.GetIdentifier())'.")
        }
    }

    # Strategy dispatch for the lifecycle action; new modes should extend this seam instead of duplicating the service.
    hidden [void] ExecuteDnsLifecycle([IpAddressWorkItem] $workItem) {
        switch ($this.Mode) {
            'onboarding' {
                $this.GatewayDnsService.EnsureIpDns($workItem)
                break
            }
            'decommissioning' {
                $this.GatewayDnsService.RemoveIpDns($workItem)
                break
            }
            default {
                throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.")
            }
        }
    }

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

    hidden [IssueHandlingContext] BuildFailureHandlingContext([IpAddressWorkItem] $workItem, [System.Exception] $exception) {
        return [IssueHandlingContext]::CreateUnassigned()
    }

    hidden [string[]] WriteExecutionLog([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $logPath = $this.LogService.CreateLogPath('ip', $workItem.GetIdentifier())
        $linesWithLogPath = @($lines + ('Log file: {0}' -f $logPath))
        $this.LogService.WriteLog($logPath, $linesWithLogPath)
        return $linesWithLogPath
    }

    hidden [string] GetLifecycleDisplayName() {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = 'IP onboarding'; break }
            'decommissioning' { $result = 'IP decommissioning'; break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    hidden [string] GetProcessingLine([IpAddressWorkItem] $workItem) {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = ('Processing IP onboarding {0}' -f $workItem.GetIdentifier()); break }
            'decommissioning' { $result = ('Processing IP decommissioning {0}' -f $workItem.GetIdentifier()); break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    hidden [string] GetDnsLifecycleResultLine() {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = 'DNS records ensured.'; break }
            'decommissioning' { $result = 'DNS records removed.'; break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    hidden [string] GetSuccessSummaryMessage([IpAddressWorkItem] $workItem) {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = ('Completed IP DNS onboarding for {0}' -f $workItem.GetIdentifier()); break }
            'decommissioning' { $result = ('Completed IP DNS decommissioning for {0}' -f $workItem.GetIdentifier()); break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

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
