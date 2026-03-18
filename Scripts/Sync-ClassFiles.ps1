[CmdletBinding()]
param(
    [switch] $InitializeFromAggregate
)

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$repoRoot = Split-Path -Path $scriptRoot -Parent
$classesRoot = Join-Path -Path $repoRoot -ChildPath 'Classes'
$aggregatePath = Join-Path -Path $classesRoot -ChildPath 'AllClasses.ps1'

$classDefinitions = @(
    @{ Name = 'OperationAuditEntry';          Path = 'Domain/OperationAuditEntry.ps1' }
    @{ Name = 'IssueHandlingContext';         Path = 'Domain/IssueHandlingContext.ps1' }
    @{ Name = 'OperationIssue';               Path = 'Domain/OperationIssue.ps1' }
    @{ Name = 'BatchRunSummary';              Path = 'Domain/BatchRunSummary.ps1' }
    @{ Name = 'EnvironmentContext';           Path = 'Domain/EnvironmentContext.ps1' }
    @{ Name = 'IPv4Address';                  Path = 'Domain/IPv4Address.ps1' }
    @{ Name = 'IPv4Subnet';                   Path = 'Domain/IPv4Subnet.ps1' }
    @{ Name = 'DhcpExclusionRange';           Path = 'Domain/DhcpExclusionRange.ps1' }
    @{ Name = 'DhcpRange';                    Path = 'Domain/DhcpRange.ps1' }
    @{ Name = 'PrefixWorkItem';               Path = 'Domain/PrefixWorkItem.ps1' }
    @{ Name = 'IpAddressWorkItem';            Path = 'Domain/IpAddressWorkItem.ps1' }
    @{ Name = 'DhcpScopeDefinition';          Path = 'Domain/DhcpScopeDefinition.ps1' }
    @{ Name = 'PrerequisiteEvaluation';       Path = 'Domain/PrerequisiteEvaluation.ps1' }
    @{ Name = 'AutomationCredential';         Path = 'Domain/AutomationCredential.ps1' }
    @{ Name = 'DnsExecutionContext';          Path = 'Domain/DnsExecutionContext.ps1' }
    @{ Name = 'EnvFileConfigurationProvider'; Path = 'Infrastructure/EnvFileConfigurationProvider.ps1' }
    @{ Name = 'SecureFileCredentialProvider'; Path = 'Infrastructure/SecureFileCredentialProvider.ps1' }
    @{ Name = 'NetBoxClient';                 Path = 'Infrastructure/NetBoxClient.ps1' }
    @{ Name = 'JiraClient';                   Path = 'Infrastructure/JiraClient.ps1' }
    @{ Name = 'ActiveDirectoryAdapter';       Path = 'Infrastructure/ActiveDirectoryAdapter.ps1' }
    @{ Name = 'DnsServerAdapter';             Path = 'Infrastructure/DnsServerAdapter.ps1' }
    @{ Name = 'DhcpServerAdapter';            Path = 'Infrastructure/DhcpServerAdapter.ps1' }
    @{ Name = 'SmtpMailClient';               Path = 'Infrastructure/SmtpMailClient.ps1' }
    @{ Name = 'WorkItemLogService';           Path = 'Infrastructure/WorkItemLogService.ps1' }
    @{ Name = 'WorkItemJournalService';       Path = 'Infrastructure/WorkItemJournalService.ps1' }
    @{ Name = 'PrerequisiteValidationService';Path = 'Application/PrerequisiteValidationService.ps1' }
    @{ Name = 'DhcpServerSelectionService';   Path = 'Application/DhcpServerSelectionService.ps1' }
    @{ Name = 'GatewayDnsService';            Path = 'Application/GatewayDnsService.ps1' }
    @{ Name = 'OperationIssueMailFormatter';  Path = 'Application/OperationIssueMailFormatter.ps1' }
    @{ Name = 'BatchNotificationService';     Path = 'Application/BatchNotificationService.ps1' }
    @{ Name = 'PrefixOnboardingService';      Path = 'Application/PrefixOnboardingService.ps1' }
    @{ Name = 'IpDnsLifecycleService';        Path = 'Application/IpDnsLifecycleService.ps1' }
    @{ Name = 'AutomationCoordinator';        Path = 'Application/AutomationCoordinator.ps1' }
    @{ Name = 'AutomationRuntime';            Path = 'Composition/AutomationRuntime.ps1' }
    @{ Name = 'AutomationRuntimeFactoryBase'; Path = 'Composition/AutomationRuntimeFactoryBase.ps1' }
    @{ Name = 'AutomationRuntimeFactory';     Path = 'Composition/AutomationRuntimeFactory.ps1' }
)

function Get-ClassDefinitionMap {
    param(
        [string] $Path
    )

    $parseErrors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $tokens, [ref] $parseErrors)
    if ($parseErrors.Count -gt 0) {
        $messages = @($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "Failed to parse '$Path'. $messages"
    }

    $sourceLines = [System.IO.File]::ReadAllLines($Path)
    $definitions = @{}
    $typeDefinitions = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.TypeDefinitionAst] -and -not $node.IsEnum
    }, $true)

    foreach ($typeDefinition in @($typeDefinitions)) {
        $startLine = $typeDefinition.Extent.StartLineNumber
        $commentStart = $startLine

        while ($commentStart -gt 1) {
            $candidateLine = $sourceLines[$commentStart - 2]
            if ([string]::IsNullOrWhiteSpace($candidateLine)) {
                break
            }

            if ($candidateLine.TrimStart().StartsWith('#')) {
                $commentStart--
                continue
            }

            break
        }

        $lineCount = $typeDefinition.Extent.EndLineNumber - $commentStart + 1
        $text = ($sourceLines | Select-Object -Skip ($commentStart - 1) -First $lineCount) -join [Environment]::NewLine
        $definitions[$typeDefinition.Name] = $text.TrimEnd()
    }

    return $definitions
}

function Initialize-ClassFilesFromAggregate {
    param(
        [string] $SourcePath
    )

    $definitionMap = Get-ClassDefinitionMap -Path $SourcePath

    foreach ($classDefinition in $classDefinitions) {
        $className = $classDefinition.Name
        if (-not $definitionMap.ContainsKey($className)) {
            throw "Could not find class '$className' in '$SourcePath'."
        }

        $targetPath = Join-Path -Path $classesRoot -ChildPath $classDefinition.Path
        $targetDirectory = Split-Path -Path $targetPath -Parent
        if (-not (Test-Path -Path $targetDirectory)) {
            New-Item -Path $targetDirectory -ItemType Directory -Force | Out-Null
        }

        [System.IO.File]::WriteAllText($targetPath, $definitionMap[$className] + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    }
}

function Build-ClassAggregate {
    $parts = @(
        '# Generated from Classes/* by Scripts/Sync-ClassFiles.ps1.'
        '# Keep module loading on this single file for PowerShell 5.1 class parser compatibility.'
        ''
    )

    foreach ($classDefinition in $classDefinitions) {
        $classPath = Join-Path -Path $classesRoot -ChildPath $classDefinition.Path
        if (-not (Test-Path -Path $classPath)) {
            throw "Expected class file '$classPath' does not exist."
        }

        $parts += (Get-Content -Path $classPath -Raw).TrimEnd()
        $parts += ''
    }

    $content = ($parts -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
    [System.IO.File]::WriteAllText($aggregatePath, $content, [System.Text.UTF8Encoding]::new($false))
}

if ($InitializeFromAggregate) {
    Initialize-ClassFilesFromAggregate -SourcePath $aggregatePath
}

Build-ClassAggregate
