# Loads all class definitions in dependency order so the module can use split
# class files without relying on an aggregated source file.
$classFiles = @(
    'Domain/OperationAuditEntry.ps1'
    'Domain/IssueHandlingContext.ps1'
    'Domain/OperationIssue.ps1'
    'Domain/BatchRunSummary.ps1'
    'Domain/EnvironmentContext.ps1'
    'Domain/IPv4Address.ps1'
    'Domain/IPv4Subnet.ps1'
    'Domain/DhcpExclusionRange.ps1'
    'Domain/DhcpRange.ps1'
    'Domain/PrefixWorkItem.ps1'
    'Domain/IpAddressWorkItem.ps1'
    'Domain/DhcpScopeDefinition.ps1'
    'Domain/PrerequisiteEvaluation.ps1'
    'Domain/AutomationCredential.ps1'
    'Domain/DnsExecutionContext.ps1'
    'Infrastructure/EnvFileConfigurationProvider.ps1'
    'Infrastructure/SecureFileCredentialProvider.ps1'
    'Infrastructure/NetBoxClient.ps1'
    'Infrastructure/JiraClient.ps1'
    'Infrastructure/ActiveDirectoryAdapter.ps1'
    'Infrastructure/DnsServerAdapter.ps1'
    'Infrastructure/DhcpServerAdapter.ps1'
    'Infrastructure/SmtpMailClient.ps1'
    'Infrastructure/WorkItemLogService.ps1'
    'Infrastructure/WorkItemJournalService.ps1'
    'Application/PrerequisiteValidationService.ps1'
    'Application/DhcpServerSelectionService.ps1'
    'Application/GatewayDnsService.ps1'
    'Application/OperationIssueMailFormatter.ps1'
    'Application/BatchNotificationService.ps1'
    'Application/PrefixOnboardingService.ps1'
    'Application/IpDnsLifecycleService.ps1'
    'Application/AutomationCoordinator.ps1'
    'Composition/AutomationRuntime.ps1'
    'Composition/AutomationRuntimeFactoryBase.ps1'
    'Composition/AutomationRuntimeFactory.ps1'
)

foreach ($classFile in $classFiles) {
    . (Join-Path -Path $PSScriptRoot -ChildPath $classFile)
}
