<#
.SYNOPSIS
Represents a secure credential object with optional appliance, username, password, and API key.

.DESCRIPTION
This class encapsulates credential data and provides methods to retrieve secure and plain versions of sensitive information.
It also includes validation methods to ensure required properties are set before access.
#>
class SecureCredential {
    [string]$Name
    [string]$Appliance
    [string]$Username
    [securestring]$Password
    [securestring]$ApiKey

    <#
    .SYNOPSIS
    Constructor to initialize the credential with a name.
    #>
    SecureCredential([string]$name) {
        $this.Name = $name
    }

    <#
    .SYNOPSIS
    Returns the appliance value after validation.
    #>
    [string]GetAppliance() {
        $this.ExpectAppliance()
        return $this.Appliance
    }

    <#
    .SYNOPSIS
    Validates that the appliance property is set.
    #>
    [void]ExpectAppliance() {
        if(-not $this.Appliance) {
            throw "Property Appliance is not defined in the credentials '$($this.Name)'!"
        }
    }

    <#
    .SYNOPSIS
    Returns the username value after validation.
    #>
    [string]GetUsername() {
        $this.ExpectUsername()
        return $this.Username
    }

    <#
    .SYNOPSIS
    Validates that the username property is set.
    #>
    [void]ExpectUsername() {
        if(-not $this.Username) {
            throw "Property Username is not defined in the credentials '$($this.Name)'!"
        }
    }

    <#
    .SYNOPSIS
    Returns the password as a SecureString after validation.
    #>
    [SecureString]GetSecureStringPassword() {
        $this.ExpectPassword()
        return $this.Password
    }

    <#
    .SYNOPSIS
    Returns the password as plain text after validation (securely freeing unmanaged memory).
    #>
    [string]GetPlainPassword() {
        $this.ExpectPassword()
        $bstr = [IntPtr]::Zero
        try {
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.Password)
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    }

    <#
    .SYNOPSIS
    Validates that the password property is set.
    #>
    [void]ExpectPassword() {
        if(-not $this.Password) {
            throw "Property Password is not defined in the credentials '$($this.Name)'!"
        }
    }

    <#
    .SYNOPSIS
    Returns the API key as a SecureString after validation.
    #>
    [SecureString]GetSecureStringApiKey() {
        $this.ExpectApiKey()
        return $this.ApiKey
    }

    <#
    .SYNOPSIS
    Returns the API key as plain text after validation (securely freeing unmanaged memory).
    #>
    [string]GetPlainApiKey() {
        $this.ExpectApiKey()
        $bstr = [IntPtr]::Zero
        try {
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.ApiKey)
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    }

    <#
    .SYNOPSIS
    Validates that the API key property is set.
    #>
    [void]ExpectApiKey() {
        if(-not $this.ApiKey) {
            throw "Property ApiKey is not defined in the credentials '$($this.Name)'!"
        }
    }

    <#
    .SYNOPSIS
    Loads or creates a SecureCredential object from disk.

    .PARAMETER CredentialName
    The name of the credential to load or create.

    .PARAMETER ForceNew
    Forces creation of a new credential even if one exists.

    .PARAMETER Username
    Prompts for username input.

    .PARAMETER Password
    Prompts for password input.

    .PARAMETER ApiKey
    Prompts for API key input.

    .PARAMETER Appliance
    Prompts for appliance input.

    .OUTPUTS
    SecureCredential
    #>
    static [SecureCredential]Load(
            [string]$CredentialName,
            [bool]$ForceNew = $false,
            [bool]$Username = $false,
            [bool]$Password = $false,
            [bool]$ApiKey = $false,
            [bool]$Appliance = $false
    ) {
        $basePath = Join-Path $pwd "\.secureCreds"
        $credentialsPath = Join-Path $basePath "$CredentialName.xml"

        Write-Verbose ("SecureCredential.Load: BasePath='{0}', File='{1}'" -f $basePath, $credentialsPath)
        Write-Debug   ("Flags -> ForceNew={0}, Username={1}, Password={2}, ApiKey={3}, Appliance={4}" -f $ForceNew, $Username, $Password, $ApiKey, $Appliance)

        if (-not (Test-Path $basePath)) {
            Write-Verbose "Creating credential directory: $basePath"
            New-Item -Path $basePath -ItemType Directory | Out-Null
        }

        if ((Test-Path $credentialsPath) -and -not $ForceNew) {
            try {
                Write-Verbose "Loading '$CredentialName' from '$credentialsPath'..."
                $raw = Import-Clixml -Path $credentialsPath

                $cred = [SecureCredential]::new($CredentialName)
                $cred.Appliance = $raw.Appliance
                $cred.Username  = $raw.Username
                $cred.Password  = $raw.Password
                $cred.ApiKey    = $raw.ApiKey

                Write-Information "Loaded credential '$CredentialName' from disk." -InformationAction Continue
                return $cred
            } catch {
                Write-Warning "Failed to load existing credential: $($_.Exception.Message). Prompting for new input..."
            }
        }

        $cred = [SecureCredential]::new($CredentialName)
        Write-Information "Enter credentials for '$CredentialName':" -InformationAction Continue

        if ($Appliance) {
            $cred.Appliance = Read-Host "Enter appliance (e.g., URL)"
        }

        if ($Username) {
            $cred.Username = Read-Host "Enter username"
        }

        if ($Password) {
            $cred.Password = Read-Host "Enter password" -AsSecureString
        }

        if ($ApiKey) {
            $cred.ApiKey = Read-Host "Enter API key" -AsSecureString
        }

        try {
            $cred | Export-Clixml -Path $credentialsPath
            Write-Information "Credential saved securely to '$credentialsPath'." -InformationAction Continue
        } catch {
            Write-Warning "Failed to save credential: $($_.Exception.Message)"
        }

        return $cred
    }
}

<#
.SYNOPSIS
Retrieves a SecureCredential object by name, optionally prompting for new input.

.DESCRIPTION
This function wraps the SecureCredential::Load method and provides a user-friendly interface
for loading or creating secure credentials.

.PARAMETER CredentialName
The name of the credential to retrieve.

.PARAMETER ForceNew
Forces creation of a new credential.

.PARAMETER Username
Prompts for username input.

.PARAMETER Password
Prompts for password input.

.PARAMETER ApiKey
Prompts for API key input.

.PARAMETER Appliance
Prompts for appliance input.

.OUTPUTS
SecureCredential
#>
function Get-SecureCredential {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$CredentialName,

        [switch]$ForceNew,
        [switch]$Username,
        [switch]$Password,
        [switch]$ApiKey,
        [switch]$Appliance
    )

    Write-Verbose "Retrieving secure credential '$CredentialName'..."
    $cred = [SecureCredential]::Load(
            $CredentialName,
            [bool]$ForceNew,
            [bool]$Username,
            [bool]$Password,
            [bool]$ApiKey,
            [bool]$Appliance
    )

    # Do not log secrets. Only confirm presence of fields.
    Write-Debug ("Retrieved fields -> Appliance:{0}, Username:{1}, PasswordSet:{2}, ApiKeySet:{3}" -f `
        ([bool]$cred.Appliance), ([bool]$cred.Username), ([bool]$cred.Password), ([bool]$cred.ApiKey))

    return $cred
}
