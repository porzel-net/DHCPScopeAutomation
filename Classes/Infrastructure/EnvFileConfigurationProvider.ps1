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
            foreach ($line in Get-Content -Path $this.Path) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line.TrimStart().StartsWith('#')) { continue }

                $parts = $line -split '=', 2
                if ($parts.Count -eq 2) {
                    $key = $parts[0].Trim()
                    $value = $parts[1].Trim()
                    $this.Values[$key] = $value
                }
            }
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
        return @($rawValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
}
