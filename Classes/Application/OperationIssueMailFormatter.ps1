# Formats grouped operational failures into a mail body that humans can triage quickly.
class OperationIssueMailFormatter {
    hidden [string] EscapeHtml([string] $value) {
        if ($null -eq $value) {
            return ''
        }

        return [System.Security.SecurityElement]::Escape($value)
    }

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
