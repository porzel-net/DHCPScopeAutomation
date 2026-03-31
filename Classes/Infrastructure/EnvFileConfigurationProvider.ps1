# Reads flat key-value automation settings from the relative environment file.
<#
.SYNOPSIS
Reads simple key/value configuration from an env-style file.

.DESCRIPTION
Parses a relative configuration file into an in-memory dictionary and exposes
strongly validated getters for required values and string arrays.

.NOTES
Methods:
- EnvFileConfigurationProvider(filePath)
- GetValue(keyName, description)
- GetStringArray(keyName, description)

.EXAMPLE
$provider = [EnvFileConfigurationProvider]::new('.env')
$provider.GetValue('Environment', 'Expected one of: dev, test, prod.')
#>
class EnvFileConfigurationProvider {
    [string] $Path
    [hashtable] $Values

    EnvFileConfigurationProvider([string] $filePath) {
        if ([string]::IsNullOrWhiteSpace($filePath)) {
            $filePath = '.env'
        }

        $this.Path = $filePath
        $this.Values = @{}

        if (Test-Path -Path $this.Path) {
            Write-Verbose -Message ("Loading environment configuration from '{0}'." -f $this.Path)
            foreach ($line in Get-Content -Path $this.Path) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line.TrimStart().StartsWith('#')) { continue }

                $parts = $line -split '=', 2
                if ($parts.Count -eq 2) {
                    $key = $parts[0].Trim()
                    $value = $parts[1].Trim()
                    $this.Values[$key] = $value
                    Write-Debug -Message ("Loaded configuration key '{0}' from '{1}'." -f $key, $this.Path)
                }
            }

            Write-Verbose -Message ("Loaded {0} configuration value(s) from '{1}'." -f $this.Values.Count, $this.Path)
        }
        else {
            Write-Verbose -Message ("Environment configuration file '{0}' was not found." -f $this.Path)
        }
    }

    <#
    .SYNOPSIS
    Returns one required configuration value.
    .OUTPUTS
    System.String
    #>
    [string] GetValue([string] $keyName, [string] $description) {
        if ([string]::IsNullOrWhiteSpace($keyName)) {
            throw [System.ArgumentException]::new('KeyName is required.')
        }

        if (-not $this.Values.ContainsKey($keyName)) {
            throw [System.InvalidOperationException]::new("Environment value '$keyName' is missing. $description")
        }

        Write-Debug -Message ("Resolved required configuration key '{0}'." -f $keyName)
        return [string] $this.Values[$keyName]
    }

    <#
    .SYNOPSIS
    Returns a required comma-separated setting as a normalized array.
    .OUTPUTS
    System.String[]
    #>
    [string[]] GetStringArray([string] $keyName, [string] $description) {
        $rawValue = $this.GetValue($keyName, $description)
        $resolvedValues = @($rawValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Write-Debug -Message ("Resolved configuration list '{0}' with {1} item(s)." -f $keyName, $resolvedValues.Count)
        return $resolvedValues
    }
}
