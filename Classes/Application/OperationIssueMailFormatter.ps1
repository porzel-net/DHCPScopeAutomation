<#
.SYNOPSIS
Formats grouped operation issues into an HTML failure summary mail.

.DESCRIPTION
Builds human-readable mail markup that groups issues by handling department and
optionally includes assignee and deep-link information for triage.

.NOTES
Methods:
- EscapeHtml(value)
- GroupByDepartment(issues)
- BuildIssueMarkup(issue)
- BuildDepartmentSection(department, issues)
- BuildFailureSummaryBody(issues)

.EXAMPLE
$body = $formatter.BuildFailureSummaryBody($issues)
#>
class OperationIssueMailFormatter {
    <#
    .SYNOPSIS
    Escapes HTML-sensitive content for safe mail rendering.

    .OUTPUTS
    System.String
    #>
    hidden [string] EscapeHtml([string] $value) {
        if ($null -eq $value) {
            return ''
        }

        return [System.Security.SecurityElement]::Escape($value)
    }

    <#
    .SYNOPSIS
    Groups issues by handling department.

    .OUTPUTS
    System.Collections.Hashtable
    #>
    hidden [hashtable] GroupByDepartment([OperationIssue[]] $issues) {
        $groups = @{}

        foreach ($issue in @($issues)) {
            $department = $issue.GetHandlingDepartment()
            if (-not $groups.ContainsKey($department)) {
                $groups[$department] = @()
            }

            $groups[$department] = @($groups[$department] + $issue)
        }

        return $groups
    }

    <#
    .SYNOPSIS
    Builds the HTML list item for a single issue.

    .OUTPUTS
    System.String
    #>
    hidden [string] BuildIssueMarkup([OperationIssue] $issue) {
        $handlerMarkup = ''
        if ($issue.HandlingContext.HasAssignedHandler()) {
            $handlerMarkup = ('<br><small>Handler: {0}</small>' -f $this.EscapeHtml($issue.GetHandlingHandler()))
        }

        $identifierMarkup = ('<strong>{0}</strong>' -f $this.EscapeHtml($issue.WorkItemIdentifier))
        if ($issue.HasResourceUrl()) {
            $identifierMarkup = ('<a href="{0}"><strong>{1}</strong></a>' -f $this.EscapeHtml($issue.ResourceUrl), $this.EscapeHtml($issue.WorkItemIdentifier))
        }

        return '<li>{0} [{1}] {2}{3}</li>' -f `
            $identifierMarkup, `
            $this.EscapeHtml($issue.WorkItemType), `
            $this.EscapeHtml($issue.Message), `
            $handlerMarkup
    }

    <#
    .SYNOPSIS
    Builds the HTML section for one department.

    .OUTPUTS
    System.String
    #>
    hidden [string] BuildDepartmentSection([string] $department, [OperationIssue[]] $issues) {
        $items = @()
        foreach ($issue in @($issues)) {
            $items += $this.BuildIssueMarkup($issue)
        }

        return @"
<h3>$($this.EscapeHtml($department)) ($($issues.Count))</h3>
<ul>
$($items -join [Environment]::NewLine)
</ul>
"@
    }

    <#
    .SYNOPSIS
    Builds the full failure summary mail body.

    .DESCRIPTION
    Returns `$null` when no issues are present. Otherwise it renders a grouped
    HTML body that operators can triage quickly.

    .OUTPUTS
    System.String
    #>
    [string] BuildFailureSummaryBody([OperationIssue[]] $issues) {
        if (-not $issues) {
            return $null
        }

        $departmentSections = @()
        $groupedIssues = $this.GroupByDepartment($issues)

        foreach ($department in @($groupedIssues.Keys | Sort-Object)) {
            $departmentSections += $this.BuildDepartmentSection($department, @($groupedIssues[$department]))
        }

        return @"
<p>During the execution of the <strong>DHCPScopeAutomation</strong> rewrite, work items failed.</p>
<p>Failures are grouped by handling department. Department ownership is prepared in the model, but explicit assignment rules are not configured yet.</p>
$($departmentSections -join [Environment]::NewLine)
<p><em>This is an automated message. No reply is required.</em></p>
"@
    }
}
