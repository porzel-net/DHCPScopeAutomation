# Creates relative log paths and persists per-run or per-work-item text logs.
class WorkItemLogService {
    [string] $BasePath

    WorkItemLogService([string] $logBasePath) {
        if ([string]::IsNullOrWhiteSpace($logBasePath)) {
            $logBasePath = 'logs'
        }

        $this.BasePath = $logBasePath

        if (-not (Test-Path -Path $this.BasePath)) {
            New-Item -Path $this.BasePath -ItemType Directory -Force | Out-Null
        }
    }

    hidden [string] SanitizeIdentifier([string] $identifier) {
        if ([string]::IsNullOrWhiteSpace($identifier)) {
            return 'unknown'
        }

        $sanitized = $identifier -replace '[\\/:*?"<>|]', '_'
        $sanitized = $sanitized -replace '\s+', '_'
        return $sanitized
    }

    [string] CreateLogPath([string] $category, [string] $identifier) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $fileName = '{0}_{1}_{2}.log' -f $category, $this.SanitizeIdentifier($identifier), $timestamp
        return (Join-Path -Path $this.BasePath -ChildPath $fileName)
    }

    [void] WriteLog([string] $relativePath, [string[]] $lines) {
        $content = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
        Set-Content -Path $relativePath -Value $content -Encoding UTF8
    }
}
