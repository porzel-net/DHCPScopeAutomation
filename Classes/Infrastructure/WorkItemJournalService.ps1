# Writes normalized journal entries back to NetBox targets.
class WorkItemJournalService {
    [NetBoxClient] $NetBoxClient

    WorkItemJournalService([NetBoxClient] $netBoxClient) {
        $this.NetBoxClient = $netBoxClient
    }

    hidden [string] JoinLines([string[]] $lines) {
        return ((@($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine) -replace [Environment]::NewLine, '<br>')
    }

    [void] WriteEntry([string] $targetType, [int] $targetId, [string[]] $lines, [string] $kind) {
        $this.NetBoxClient.AddJournalEntry($targetType, $targetId, $this.JoinLines($lines), $kind)
    }

    [void] WritePrefixInfo([PrefixWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('Prefix', $workItem.Id, $lines, 'info')
    }

    [void] WritePrefixError([PrefixWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('Prefix', $workItem.Id, $lines, 'danger')
    }

    [void] WriteIpInfo([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('IPAddress', $workItem.Id, $lines, 'info')
    }

    [void] WriteIpError([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('IPAddress', $workItem.Id, $lines, 'danger')
    }
}
