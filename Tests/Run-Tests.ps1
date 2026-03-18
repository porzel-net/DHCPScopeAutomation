[CmdletBinding()]
param()

$moduleRoot = Split-Path -Path $PSScriptRoot -Parent

if (-not (Get-Module -ListAvailable -Name Pester)) {
    Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module -Name Pester -MinimumVersion 5.0 -Force

$configuration = [PesterConfiguration]::Default
$configuration.Run.Path = $PSScriptRoot
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.CodeCoverage.Enabled = $true
$configuration.CodeCoverage.Path = @(
    @(Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Classes') -Filter '*.ps1' -Recurse |
        Where-Object { $_.Name -ne 'ImportClasses.ps1' } |
        Select-Object -ExpandProperty FullName),
    (Join-Path -Path $moduleRoot -ChildPath 'Public/*.ps1'),
    (Join-Path -Path $moduleRoot -ChildPath 'Private/*.ps1')
)

$result = Invoke-Pester -Configuration $configuration
$result

if ($result.FailedCount -gt 0) {
    exit 1
}
