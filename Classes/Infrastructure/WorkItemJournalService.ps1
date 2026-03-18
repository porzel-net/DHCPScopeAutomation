# Writes normalized journal entries back to NetBox targets.
<#
.SYNOPSIS
Writes normalized journal entries back to NetBox.

.DESCRIPTION
Converts line arrays into NetBox journal markup and provides typed entry points
for prefix and IP information and error messages.

.NOTES
Methods:
- WorkItemJournalService(netBoxClient)
- JoinLines(lines)
- WriteEntry(targetType, targetId, lines, kind)
- WritePrefixInfo(workItem, lines)
- WritePrefixError(workItem, lines)
- WriteIpInfo(workItem, lines)
- WriteIpError(workItem, lines)

.EXAMPLE
$journalService = [WorkItemJournalService]::new($netBoxClient)
$journalService.WritePrefixInfo($workItem, @('Completed'))
#>
class WorkItemJournalService {
    [NetBoxClient] $NetBoxClient

    WorkItemJournalService([NetBoxClient] $netBoxClient) {
        $this.NetBoxClient = $netBoxClient
    }

    <#
    .SYNOPSIS
    Joins journal lines into NetBox-friendly HTML markup.
    .OUTPUTS
    System.String
    #>
    hidden [string] JoinLines([string[]] $lines) {
        return ((@($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine) -replace [Environment]::NewLine, '<br>')
    }

    <#
    .SYNOPSIS
    Writes one normalized journal entry to NetBox.
    .OUTPUTS
    System.Void
    #>
    [void] WriteEntry([string] $targetType, [int] $targetId, [string[]] $lines, [string] $kind) {
        $this.NetBoxClient.AddJournalEntry($targetType, $targetId, $this.JoinLines($lines), $kind)
    }

    <#
    .SYNOPSIS
    Writes an informational prefix journal entry.
    .OUTPUTS
    System.Void
    #>
    [void] WritePrefixInfo([PrefixWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('Prefix', $workItem.Id, $lines, 'info')
    }

    <#
    .SYNOPSIS
    Writes an error prefix journal entry.
    .OUTPUTS
    System.Void
    #>
    [void] WritePrefixError([PrefixWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('Prefix', $workItem.Id, $lines, 'danger')
    }

    <#
    .SYNOPSIS
    Writes an informational IP journal entry.
    .OUTPUTS
    System.Void
    #>
    [void] WriteIpInfo([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('IPAddress', $workItem.Id, $lines, 'info')
    }

    <#
    .SYNOPSIS
    Writes an error IP journal entry.
    .OUTPUTS
    System.Void
    #>
    [void] WriteIpError([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('IPAddress', $workItem.Id, $lines, 'danger')
    }
}
