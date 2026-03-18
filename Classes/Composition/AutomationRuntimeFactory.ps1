<#
.SYNOPSIS
Builds the runtime object graph for the automation module.

.DESCRIPTION
Acts as the composition root of the module. It resolves configuration and
credentials, constructs infrastructure adapters and application services, and
returns a ready-to-run runtime container.

.NOTES
Methods:
- AutomationRuntimeFactory(requestedEnvironment, requestedEmailRecipients, configurationPath, credentialDirectory)
- CreateRuntime()
- ResolveEnvironment(configurationProvider)
- ResolveEmailRecipients(configurationProvider)

.EXAMPLE
$runtime = $factory.CreateRuntime()
#>
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

    <#
    .SYNOPSIS
    Creates the fully wired runtime for one execution.

    .DESCRIPTION
    Resolves configuration values and credentials, constructs the infrastructure
    and application graph, and returns the runtime container used by the public
    command.

    .OUTPUTS
    AutomationRuntime
    #>
    # Composition root for the module. Dependency construction stays here so application services remain injectable and testable.
    [AutomationRuntime] CreateRuntime() {
        $configurationProvider = [EnvFileConfigurationProvider]::new($this.ConfigurationPath)
        $resolvedEnvironment = $this.ResolveEnvironment($configurationProvider)
        $resolvedRecipients = $this.ResolveEmailRecipients($configurationProvider)
        $environmentContext = [EnvironmentContext]::new($resolvedEnvironment)
        $credentialProvider = [SecureFileCredentialProvider]::new($this.CredentialDirectory)

        $netBoxCredential = $credentialProvider.GetApiCredential('DHCPScopeAutomationNetboxApiKey')
        $jiraCredential = $credentialProvider.GetApiCredential('DHCPScopeAutomationJiraApiKey')

        # All side-effecting adapters are created here so the application layer stays constructor-injected and test-friendly.
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

    <#
    .SYNOPSIS
    Resolves the effective environment name.

    .DESCRIPTION
    Prefers an explicitly requested environment and falls back to the `.env`
    configuration value when no override was provided.

    .OUTPUTS
    System.String
    #>
    hidden [string] ResolveEnvironment([EnvFileConfigurationProvider] $configurationProvider) {
        if (-not [string]::IsNullOrWhiteSpace($this.RequestedEnvironment)) {
            return $this.RequestedEnvironment
        }

        return $configurationProvider.GetValue('Environment', 'Expected one of: dev, test, prod, gov, china.')
    }

    <#
    .SYNOPSIS
    Resolves the effective mail recipient list.

    .DESCRIPTION
    Prefers explicit recipient overrides and falls back to the configured
    recipient list from the environment file.

    .OUTPUTS
    System.String[]
    #>
    hidden [string[]] ResolveEmailRecipients([EnvFileConfigurationProvider] $configurationProvider) {
        if ($this.RequestedEmailRecipients -and $this.RequestedEmailRecipients.Count -gt 0) {
            return @($this.RequestedEmailRecipients)
        }

        return $configurationProvider.GetStringArray('EmailRecipients', 'Expected a comma separated recipient list.')
    }
}
