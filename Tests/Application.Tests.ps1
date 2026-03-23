Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'DHCPScopeAutomation.psd1') -Force

Describe 'Application services' {
    InModuleScope DHCPScopeAutomation {
        BeforeAll {
            if (-not ('FakeActiveDirectoryAdapter' -as [type])) {
                Invoke-Expression @'
class FakeActiveDirectoryAdapter : ActiveDirectoryAdapter {
    [string] $DomainControllerName = 'dc01.example.test'
    [string] $DomainDnsRoot = 'de.mtu.corp'
    [string] $ForestShortNameValue = 'MTU'
    [string] $SubnetSiteValue

    [string] GetDomainControllerName() {
        return $this.DomainControllerName
    }

    [string] GetDomainDnsRoot() {
        return $this.DomainDnsRoot
    }

    [string] GetForestShortName([string] $domain) {
        return $this.ForestShortNameValue
    }

    [string] GetSubnetSite([IPv4Subnet] $subnet, [string] $domainController) {
        return $this.SubnetSiteValue
    }
}

class FakeDnsServerAdapter : DnsServerAdapter {
    [string] $ReverseZoneName = '30.20.10.in-addr.arpa'
    [bool] $HasDelegation = $true
    [System.Collections.Generic.List[string]] $EnsuredDns = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $RemovedDns = [System.Collections.Generic.List[string]]::new()

    [string] FindBestReverseZoneName([IPv4Subnet] $subnet, [string] $dnsComputerName) {
        return $this.ReverseZoneName
    }

    [bool] TestReverseZoneDelegation([IPv4Subnet] $subnet, [string] $domain) {
        return $this.HasDelegation
    }

    [void] EnsureDnsRecordsForIp(
        [string] $dnsServer,
        [string] $dnsZone,
        [string] $dnsName,
        [IPv4Address] $ipAddress,
        [string] $reverseZone,
        [string] $ptrDomainName
    ) {
        $null = $this.EnsuredDns.Add(('{0}|{1}|{2}' -f $dnsZone, $dnsName, $ipAddress.Value))
    }

    [void] RemoveDnsRecordsForIp([string] $dnsServer, [string] $dnsZone, [string] $reverseZone, [IPv4Address] $ipAddress) {
        $null = $this.RemovedDns.Add(('{0}|{1}' -f $dnsZone, $ipAddress.Value))
    }
}

class FakeJiraClient : JiraClient {
    [System.Collections.Generic.List[string]] $ClosedTickets = [System.Collections.Generic.List[string]]::new()
    [string] $CreatedTicketUrl = 'https://jira.example.test/browse/TCO-123'

    FakeJiraClient([AutomationCredential] $credential) : base($credential) {
    }

    [void] EnsureTicketClosed([string] $jiraUrl) {
        $null = $this.ClosedTickets.Add($jiraUrl)
    }

    [string] CreatePrerequisiteTicket([PrefixWorkItem] $workItem, [string] $forestShortName, [bool] $dnsZoneDelegated) {
        return $this.CreatedTicketUrl
    }
}

class FakeNetBoxClient : NetBoxClient {
    [PrefixWorkItem[]] $PrefixItems = @()
    [IpAddressWorkItem[]] $IpItems = @()
    [System.Collections.Generic.List[int]] $MarkedPrefixes = [System.Collections.Generic.List[int]]::new()
    [System.Collections.Generic.List[string]] $UpdatedPrefixTickets = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $UpdatedIpStatuses = [System.Collections.Generic.List[string]]::new()

    FakeNetBoxClient([AutomationCredential] $credential) : base($credential) {
    }

    [PrefixWorkItem[]] GetOpenPrefixWorkItems([EnvironmentContext] $environment) {
        return $this.PrefixItems
    }

    [IpAddressWorkItem[]] GetIpWorkItems([EnvironmentContext] $environment, [string[]] $statuses) {
        return $this.IpItems
    }

    [void] UpdatePrefixTicketUrl([int] $prefixId, [string] $ticketUrl) {
        $null = $this.UpdatedPrefixTickets.Add(('{0}|{1}' -f $prefixId, $ticketUrl))
    }

    [void] MarkPrefixOnboardingDone([int] $prefixId) {
        $null = $this.MarkedPrefixes.Add($prefixId)
    }

    [void] UpdateIpStatus([int] $ipId, [string] $status) {
        $null = $this.UpdatedIpStatuses.Add(('{0}|{1}' -f $ipId, $status))
    }

    [void] AddJournalEntry([string] $targetType, [int] $targetId, [string] $message, [string] $kind) {
    }

    [string] GetPrefixUrl([int] $prefixId) {
        return 'https://netbox.example.test/ipam/prefixes/{0}/' -f $prefixId
    }

    [string] GetIpAddressUrl([int] $ipAddressId) {
        return 'https://netbox.example.test/ipam/ip-addresses/{0}/' -f $ipAddressId
    }
}

class FakeDhcpServerAdapter : DhcpServerAdapter {
    [string] $SelectedServer = 'm-dhcp02.de.mtu.corp'
    [System.Collections.Generic.List[string]] $EnsuredScopes = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $FailoverScopes = [System.Collections.Generic.List[string]]::new()

    [string] GetPrimaryServerForSite([string] $site, [bool] $isDevelopment) {
        return $this.SelectedServer
    }

    [void] EnsureScope([string] $dhcpServer, [DhcpScopeDefinition] $definition) {
        $null = $this.EnsuredScopes.Add(('{0}|{1}' -f $dhcpServer, $definition.Subnet.Cidr))
    }

    [void] EnsureScopeFailover([string] $dhcpServer, [IPv4Subnet] $subnet) {
        $null = $this.FailoverScopes.Add(('{0}|{1}' -f $dhcpServer, $subnet.Cidr))
    }
}

class FakeGatewayDnsService : GatewayDnsService {
    [bool] $ThrowOnPrefix
    [bool] $ThrowOnIp
    [System.Collections.Generic.List[string]] $PrefixCalls = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $IpEnsureCalls = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $IpRemoveCalls = [System.Collections.Generic.List[string]]::new()

    FakeGatewayDnsService([ActiveDirectoryAdapter] $activeDirectoryAdapter, [DnsServerAdapter] $dnsServerAdapter) : base($activeDirectoryAdapter, $dnsServerAdapter) {
    }

    [void] EnsurePrefixGatewayDns([PrefixWorkItem] $workItem) {
        if ($this.ThrowOnPrefix) {
            throw [System.InvalidOperationException]::new('Gateway DNS failed.')
        }

        $null = $this.PrefixCalls.Add($workItem.GetIdentifier())
    }

    [void] EnsureIpDns([IpAddressWorkItem] $workItem) {
        if ($this.ThrowOnIp) {
            throw [System.InvalidOperationException]::new('IP DNS failed.')
        }

        $null = $this.IpEnsureCalls.Add($workItem.GetIdentifier())
    }

    [void] RemoveIpDns([IpAddressWorkItem] $workItem) {
        if ($this.ThrowOnIp) {
            throw [System.InvalidOperationException]::new('IP DNS failed.')
        }

        $null = $this.IpRemoveCalls.Add($workItem.GetIdentifier())
    }
}

class FakeWorkItemJournalService : WorkItemJournalService {
    [System.Collections.Generic.List[string]] $PrefixInfoEntries = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $PrefixErrorEntries = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $IpInfoEntries = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $IpErrorEntries = [System.Collections.Generic.List[string]]::new()

    FakeWorkItemJournalService([NetBoxClient] $netBoxClient) : base($netBoxClient) {
    }

    [void] WritePrefixInfo([PrefixWorkItem] $workItem, [string[]] $lines) {
        $null = $this.PrefixInfoEntries.Add(('{0}|{1}' -f $workItem.GetIdentifier(), ($lines -join ';')))
    }

    [void] WritePrefixError([PrefixWorkItem] $workItem, [string[]] $lines) {
        $null = $this.PrefixErrorEntries.Add(('{0}|{1}' -f $workItem.GetIdentifier(), ($lines -join ';')))
    }

    [void] WriteIpInfo([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $null = $this.IpInfoEntries.Add(('{0}|{1}' -f $workItem.GetIdentifier(), ($lines -join ';')))
    }

    [void] WriteIpError([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $null = $this.IpErrorEntries.Add(('{0}|{1}' -f $workItem.GetIdentifier(), ($lines -join ';')))
    }
}

class FakeSmtpMailClient : SmtpMailClient {
    [System.Collections.Generic.List[string]] $Recipients = [System.Collections.Generic.List[string]]::new()
    [string] $LastSubject
    [string] $LastBody

    FakeSmtpMailClient([ActiveDirectoryAdapter] $activeDirectoryAdapter) : base($activeDirectoryAdapter) {
    }

    [void] SendHtmlMail([string[]] $recipients, [string] $subject, [string] $htmlBody) {
        foreach ($recipient in @($recipients)) {
            $null = $this.Recipients.Add($recipient)
        }

        $this.LastSubject = $subject
        $this.LastBody = $htmlBody
    }
}

class FakeThrowingPrefixErrorJournalService : FakeWorkItemJournalService {
    FakeThrowingPrefixErrorJournalService([NetBoxClient] $netBoxClient) : base($netBoxClient) {
    }

    [void] WritePrefixError([PrefixWorkItem] $workItem, [string[]] $lines) {
        throw [System.InvalidOperationException]::new('Journal write failed.')
    }
}

class FakeThrowingIpErrorJournalService : FakeWorkItemJournalService {
    FakeThrowingIpErrorJournalService([NetBoxClient] $netBoxClient) : base($netBoxClient) {
    }

    [void] WriteIpError([IpAddressWorkItem] $workItem, [string[]] $lines) {
        throw [System.InvalidOperationException]::new('Journal write failed.')
    }
}

class FakeThrowingSmtpMailClient : SmtpMailClient {
    FakeThrowingSmtpMailClient([ActiveDirectoryAdapter] $activeDirectoryAdapter) : base($activeDirectoryAdapter) {
    }

    [void] SendHtmlMail([string[]] $recipients, [string] $subject, [string] $htmlBody) {
        throw [System.InvalidOperationException]::new('SMTP unavailable.')
    }
}

class FakePrerequisiteValidationService : PrerequisiteValidationService {
    [PrerequisiteEvaluation] $EvaluationToReturn
    [int] $EvaluateCallCount

    FakePrerequisiteValidationService() : base($null, $null, $null) {
    }

    [PrerequisiteEvaluation] Evaluate([PrefixWorkItem] $workItem, [EnvironmentContext] $environment) {
        $this.EvaluateCallCount++
        return $this.EvaluationToReturn
    }
}

class RecordingPrefixOnboardingService : PrefixOnboardingService {
    [BatchRunSummary] $SummaryToReturn
    [int] $ProcessBatchCallCount

    RecordingPrefixOnboardingService() : base($null, $null, $null, $null, $null, $null, $null, $null, $null) {
    }

    [BatchRunSummary] ProcessBatch([EnvironmentContext] $environment) {
        $this.ProcessBatchCallCount++
        return $this.SummaryToReturn
    }
}

class RecordingIpDnsLifecycleService : IpDnsLifecycleService {
    [BatchRunSummary] $SummaryToReturn
    [int] $ProcessBatchCallCount

    RecordingIpDnsLifecycleService([string] $mode) : base($mode, $null, $null, $null, $null) {
    }

    [BatchRunSummary] ProcessBatch([EnvironmentContext] $environment) {
        $this.ProcessBatchCallCount++
        return $this.SummaryToReturn
    }
}
'@
            }
        }

        BeforeEach {
            $script:credential = [AutomationCredential]::new('Test', 'https://example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
            $script:environment = [EnvironmentContext]::new('prod')
            $script:activeDirectory = New-Object -TypeName FakeActiveDirectoryAdapter
            $script:dns = New-Object -TypeName FakeDnsServerAdapter
            $script:jira = New-Object -TypeName FakeJiraClient -ArgumentList $script:credential
            $script:netBox = New-Object -TypeName FakeNetBoxClient -ArgumentList $script:credential
            $script:dhcp = New-Object -TypeName FakeDhcpServerAdapter
            $script:gatewayDns = New-Object -TypeName FakeGatewayDnsService -ArgumentList $script:activeDirectory, $script:dns
            $script:journal = New-Object -TypeName FakeWorkItemJournalService -ArgumentList $script:netBox
            $script:logService = [WorkItemLogService]::new((Join-Path -Path $TestDrive -ChildPath 'logs'))
            $script:prerequisites = [PrerequisiteValidationService]::new($script:activeDirectory, $script:dns, $script:jira)
            $script:selector = [DhcpServerSelectionService]::new($script:dhcp)
        }

        It 'requests a new Jira ticket when no AD site exists' {
            $script:activeDirectory.SubnetSiteValue = $null
            $workItem = [PrefixWorkItem]::new(
                1, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                'MUC', 7, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed'
            )

            $result = $script:prerequisites.Evaluate($workItem, $script:environment)

            $result.CanContinue | Should -BeFalse
            $result.RequiresNewJiraTicket | Should -BeTrue
            $result.Reasons | Should -Contain 'Network is not assigned to any AD site.'
        }

        It 'continues when all prerequisites are satisfied and closes an existing ticket' {
            $script:activeDirectory.SubnetSiteValue = 'MUC'
            $script:dns.ReverseZoneName = '30.20.10.in-addr.arpa'
            $script:dns.HasDelegation = $true
            $workItem = [PrefixWorkItem]::new(
                1, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                'MUC', 7, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', 'https://jira.example.test/browse/TCO-9', 'routed'
            )

            $result = $script:prerequisites.Evaluate($workItem, $script:environment)

            $result.CanContinue | Should -BeTrue
            $script:jira.ClosedTickets | Should -Contain 'https://jira.example.test/browse/TCO-9'
        }

        It 'selects the configured DHCP server for production prefixes' {
            $script:selector.SelectServer($script:environment, 'MUC') | Should -Be 'm-dhcp02.de.mtu.corp'
        }

        It 'applies gateway DNS through the facade boundary for prefixes' {
            $workItem = [PrefixWorkItem]::new(
                7, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                'MUC', 7, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed'
            )

            $script:gatewayDns.EnsurePrefixGatewayDns($workItem)

            $script:gatewayDns.PrefixCalls | Should -Contain '10.20.30.0/24'
        }

        It 'applies and removes IP DNS through the shared DNS facade' {
            $workItem = [IpAddressWorkItem]::new(20, '10.20.30.10', 'onboarding_open_dns', 'host102030', 'de.mtu.corp', '10.20.30.0/24')

            $script:gatewayDns.EnsureIpDns($workItem)
            $script:gatewayDns.RemoveIpDns($workItem)

            $script:gatewayDns.IpEnsureCalls | Should -Contain '10.20.30.10'
            $script:gatewayDns.IpRemoveCalls | Should -Contain '10.20.30.10'
        }

        It 'sends grouped failure mail summaries through the notification service' {
            $mailClient = New-Object -TypeName FakeSmtpMailClient -ArgumentList $script:activeDirectory
            $notificationService = [BatchNotificationService]::new($mailClient, [OperationIssueMailFormatter]::new())
            $summary = [BatchRunSummary]::new('PrefixOnboarding')
            $summary.AddFailure(
                [OperationIssue]::new(
                    'Prefix',
                    '10.20.30.0/24',
                    'failed',
                    'details',
                    [IssueHandlingContext]::new('FIST', 'Alice'),
                    'https://netbox.example.test/ipam/prefixes/7/'
                )
            )
            $summary.Complete()

            $notificationService.SendFailureSummary(@('ops@example.test'), @($summary))

            $mailClient.Recipients | Should -Contain 'ops@example.test'
            $mailClient.LastSubject | Should -Be 'DHCPScopeAutomation'
            $mailClient.LastBody | Should -Match 'FIST'
            $mailClient.LastBody | Should -Match 'https://netbox.example.test/ipam/prefixes/7/'
        }

        It 'builds a runtime from relative configuration and credential files' {
            $currentLocation = Get-Location

            try {
                Set-Location -Path $TestDrive
                Set-Content -Path '.env' -Value @(
                    'Environment=prod'
                    'EmailRecipients=ops@example.test,net@example.test'
                )

                New-Item -Path '.secureCreds' -ItemType Directory | Out-Null
                [pscustomobject]@{
                    Appliance = 'https://netbox.example.test'
                    ApiKey    = (ConvertTo-SecureString -String 'netbox-secret' -AsPlainText -Force)
                } | Export-Clixml -Path '.secureCreds/DHCPScopeAutomationNetboxApiKey.xml'
                [pscustomobject]@{
                    Appliance = 'https://jira.example.test'
                    ApiKey    = (ConvertTo-SecureString -String 'jira-secret' -AsPlainText -Force)
                } | Export-Clixml -Path '.secureCreds/DHCPScopeAutomationJiraApiKey.xml'

                $factory = [AutomationRuntimeFactory]::new($null, $null, '.env', '.secureCreds')
                $runtime = $factory.CreateRuntime()

                $runtime.Environment.Name | Should -Be 'prod'
                $runtime.EmailRecipients | Should -Be @('ops@example.test', 'net@example.test')
                Test-Path -Path 'logs' | Should -BeTrue
            }
            finally {
                Set-Location -Path $currentLocation
            }
        }

        It 'creates a Jira ticket for blocked prefixes when prerequisites are missing' {
            $script:activeDirectory.SubnetSiteValue = $null
            $service = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $script:prerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [PrefixWorkItem]::new(
                11, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                'MUC', 7, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed'
            )

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))
            $summary.SuccessCount | Should -Be 1
            $summary.FailureCount | Should -Be 0
            $script:netBox.UpdatedPrefixTickets | Should -Contain '11|https://jira.example.test/browse/TCO-123'
            $script:journal.PrefixInfoEntries.Count | Should -Be 1
            $script:journal.PrefixInfoEntries[0] | Should -Match 'Created Jira ticket'
        }

        It 'completes no_dhcp prefixes without DHCP scope creation' {
            $script:activeDirectory.SubnetSiteValue = 'MUC'
            $script:dns.ReverseZoneName = '30.20.10.in-addr.arpa'
            $script:dns.HasDelegation = $true
            $service = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $script:prerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [PrefixWorkItem]::new(
                12, '10.20.31.0/24', 'Office', 'no_dhcp', 'de.mtu.corp',
                'MUC', 7, 102, '10.20.31.254', 'gw102031.de.mtu.corp', 'MUC', $null, 'routed'
            )

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))
            $summary.SuccessCount | Should -Be 1
            $summary.FailureCount | Should -Be 0
            $script:gatewayDns.PrefixCalls | Should -Contain '10.20.31.0/24'
            $script:netBox.MarkedPrefixes | Should -Contain 12
            $script:dhcp.EnsuredScopes.Count | Should -Be 0
        }

        It 'completes not_routed no_dhcp prefixes without gateway DNS or a default gateway' {
            $script:activeDirectory.SubnetSiteValue = 'MUC'
            $script:dns.ReverseZoneName = '38.20.10.in-addr.arpa'
            $script:dns.HasDelegation = $true
            $service = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $script:prerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [PrefixWorkItem]::new(
                121, '10.20.38.0/24', 'Transitless', 'no_dhcp', 'de.mtu.corp',
                'MUC', 7, 0, $null, $null, 'MUC', $null, 'not_routed'
            )

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))

            $summary.SuccessCount | Should -Be 1
            $summary.FailureCount | Should -Be 0
            $script:gatewayDns.PrefixCalls | Should -Not -Contain '10.20.38.0/24'
            $script:netBox.MarkedPrefixes | Should -Contain 121
            $script:dhcp.EnsuredScopes.Count | Should -Be 0
            $script:journal.PrefixInfoEntries[0] | Should -Match 'Gateway DNS skipped'
        }

        It 'completes DHCP backed prefixes through the provisioning workflow' {
            $script:activeDirectory.SubnetSiteValue = 'MUC'
            $script:dns.ReverseZoneName = '30.20.10.in-addr.arpa'
            $script:dns.HasDelegation = $true
            $service = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $script:prerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [PrefixWorkItem]::new(
                13, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                'MUC', 7, 103, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed'
            )

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))

            $summary.SuccessCount | Should -Be 1
            $summary.FailureCount | Should -Be 0
            $script:dhcp.EnsuredScopes | Should -Contain 'm-dhcp02.de.mtu.corp|10.20.30.0/24'
            $script:dhcp.FailoverScopes | Should -Contain 'm-dhcp02.de.mtu.corp|10.20.30.0/24'
            $script:netBox.MarkedPrefixes | Should -Contain 13
        }

        It 'captures prefix failures and degrades journal write errors into warnings' {
            $script:activeDirectory.SubnetSiteValue = 'MUC'
            $script:dns.ReverseZoneName = '30.20.10.in-addr.arpa'
            $script:dns.HasDelegation = $true
            $script:gatewayDns.ThrowOnPrefix = $true
            $throwingJournal = New-Object -TypeName FakeThrowingPrefixErrorJournalService -ArgumentList $script:netBox
            $service = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $script:prerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $throwingJournal,
                $script:logService
            )
            $workItem = [PrefixWorkItem]::new(
                14, '10.20.32.0/24', 'Office', 'no_dhcp', 'de.mtu.corp',
                'MUC', 7, 104, '10.20.32.254', 'gw102032.de.mtu.corp', 'MUC', $null, 'routed'
            )

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))

            $summary.SuccessCount | Should -Be 0
            $summary.FailureCount | Should -Be 1
            $summary.Issues[0].ResourceUrl | Should -Be 'https://netbox.example.test/ipam/prefixes/14/'
            $summary.AuditEntries.Where({ $_.Level -eq 'Warning' }).Count | Should -Be 1
        }

        It 'processes IP onboarding work items through the lifecycle service' {
            $service = [IpDnsLifecycleService]::new(
                'onboarding',
                $script:netBox,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [IpAddressWorkItem]::new(20, '10.20.30.10', 'onboarding_open_dns', 'host102030', 'de.mtu.corp', '10.20.30.0/24')

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))
            $summary.SuccessCount | Should -Be 1
            $summary.FailureCount | Should -Be 0
            $script:gatewayDns.IpEnsureCalls | Should -Contain '10.20.30.10'
            $script:netBox.UpdatedIpStatuses | Should -Contain '20|onboarding_done_dns'
        }

        It 'captures onboarding failures for IP work items with missing DNS names' {
            $service = [IpDnsLifecycleService]::new(
                'onboarding',
                $script:netBox,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [IpAddressWorkItem]::new(21, '10.20.30.11', 'onboarding_open_dns', $null, 'de.mtu.corp', '10.20.30.0/24')

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))

            $summary.SuccessCount | Should -Be 0
            $summary.FailureCount | Should -Be 1
            $summary.Issues[0].Message | Should -Match 'DNS name is missing'
            $summary.Issues[0].ResourceUrl | Should -Be 'https://netbox.example.test/ipam/ip-addresses/21/'
            $script:journal.IpErrorEntries.Count | Should -Be 1
        }

        It 'processes IP decommissioning work items through the shared lifecycle shell' {
            $service = [IpDnsLifecycleService]::new(
                'decommissioning',
                $script:netBox,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [IpAddressWorkItem]::new(22, '10.20.30.12', 'decommissioning_open_dns', 'host102031', 'de.mtu.corp', '10.20.30.0/24')

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))
            $summary.SuccessCount | Should -Be 1
            $summary.FailureCount | Should -Be 0
            $script:gatewayDns.IpRemoveCalls | Should -Contain '10.20.30.12'
            $script:netBox.UpdatedIpStatuses | Should -Contain '22|decommissioning_done_dns'
        }

        It 'downgrades IP journal write failures into warnings while keeping the original issue' {
            $script:gatewayDns.ThrowOnIp = $true
            $throwingJournal = New-Object -TypeName FakeThrowingIpErrorJournalService -ArgumentList $script:netBox
            $service = [IpDnsLifecycleService]::new(
                'decommissioning',
                $script:netBox,
                $script:gatewayDns,
                $throwingJournal,
                $script:logService
            )
            $workItem = [IpAddressWorkItem]::new(23, '10.20.30.13', 'decommissioning_open_dns', 'host102032', 'de.mtu.corp', '10.20.30.0/24')

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))

            $summary.SuccessCount | Should -Be 0
            $summary.FailureCount | Should -Be 1
            $summary.Issues[0].ResourceUrl | Should -Be 'https://netbox.example.test/ipam/ip-addresses/23/'
            $summary.AuditEntries.Where({ $_.Level -eq 'Warning' }).Count | Should -Be 1
        }

        It 'adds a failure notification summary when mail delivery fails' {
            $mailClient = New-Object -TypeName FakeThrowingSmtpMailClient -ArgumentList $script:activeDirectory
            $notificationService = [BatchNotificationService]::new($mailClient, [OperationIssueMailFormatter]::new())
            $prefixService = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $script:prerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $ipOnboardingService = [IpDnsLifecycleService]::new(
                'onboarding',
                $script:netBox,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $ipDecommissioningService = [IpDnsLifecycleService]::new(
                'decommissioning',
                $script:netBox,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $coordinator = [AutomationCoordinator]::new(
                $prefixService,
                $ipOnboardingService,
                $ipDecommissioningService,
                $notificationService
            )
            $script:gatewayDns.ThrowOnPrefix = $true
            $script:activeDirectory.SubnetSiteValue = 'MUC'
            $script:dns.ReverseZoneName = '30.20.10.in-addr.arpa'
            $script:dns.HasDelegation = $true
            $script:netBox.PrefixItems = @(
                [PrefixWorkItem]::new(
                    24, '10.20.33.0/24', 'Office', 'no_dhcp', 'de.mtu.corp',
                    'MUC', 7, 105, '10.20.33.254', 'gw102033.de.mtu.corp', 'MUC', $null, 'routed'
                )
            )

            $summaries = $coordinator.Run($script:environment, @('ops@example.test'), $true, $false, $true, $true)

            $summaries.Count | Should -Be 2
            $summaries[0].FailureCount | Should -Be 1
            $summaries[1].ProcessName | Should -Be 'FailureNotification'
            $summaries[1].FailureCount | Should -Be 1
            $summaries[1].Issues[0].Message | Should -Match 'Failed to send failure summary mail'
        }

        It 'loads prefix work items through ProcessBatch before executing the use case' {
            $script:activeDirectory.SubnetSiteValue = 'MUC'
            $script:dns.ReverseZoneName = '30.20.10.in-addr.arpa'
            $script:dns.HasDelegation = $true
            $script:netBox.PrefixItems = @(
                [PrefixWorkItem]::new(
                    31, '10.20.34.0/24', 'Office', 'no_dhcp', 'de.mtu.corp',
                    'MUC', 7, 106, '10.20.34.254', 'gw102034.de.mtu.corp', 'MUC', $null, 'routed'
                )
            )
            $service = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $script:prerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )

            $summary = $service.ProcessBatch($script:environment)

            $summary.SuccessCount | Should -Be 1
            $script:netBox.MarkedPrefixes | Should -Contain 31
        }

        It 'fails blocked prefixes with an existing Jira ticket instead of creating a new one' {
            $script:activeDirectory.SubnetSiteValue = $null
            $service = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $script:prerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [PrefixWorkItem]::new(
                32, '10.20.35.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                'MUC', 7, 107, '10.20.35.254', 'gw102035.de.mtu.corp', 'MUC', 'https://jira.example.test/browse/TCO-32', 'routed'
            )

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))

            $summary.SuccessCount | Should -Be 0
            $summary.FailureCount | Should -Be 1
            $summary.Issues[0].Message | Should -Match 'Network is not assigned to any AD site'
            $script:netBox.UpdatedPrefixTickets.Count | Should -Be 0
            $script:journal.PrefixErrorEntries.Count | Should -Be 1
        }

        It 'uses the default blocked-prefix message when validation returns no reasons' {
            $fakePrerequisites = New-Object -TypeName FakePrerequisiteValidationService
            $fakePrerequisites.EvaluationToReturn = [PrerequisiteEvaluation]::new()
            $service = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $fakePrerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [PrefixWorkItem]::new(
                33, '10.20.36.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                'MUC', 7, 108, '10.20.36.254', 'gw102036.de.mtu.corp', 'MUC', 'https://jira.example.test/browse/TCO-33', 'routed'
            )

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))

            $summary.FailureCount | Should -Be 1
            $summary.Issues[0].Message | Should -Match 'Prefix prerequisites are not satisfied'
            $fakePrerequisites.EvaluateCallCount | Should -Be 1
        }

        It 'fails DHCP-backed prefixes when the configured gateway mismatches the derived DHCP gateway' {
            $script:activeDirectory.SubnetSiteValue = 'MUC'
            $script:dns.ReverseZoneName = '30.20.10.in-addr.arpa'
            $script:dns.HasDelegation = $true
            $service = [PrefixOnboardingService]::new(
                $script:netBox,
                $script:activeDirectory,
                $script:jira,
                $script:prerequisites,
                $script:selector,
                $script:dhcp,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [PrefixWorkItem]::new(
                34, '10.20.37.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                'MUC', 7, 109, '10.20.37.1', 'gw102037.de.mtu.corp', 'MUC', $null, 'routed'
            )

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))

            $summary.SuccessCount | Should -Be 0
            $summary.FailureCount | Should -Be 1
            $summary.Issues[0].Message | Should -Match 'Gateway mismatch'
            $script:dhcp.EnsuredScopes.Count | Should -Be 0
        }

        It 'loads IP work items through ProcessBatch for DNS onboarding' {
            $script:netBox.IpItems = @(
                [IpAddressWorkItem]::new(41, '10.20.30.41', 'onboarding_open_dns', 'host102041', 'de.mtu.corp', '10.20.30.0/24')
            )
            $service = [IpDnsLifecycleService]::new(
                'onboarding',
                $script:netBox,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )

            $summary = $service.ProcessBatch($script:environment)

            $summary.SuccessCount | Should -Be 1
            $script:gatewayDns.IpEnsureCalls | Should -Contain '10.20.30.41'
        }

        It 'allows missing DNS names during IP decommissioning' {
            $service = [IpDnsLifecycleService]::new(
                'decommissioning',
                $script:netBox,
                $script:gatewayDns,
                $script:journal,
                $script:logService
            )
            $workItem = [IpAddressWorkItem]::new(42, '10.20.30.42', 'decommissioning_open_dns', $null, 'de.mtu.corp', '10.20.30.0/24')

            $summary = $service.ProcessWorkItems($script:environment, @($workItem))

            $summary.SuccessCount | Should -Be 1
            $summary.FailureCount | Should -Be 0
            $script:gatewayDns.IpRemoveCalls | Should -Contain '10.20.30.42'
        }

        It 'rejects unsupported IP lifecycle modes' {
            {
                [IpDnsLifecycleService]::new(
                    'unexpected',
                    $script:netBox,
                    $script:gatewayDns,
                    $script:journal,
                    $script:logService
                )
            } | Should -Throw
        }

        It 'runs only the enabled services when coordinator skip flags are used' {
            $prefixSummary = [BatchRunSummary]::new('PrefixOnboarding')
            $prefixSummary.Complete()
            $ipSummary = [BatchRunSummary]::new('IpDnsOnboarding')
            $ipSummary.Complete()
            $decomSummary = [BatchRunSummary]::new('IpDnsDecommissioning')
            $decomSummary.Complete()
            $prefixService = New-Object -TypeName RecordingPrefixOnboardingService
            $prefixService.SummaryToReturn = $prefixSummary
            $ipOnboardingService = New-Object -TypeName RecordingIpDnsLifecycleService -ArgumentList 'onboarding'
            $ipOnboardingService.SummaryToReturn = $ipSummary
            $ipDecommissioningService = New-Object -TypeName RecordingIpDnsLifecycleService -ArgumentList 'decommissioning'
            $ipDecommissioningService.SummaryToReturn = $decomSummary
            $notificationService = [BatchNotificationService]::new(
                (New-Object -TypeName FakeSmtpMailClient -ArgumentList $script:activeDirectory),
                [OperationIssueMailFormatter]::new()
            )
            $coordinator = [AutomationCoordinator]::new(
                $prefixService,
                $ipOnboardingService,
                $ipDecommissioningService,
                $notificationService
            )

            $summaries = $coordinator.Run($script:environment, @('ops@example.test'), $false, $true, $false, $true)

            $summaries.Count | Should -Be 1
            $summaries[0].ProcessName | Should -Be 'IpDnsOnboarding'
            $prefixService.ProcessBatchCallCount | Should -Be 0
            $ipOnboardingService.ProcessBatchCallCount | Should -Be 1
            $ipDecommissioningService.ProcessBatchCallCount | Should -Be 0
        }
    }
}
