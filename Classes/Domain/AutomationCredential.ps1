# Stores a username and secure password for external system access.
class AutomationCredential {
    [string] $Name
    [string] $Appliance
    [securestring] $ApiKey

    AutomationCredential([string] $name, [string] $appliance, [securestring] $apiKey) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw [System.ArgumentException]::new('Name is required.') }
        if ([string]::IsNullOrWhiteSpace($appliance)) { throw [System.ArgumentException]::new('Appliance is required.') }
        if ($null -eq $apiKey) { throw [System.ArgumentNullException]::new('apiKey') }

        $this.Name = $name
        $this.Appliance = $appliance
        $this.ApiKey = $apiKey
    }

    [string] GetPlainApiKey() {
        $pointer = [System.IntPtr]::Zero
        try {
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.ApiKey)
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        }
        finally {
            if ($pointer -ne [System.IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
            }
        }
    }
}
