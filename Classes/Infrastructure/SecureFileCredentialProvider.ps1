# Loads persisted secure credential files and converts them into automation credentials.
<#
.SYNOPSIS
Loads persisted API credentials from secure XML files.

.DESCRIPTION
Provides the credential storage abstraction for the automation. Existing files are
loaded non-interactively; missing files can be bootstrapped interactively.

.NOTES
Methods:
- SecureFileCredentialProvider(credentialBasePath)
- GetApiCredential(credentialName)

.EXAMPLE
$provider = [SecureFileCredentialProvider]::new('.secureCreds')
$provider.GetApiCredential('DHCPScopeAutomationNetboxApiKey')
#>
class SecureFileCredentialProvider {
    [string] $BasePath

    SecureFileCredentialProvider([string] $credentialBasePath) {
        if ([string]::IsNullOrWhiteSpace($credentialBasePath)) {
            $credentialBasePath = '.secureCreds'
        }

        $this.BasePath = $credentialBasePath

        if (-not (Test-Path -Path $this.BasePath)) {
            New-Item -Path $this.BasePath -ItemType Directory | Out-Null
            Write-Verbose -Message ("Created credential directory '{0}'." -f $this.BasePath)
        }
        else {
            Write-Verbose -Message ("Using credential directory '{0}'." -f $this.BasePath)
        }
    }

    <#
    .SYNOPSIS
    Loads one persisted API credential or bootstraps it interactively.
    .OUTPUTS
    AutomationCredential
    #>
    [AutomationCredential] GetApiCredential([string] $credentialName) {
        if ([string]::IsNullOrWhiteSpace($credentialName)) {
            throw [System.ArgumentException]::new('CredentialName is required.')
        }

        $path = Join-Path -Path $this.BasePath -ChildPath ('{0}.xml' -f $credentialName)
        $loaded = $null

        if (Test-Path -Path $path) {
            Write-Verbose -Message ("Loading credential '{0}' from '{1}'." -f $credentialName, $path)
            try {
                $loaded = Import-Clixml -Path $path
            }
            catch {
                throw [System.InvalidOperationException]::new(
                    ("Credential file '{0}' could not be read. Recreate the file or fix access permissions. {1}" -f $path, $_.Exception.Message)
                )
            }
        }

        if ($null -ne $loaded) {
            if ($loaded.Appliance -and $loaded.ApiKey) {
                Write-Verbose -Message ("Loaded credential '{0}' from secure file." -f $credentialName)
                return [AutomationCredential]::new($credentialName, $loaded.Appliance, $loaded.ApiKey)
            }

            throw [System.InvalidOperationException]::new(
                ("Credential file '{0}' is missing required fields 'Appliance' and/or 'ApiKey'." -f $path)
            )
        }

        Write-Warning -Message ("Credential '{0}' not found on disk. Interactive bootstrap is required." -f $credentialName)
        $appliance = Read-Host ('Enter appliance/base URL for {0}' -f $credentialName)
        $apiKey = Read-Host ('Enter API key for {0}' -f $credentialName) -AsSecureString

        $record = [pscustomobject]@{
            Appliance = $appliance
            ApiKey    = $apiKey
        }

        $record | Export-Clixml -Path $path
        Write-Verbose -Message ("Stored credential '{0}' at '{1}'." -f $credentialName, $path)

        return [AutomationCredential]::new($credentialName, $appliance, $apiKey)
    }
}
