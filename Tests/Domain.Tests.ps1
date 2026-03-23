Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'DHCPScopeAutomation.psd1') -Force

Describe 'Domain and supporting services' {
    InModuleScope DHCPScopeAutomation {
        Context 'OperationIssue and BatchRunSummary' {
            It 'rejects unsupported audit log levels' {
                { [OperationAuditEntry]::new('Trace', 'ignored') } | Should -Throw
            }

            It 'uses unassigned handling context by default' {
                $issue = [OperationIssue]::new('Prefix', '10.20.30.0/24', 'failed', 'details')

                $issue.GetHandlingDepartment() | Should -Be 'Unassigned'
                $issue.GetHandlingHandler() | Should -Be 'Unassigned'
                $issue.HasResourceUrl() | Should -BeFalse
            }

            It 'preserves assigned handling context and resource links' {
                $issue = [OperationIssue]::new(
                    'Prefix',
                    '10.20.30.0/24',
                    'failed',
                    'details',
                    [IssueHandlingContext]::new('FIST', 'Alice'),
                    'https://netbox.example.test/prefix/1'
                )

                $issue.GetHandlingDepartment() | Should -Be 'FIST'
                $issue.GetHandlingHandler() | Should -Be 'Alice'
                $issue.HasResourceUrl() | Should -BeTrue
            }

            It 'aggregates success, failure, and audit information' {
                $summary = [BatchRunSummary]::new('PrefixOnboarding')
                $issue = [OperationIssue]::new('Prefix', '10.20.30.0/24', 'failed', 'details')

                $summary.AddSuccess('ok')
                $summary.AddFailure($issue)
                $summary.Complete()

                $summary.SuccessCount | Should -Be 1
                $summary.FailureCount | Should -Be 1
                $summary.HasFailures() | Should -BeTrue
                $summary.AuditEntries.Count | Should -Be 2
                $summary.FinishedUtc | Should -Not -BeNullOrEmpty
            }

            It 'rejects null failures in the batch summary' {
                $summary = [BatchRunSummary]::new('PrefixOnboarding')

                { $summary.AddFailure($null) } | Should -Throw
            }
        }

        Context 'EnvironmentContext' {
            It 'maps production to the expected DNS zone' {
                $context = [EnvironmentContext]::new('prod')

                $context.DnsZone | Should -Be 'de.mtu.corp'
                $context.IsProduction() | Should -BeTrue
                $context.GetDelegationValidationDomain() | Should -Be 'de.mtu.corp'
            }

            It 'uses the production delegation zone for test' {
                $context = [EnvironmentContext]::new('test')

                $context.DnsZone | Should -Be 'test.mtu.corp'
                $context.GetDelegationValidationDomain() | Should -Be 'de.mtu.corp'
            }

            It 'rejects unsupported environments' {
                { [EnvironmentContext]::new('stage') } | Should -Throw
            }
        }

        Context 'IPv4Subnet' {
            It 'rejects non-ipv4 addresses' {
                { [IPv4Address]::new('2001:db8::1') } | Should -Throw
            }

            It 'normalizes a CIDR and computes derived values' {
                $subnet = [IPv4Subnet]::new('10.20.30.44/24')

                $subnet.Cidr | Should -Be '10.20.30.0/24'
                $subnet.GetSubnetMaskString() | Should -Be '255.255.255.0'
                $subnet.GetBroadcastAddress().Value | Should -Be '10.20.30.255'
                $subnet.GetReverseZoneName() | Should -Be '30.20.10.in-addr.arpa'
                $subnet.GetAddressAtOffset(10).Value | Should -Be '10.20.30.10'
                $subnet.Get24BlockBaseAddresses() | Should -Be @('10.20.30.0')
            }

            It 'returns AD lookup candidates from most to less specific' {
                $subnet = [IPv4Subnet]::new('10.20.30.0/23')

                $subnet.GetAdLookupCandidates() | Should -Be @(
                    '10.20.30.0/23',
                    '10.20.0.0/16',
                    '10.0.0.0/8'
                )
            }

            It 'rejects malformed CIDR strings' {
                { [IPv4Subnet]::new('10.20.30.0') } | Should -Throw
            }

            It 'rejects octet-free reverse zone derivation' {
                { [IPv4Subnet]::new('10.20.30.0/0').GetReverseZoneName() } | Should -Throw
            }
        }

        Context 'DHCP domain model' {
            It 'calculates the dynamic DHCP range for a /24 subnet' {
                $range = [DhcpRange]::FromSubnet([IPv4Subnet]::new('10.20.30.0/24'), 'dhcp_dynamic')

                $range.StartAddress.Value | Should -Be '10.20.30.1'
                $range.EndAddress.Value | Should -Be '10.20.30.248'
                $range.GatewayAddress.Value | Should -Be '10.20.30.254'
                $range.BroadcastAddress.Value | Should -Be '10.20.30.255'
                $range.ReservedAfterGateway | Should -Be 5
            }

            It 'creates strict exclusions for a /24 dynamic scope' {
                $workItem = [PrefixWorkItem]::new(
                    1, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                    'MUC', 7, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed'
                )
                $definition = [DhcpScopeDefinition]::FromPrefixWorkItem($workItem)

                $definition.ConfigureDynamicDns | Should -BeTrue
                $definition.ExclusionRanges.Count | Should -Be 3
                ($definition.ExclusionRanges | ForEach-Object MustSucceed | Select-Object -Unique) | Should -Be @($true)
            }

            It 'creates non-strict exclusions for a /23 dynamic scope' {
                $workItem = [PrefixWorkItem]::new(
                    1, '10.20.30.0/23', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                    'MUC', 7, 101, '10.20.31.254', 'gw102031.de.mtu.corp', 'MUC', $null, 'routed'
                )
                $definition = [DhcpScopeDefinition]::FromPrefixWorkItem($workItem)

                $definition.ExclusionRanges.Count | Should -Be 6
                ($definition.ExclusionRanges | ForEach-Object MustSucceed | Select-Object -Unique) | Should -Be @($false)
            }

            It 'creates a single strict exclusion for a static scope' {
                $workItem = [PrefixWorkItem]::new(
                    1, '10.20.30.0/24', 'Office', 'dhcp_static', 'de.mtu.corp',
                    'MUC', 7, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed'
                )
                $definition = [DhcpScopeDefinition]::FromPrefixWorkItem($workItem)

                $definition.ConfigureDynamicDns | Should -BeFalse
                $definition.ExclusionRanges.Count | Should -Be 1
                $definition.ExclusionRanges[0].MustSucceed | Should -BeTrue
            }

            It 'rejects exclusion ranges with inverted boundaries' {
                {
                    [DhcpExclusionRange]::new(
                        [IPv4Address]::new('10.20.30.10'),
                        [IPv4Address]::new('10.20.30.1')
                    )
                } | Should -Throw
            }

            It 'rejects unsupported DHCP types during scope creation' {
                $workItem = [PrefixWorkItem]::new(
                    1, '10.20.30.0/24', 'Office', 'dhcp_unknown', 'de.mtu.corp',
                    'MUC', 7, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed'
                )

                { [DhcpScopeDefinition]::FromPrefixWorkItem($workItem) } | Should -Throw
            }
        }

        Context 'Work item helpers' {
            It 'appends the domain to gateway dns names when needed' {
                $workItem = [PrefixWorkItem]::new(
                    1, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                    'MUC', 7, 101, '10.20.30.254', 'gw102030', 'MUC', $null, 'routed'
                )

                $workItem.GetGatewayFqdn() | Should -Be 'gw102030.de.mtu.corp'
                $workItem.GetIdentifier() | Should -Be '10.20.30.0/24'
            }

            It 'allows no_dhcp prefixes without a default gateway when routing_type is not_routed' {
                $workItem = [PrefixWorkItem]::new(
                    1, '10.20.38.0/24', 'Transitless', 'no_dhcp', 'de.mtu.corp',
                    'MUC', 7, 0, $null, $null, 'MUC', $null, 'not_routed'
                )

                $workItem.RequiresDefaultGateway() | Should -BeFalse
                $workItem.DefaultGatewayAddress | Should -BeNullOrEmpty
                $workItem.GetGatewayFqdn() | Should -BeNullOrEmpty
            }

            It 'returns fqdn branches for ip work items' {
                $workItemWithShortName = [IpAddressWorkItem]::new(1, '10.20.30.10', 'onboarding_open_dns', 'host102030', 'de.mtu.corp', '10.20.30.0/24')
                $workItemWithFqdn = [IpAddressWorkItem]::new(2, '10.20.30.11', 'onboarding_open_dns', 'host102031.de.mtu.corp', 'de.mtu.corp', '10.20.30.0/24')
                $workItemWithoutName = [IpAddressWorkItem]::new(3, '10.20.30.12', 'onboarding_open_dns', $null, 'de.mtu.corp', '10.20.30.0/24')

                $workItemWithShortName.GetFqdn() | Should -Be 'host102030.de.mtu.corp'
                $workItemWithFqdn.GetFqdn() | Should -Be 'host102031.de.mtu.corp'
                $workItemWithoutName.GetFqdn() | Should -BeNullOrEmpty
            }
        }

        Context 'Configuration and credential providers' {
            It 'reads values and arrays from the env file' {
                $path = Join-Path -Path $TestDrive -ChildPath '.env'
                Set-Content -Path $path -Value @(
                    '# comment'
                    'Environment=prod'
                    'EmailRecipients=ops@example.test, net@example.test'
                )

                $provider = [EnvFileConfigurationProvider]::new($path)

                $provider.GetValue('Environment', 'missing') | Should -Be 'prod'
                $provider.GetStringArray('EmailRecipients', 'missing') | Should -Be @('ops@example.test', 'net@example.test')
            }

            It 'fails when required env values are missing' {
                $path = Join-Path -Path $TestDrive -ChildPath '.env'
                Set-Content -Path $path -Value 'Environment=prod'

                $provider = [EnvFileConfigurationProvider]::new($path)

                { $provider.GetValue('EmailRecipients', 'missing') } | Should -Throw
            }

            It 'loads an existing persisted API credential' {
                $directory = Join-Path -Path $TestDrive -ChildPath 'creds'
                New-Item -Path $directory -ItemType Directory | Out-Null
                $credentialPath = Join-Path -Path $directory -ChildPath 'DHCPScopeAutomationNetboxApiKey.xml'
                [pscustomobject]@{
                    Appliance = 'https://netbox.example.test'
                    ApiKey    = (ConvertTo-SecureString -String 'super-secret' -AsPlainText -Force)
                } | Export-Clixml -Path $credentialPath

                $provider = [SecureFileCredentialProvider]::new($directory)
                $credential = $provider.GetApiCredential('DHCPScopeAutomationNetboxApiKey')

                $credential.Appliance | Should -Be 'https://netbox.example.test'
                $credential.GetPlainApiKey() | Should -Be 'super-secret'
            }

            It 'fails on malformed persisted credential files' {
                $directory = Join-Path -Path $TestDrive -ChildPath 'creds-invalid'
                New-Item -Path $directory -ItemType Directory | Out-Null
                $credentialPath = Join-Path -Path $directory -ChildPath 'BrokenCredential.xml'
                [pscustomobject]@{
                    Appliance = 'https://netbox.example.test'
                } | Export-Clixml -Path $credentialPath

                $provider = [SecureFileCredentialProvider]::new($directory)

                { $provider.GetApiCredential('BrokenCredential') } | Should -Throw
            }
        }

        Context 'Formatting and logging helpers' {
            It 'groups failure mails by department and renders deep links' {
                $formatter = [OperationIssueMailFormatter]::new()
                $issues = @(
                    [OperationIssue]::new('Prefix', '10.20.30.0/24', 'prefix failed', 'details', [IssueHandlingContext]::new('FIST', 'Alice'), 'https://netbox.example.test/prefix/1'),
                    [OperationIssue]::new('IPAddress', '10.20.30.10', 'ip failed', 'details', [IssueHandlingContext]::new('FIST', $null), $null),
                    [OperationIssue]::new('IPAddress', '10.20.30.11', 'other failed', 'details', [IssueHandlingContext]::new('Network', 'Bob'), $null)
                )

                $body = $formatter.BuildFailureSummaryBody($issues)

                $body | Should -Match 'FIST \(2\)'
                $body | Should -Match 'Network \(1\)'
                $body | Should -Match 'https://netbox.example.test/prefix/1'
                $body | Should -Match 'Handler: Alice'
            }

            It 'writes log files to the configured base path' {
                $basePath = Join-Path -Path $TestDrive -ChildPath 'logs'
                $service = [WorkItemLogService]::new($basePath)
                $logPath = $service.CreateLogPath('ip', '10.20.30.10')

                $service.WriteLog($logPath, @('line1', '', 'line2'))

                Test-Path -Path $logPath | Should -BeTrue
                (Get-Content -Path $logPath) | Should -Be @('line1', 'line2')
            }
        }
    }
}
