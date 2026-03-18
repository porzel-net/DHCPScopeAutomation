<#
.SYNOPSIS
Defines the runtime-factory seam used by the public entry point.

.DESCRIPTION
Provides the abstract factory contract that allows tests to inject synthetic
runtime graphs without constructing real infrastructure dependencies.

.NOTES
Methods:
- CreateRuntime()

.EXAMPLE
class FakeRuntimeFactory : AutomationRuntimeFactoryBase {
    [AutomationRuntime] CreateRuntime() { return $this.Runtime }
}
#>
class AutomationRuntimeFactoryBase {
    <#
    .SYNOPSIS
    Creates an automation runtime.

    .DESCRIPTION
    Must be implemented by a concrete runtime factory.

    .OUTPUTS
    AutomationRuntime
    #>
    [AutomationRuntime] CreateRuntime() {
        throw [System.NotImplementedException]::new('CreateRuntime() must be implemented by a concrete runtime factory.')
    }
}
