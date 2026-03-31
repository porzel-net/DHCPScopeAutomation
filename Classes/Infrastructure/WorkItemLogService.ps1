# Creates relative log paths and persists per-run or per-work-item text logs.
<#
.SYNOPSIS
Creates and writes work-item specific log files.

.DESCRIPTION
Centralizes log-path generation and file writing so workflow services can stay
focused on business behavior and still emit deterministic per-item logs.

.NOTES
Methods:
- WorkItemLogService(logBasePath)
- SanitizeIdentifier(identifier)
- CreateLogPath(category, identifier)
- WriteLog(relativePath, lines)

.EXAMPLE
$logService = [WorkItemLogService]::new('logs')
$logService.CreateLogPath('network', '10.20.30.0/24')
#>
class WorkItemLogService {
    [string] $BasePath

    WorkItemLogService([string] $logBasePath) {
        if ([string]::IsNullOrWhiteSpace($logBasePath)) {
            $logBasePath = 'logs'
        }

        $this.BasePath = $logBasePath

        if (-not (Test-Path -Path $this.BasePath)) {
            New-Item -Path $this.BasePath -ItemType Directory -Force | Out-Null
            Write-Verbose -Message ("Created log base path '{0}'." -f $this.BasePath)
        }
        else {
            Write-Verbose -Message ("Using existing log base path '{0}'." -f $this.BasePath)
        }
    }

    <#
    .SYNOPSIS
    Normalizes an identifier for safe file names.
    .OUTPUTS
    System.String
    #>
    hidden [string] SanitizeIdentifier([string] $identifier) {
        if ([string]::IsNullOrWhiteSpace($identifier)) {
            return 'unknown'
        }

        $sanitized = $identifier -replace '[\\/:*?"<>|]', '_'
        $sanitized = $sanitized -replace '\s+', '_'
        return $sanitized
    }

    <#
    .SYNOPSIS
    Builds the relative log path for a work item.
    .OUTPUTS
    System.String
    #>
    [string] CreateLogPath([string] $category, [string] $identifier) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $fileName = '{0}_{1}_{2}.log' -f $category, $this.SanitizeIdentifier($identifier), $timestamp
        $path = Join-Path -Path $this.BasePath -ChildPath $fileName
        Write-Debug -Message ("Created log path '{0}' for category '{1}' and identifier '{2}'." -f $path, $category, $identifier)
        return $path
    }

    <#
    .SYNOPSIS
    Persists the supplied log lines to disk.
    .OUTPUTS
    System.Void
    #>
    [void] WriteLog([string] $relativePath, [string[]] $lines) {
        $content = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
        Write-Debug -Message ("Writing log file '{0}' with {1} non-empty line(s)." -f $relativePath, @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count)
        Set-Content -Path $relativePath -Value $content -Encoding UTF8
    }
}
