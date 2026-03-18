# Holds future routing metadata so failures can later be assigned to the right department or handler.
class IssueHandlingContext {
    [string] $Department
    [string] $Handler

    IssueHandlingContext([string] $department, [string] $handler) {
        $this.Department = $this.NormalizeValue($department)
        $this.Handler = $this.NormalizeValue($handler)
    }

    static [IssueHandlingContext] CreateUnassigned() {
        return [IssueHandlingContext]::new($null, $null)
    }

    hidden [string] NormalizeValue([string] $value) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }

        return $value.Trim()
    }

    [string] GetDepartmentOrDefault() {
        if ([string]::IsNullOrWhiteSpace($this.Department)) {
            return 'Unassigned'
        }

        return $this.Department
    }

    [string] GetHandlerOrDefault() {
        if ([string]::IsNullOrWhiteSpace($this.Handler)) {
            return 'Unassigned'
        }

        return $this.Handler
    }

    [bool] HasAssignedDepartment() {
        return -not [string]::IsNullOrWhiteSpace($this.Department)
    }

    [bool] HasAssignedHandler() {
        return -not [string]::IsNullOrWhiteSpace($this.Handler)
    }
}
