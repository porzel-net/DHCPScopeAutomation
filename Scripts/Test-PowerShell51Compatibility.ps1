[CmdletBinding()]
param()

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module PSScriptAnalyzer -Force

$settings = @{
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1')
        }
        PSUseCompatibleCommands = @{
            Enable = $true
            TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
        }
        PSUseCompatibleTypes = @{
            Enable = $true
            TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
        }
    }
}

$syntaxOnlyRules = @(
    'PSUseCompatibleSyntax'
)

$runtimeCompatibilityRules = @(
    'PSUseCompatibleSyntax',
    'PSUseCompatibleCommands',
    'PSUseCompatibleTypes'
)

$syntaxOnlyPaths = @(
    './Classes',
    './Tests',
    './Scripts'
)

$runtimePaths = @(
    './Classes/AllClasses.ps1',
    './Private',
    './Public'
)

$results = @()

foreach ($path in $syntaxOnlyPaths) {
    $results += @(Invoke-ScriptAnalyzer -Path $path -Recurse -Settings $settings -IncludeRule $syntaxOnlyRules)
}

foreach ($path in $runtimePaths) {
    $results += @(Invoke-ScriptAnalyzer -Path $path -Recurse -Settings $settings -IncludeRule $runtimeCompatibilityRules)
}

$results = @($results | Where-Object { $_.RuleName -ne 'TypeNotFound' })

if (-not $results) {
    Write-Output 'NO_FINDINGS'
    return
}

$results |
    Sort-Object -Property ScriptName, Line, RuleName |
    Select-Object RuleName, Severity, ScriptName, Line, Message

exit 1
