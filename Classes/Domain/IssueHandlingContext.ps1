# Holds future routing metadata so failures can later be assigned to the right department or handler.
<#
.SYNOPSIS
Stores routing metadata for operational issue ownership.

.DESCRIPTION
Encapsulates the future department and handler assignment for failures so
notification and triage logic can evolve without changing the issue model.

.NOTES
Methods:
- IssueHandlingContext(department, handler)
- CreateUnassigned()
- NormalizeValue(value)
- GetDepartmentOrDefault()
- GetHandlerOrDefault()
- HasAssignedDepartment()
- HasAssignedHandler()

.EXAMPLE
[IssueHandlingContext]::new('FIST', 'Alice')
#>
class IssueHandlingContext {
    [string] $Department
    [string] $Handler

    IssueHandlingContext([string] $department, [string] $handler) {
        $this.Department = $this.NormalizeValue($department)
        $this.Handler = $this.NormalizeValue($handler)
    }

    <#
    .SYNOPSIS
    Creates the default unassigned handling context.
    .OUTPUTS
    IssueHandlingContext
    #>
    static [IssueHandlingContext] CreateUnassigned() {
        return [IssueHandlingContext]::new($null, $null)
    }

    <#
    .SYNOPSIS
    Normalizes an optional routing value.
    .OUTPUTS
    System.String
    #>
    hidden [string] NormalizeValue([string] $value) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }

        return $value.Trim()
    }

    <#
    .SYNOPSIS
    Returns the assigned department or the fallback label.
    .OUTPUTS
    System.String
    #>
    [string] GetDepartmentOrDefault() {
        if ([string]::IsNullOrWhiteSpace($this.Department)) {
            return 'Unassigned'
        }

        return $this.Department
    }

    <#
    .SYNOPSIS
    Returns the assigned handler or the fallback label.
    .OUTPUTS
    System.String
    #>
    [string] GetHandlerOrDefault() {
        if ([string]::IsNullOrWhiteSpace($this.Handler)) {
            return 'Unassigned'
        }

        return $this.Handler
    }

    <#
    .SYNOPSIS
    Indicates whether a department is assigned.
    .OUTPUTS
    System.Boolean
    #>
    [bool] HasAssignedDepartment() {
        return -not [string]::IsNullOrWhiteSpace($this.Department)
    }

    <#
    .SYNOPSIS
    Indicates whether a handler is assigned.
    .OUTPUTS
    System.Boolean
    #>
    [bool] HasAssignedHandler() {
        return -not [string]::IsNullOrWhiteSpace($this.Handler)
    }
}
