# Builds the runtime object graph and acts as the composition root of the module.
class AutomationRuntimeFactory : AutomationRuntimeFactoryBase {
    [string] $RequestedEnvironment
    [string[]] $RequestedEmailRecipients
    [string] $ConfigurationPath
    [string] $CredentialDirectory

    AutomationRuntimeFactory(
        [string] $requestedEnvironment,
        [string[]] $requestedEmailRecipients,
        [string] $configurationPath,
        [string] $credentialDirectory
    ) {
        $this.RequestedEnvironment = $requestedEnvironment
        $this.RequestedEmailRecipients = @($requestedEmailRecipients | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        $this.ConfigurationPath = $configurationPath
        $this.CredentialDirectory = $credentialDirectory
    }

    # Composition root for the module. Dependency construction stays here so application services remain injectable and testable.
    [AutomationRuntime] CreateRuntime() {
        $configurationProvider = [EnvFileConfigurationProvider]::new($this.ConfigurationPath)
        $resolvedEnvironment = $this.ResolveEnvironment($configurationProvider)
        $resolvedRecipients = $this.ResolveEmailRecipients($configurationProvider)
        $environmentContext = [EnvironmentContext]::new($resolvedEnvironment)
        $credentialProvider = [SecureFileCredentialProvider]::new($this.CredentialDirectory)

        $netBoxCredential = $credentialProvider.GetApiCredential('DHCPScopeAutomationNetboxApiKey')
        $jiraCredential = $credentialProvider.GetApiCredential('DHCPScopeAutomationJiraApiKey')

        $activeDirectoryAdapter = [ActiveDirectoryAdapter]::new()
        $dnsServerAdapter = [DnsServerAdapter]::new()
        $dhcpServerAdapter = [DhcpServerAdapter]::new()
        $netBoxClient = [NetBoxClient]::new($netBoxCredential)
        $jiraClient = [JiraClient]::new($jiraCredential)
        $mailClient = [SmtpMailClient]::new($activeDirectoryAdapter)
        $mailFormatter = [OperationIssueMailFormatter]::new()
        $logService = [WorkItemLogService]::new('logs')

        $prerequisiteValidationService = [PrerequisiteValidationService]::new($activeDirectoryAdapter, $dnsServerAdapter, $jiraClient)
        $dhcpServerSelectionService = [DhcpServerSelectionService]::new($dhcpServerAdapter)
        $gatewayDnsService = [GatewayDnsService]::new($activeDirectoryAdapter, $dnsServerAdapter)
        $journalService = [WorkItemJournalService]::new($netBoxClient)
        $notificationService = [BatchNotificationService]::new($mailClient, $mailFormatter)

        $prefixOnboardingService = [PrefixOnboardingService]::new(
            $netBoxClient,
            $activeDirectoryAdapter,
            $jiraClient,
            $prerequisiteValidationService,
            $dhcpServerSelectionService,
            $dhcpServerAdapter,
            $gatewayDnsService,
            $journalService,
            $logService
        )

        $ipDnsOnboardingService = [IpDnsLifecycleService]::new('onboarding', $netBoxClient, $gatewayDnsService, $journalService, $logService)
        $ipDnsDecommissioningService = [IpDnsLifecycleService]::new('decommissioning', $netBoxClient, $gatewayDnsService, $journalService, $logService)

        $coordinator = [AutomationCoordinator]::new(
            $prefixOnboardingService,
            $ipDnsOnboardingService,
            $ipDnsDecommissioningService,
            $notificationService
        )

        return [AutomationRuntime]::new($environmentContext, $resolvedRecipients, $coordinator, $logService)
    }

    hidden [string] ResolveEnvironment([EnvFileConfigurationProvider] $configurationProvider) {
        if (-not [string]::IsNullOrWhiteSpace($this.RequestedEnvironment)) {
            return $this.RequestedEnvironment
        }

        return $configurationProvider.GetValue('Environment', 'Expected one of: dev, test, prod, gov, china.')
    }

    hidden [string[]] ResolveEmailRecipients([EnvFileConfigurationProvider] $configurationProvider) {
        if ($this.RequestedEmailRecipients -and $this.RequestedEmailRecipients.Count -gt 0) {
            return @($this.RequestedEmailRecipients)
        }

        return $configurationProvider.GetStringArray('EmailRecipients', 'Expected a comma separated recipient list.')
    }
}
