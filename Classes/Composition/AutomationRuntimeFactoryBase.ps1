# Base factory seam for runtime creation so the public entry point can be tested without real infrastructure.
class AutomationRuntimeFactoryBase {
    [AutomationRuntime] CreateRuntime() {
        throw [System.NotImplementedException]::new('CreateRuntime() must be implemented by a concrete runtime factory.')
    }
}
