# Stores a username and secure password for external system access.
<#
.SYNOPSIS
Stores one appliance endpoint and API key pair.

.DESCRIPTION
Provides the minimal credential value object used by REST clients such as NetBox
and Jira. The secure string is only converted to plain text at send time.

.NOTES
Methods:
- AutomationCredential(name, appliance, apiKey)
- GetPlainApiKey()

.EXAMPLE
[AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
#>
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

    <#
    .SYNOPSIS
    Returns the API key as plain text for outbound requests.

    .DESCRIPTION
    Converts the secure string only for the short period required to build an
    outbound HTTP authorization header.

    .OUTPUTS
    System.String
    #>
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
