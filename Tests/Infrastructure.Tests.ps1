Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'DHCPScopeAutomation.psd1') -Force

Describe 'Infrastructure adapters and module internals' {
    InModuleScope DHCPScopeAutomation {
        Context 'NetBoxClient' {
            It 'builds deep links for prefixes and IP addresses' {
                $credential = [AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
                $client = [NetBoxClient]::new($credential)

                $client.GetPrefixUrl(12) | Should -Be 'https://netbox.example.test/ipam/prefixes/12/'
                $client.GetIpAddressUrl(34) | Should -Be 'https://netbox.example.test/ipam/ip-addresses/34/'
            }
        }

        Context 'JiraClient' {
            It 'extracts a ticket key from a browse URL' {
                $client = [JiraClient]::new([AutomationCredential]::new('Jira', 'https://jira.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force)))

                $client.GetTicketKeyFromUrl('https://jira.example.test/browse/TCO-123') | Should -Be 'TCO-123'
            }
        }

        Context 'Private module functions' {
            It 'imports all required infrastructure modules' {
                $imports = [System.Collections.Generic.List[string]]::new()

                Mock Import-Module {
                    param($Name)
                    $null = $imports.Add($Name)
                }

                Import-AutomationDependencies

                $imports | Should -Be @('ActiveDirectory', 'DhcpServer', 'DnsServer')
            }

            It 'writes audit entries to the matching PowerShell stream' {
                $debugMessages = [System.Collections.Generic.List[string]]::new()
                $warningMessages = [System.Collections.Generic.List[string]]::new()

                Mock Write-Debug { param($Message) $null = $debugMessages.Add($Message) }
                Mock Write-Warning { param($Message) $null = $warningMessages.Add($Message) }

                Write-AutomationLogEntry -Entry ([OperationAuditEntry]::new('Debug', 'debugged'))
                Write-AutomationLogEntry -Entry ([OperationAuditEntry]::new('Warning', 'warned'))

                $debugMessages.Count | Should -Be 1
                $warningMessages.Count | Should -Be 1
                $warningMessages[0] | Should -Match 'warned'
            }

            It 'converts batch summaries to public PSCustomObject results' {
                $summary = [BatchRunSummary]::new('Example')
                $summary.AddFailure([OperationIssue]::new('Prefix', '10.20.30.0/24', 'failed', 'details', [IssueHandlingContext]::new('FIST', 'Alice'), 'https://netbox.example.test/prefix/1'))
                $summary.Complete()

                $publicObject = Convert-BatchRunSummaryToPublicObject -Summary $summary

                $publicObject.ProcessName | Should -Be 'Example'
                $publicObject.Issues[0].HandlingDepartment | Should -Be 'FIST'
                $publicObject.Issues[0].ResourceUrl | Should -Be 'https://netbox.example.test/prefix/1'
            }

            It 'writes a run summary log file' {
                $logService = [WorkItemLogService]::new((Join-Path -Path $TestDrive -ChildPath 'logs'))
                $coordinator = [AutomationCoordinator]::new($null, $null, $null, $null)
                $runtime = [AutomationRuntime]::new([EnvironmentContext]::new('prod'), @('ops@example.test'), $coordinator, $logService)
                $summary = [BatchRunSummary]::new('Example')
                $summary.AddSuccess('done')
                $summary.Complete()

                $path = Write-AutomationRunLog -Runtime $runtime -Summaries @($summary)

                Test-Path -Path $path | Should -BeTrue
                (Get-Content -Path $path -Raw) | Should -Match 'DHCPScopeAutomation run summary'
                (Get-Content -Path $path -Raw) | Should -Match 'Process: Example'
            }
        }
    }
}
