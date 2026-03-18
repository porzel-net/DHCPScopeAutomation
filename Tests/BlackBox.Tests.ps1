Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'DHCPScopeAutomation.psd1') -Force

Describe 'Public command blackbox behavior' {
    InModuleScope DHCPScopeAutomation {
        BeforeAll {
            if (-not ('FakeBlackBoxCoordinator' -as [type])) {
                Invoke-Expression @'
class FakeBlackBoxCoordinator : AutomationCoordinator {
    [BatchRunSummary[]] $SummariesToReturn = @()
    [bool] $LastSendFailureMail
    [bool] $LastSkipPrefixOnboarding
    [bool] $LastSkipIpDnsOnboarding
    [bool] $LastSkipIpDnsDecommissioning

    FakeBlackBoxCoordinator() : base($null, $null, $null, $null) {
    }

    [BatchRunSummary[]] Run(
        [EnvironmentContext] $environment,
        [string[]] $emailRecipients,
        [bool] $sendFailureMail,
        [bool] $skipPrefixOnboarding,
        [bool] $skipIpDnsOnboarding,
        [bool] $skipIpDnsDecommissioning
    ) {
        $this.LastSendFailureMail = $sendFailureMail
        $this.LastSkipPrefixOnboarding = $skipPrefixOnboarding
        $this.LastSkipIpDnsOnboarding = $skipIpDnsOnboarding
        $this.LastSkipIpDnsDecommissioning = $skipIpDnsDecommissioning
        return $this.SummariesToReturn
    }
}

class FakeBlackBoxRuntimeFactory : AutomationRuntimeFactoryBase {
    [AutomationRuntime] $RuntimeToReturn

    FakeBlackBoxRuntimeFactory([AutomationRuntime] $runtime) {
        $this.RuntimeToReturn = $runtime
    }

    [AutomationRuntime] CreateRuntime() {
        return $this.RuntimeToReturn
    }
}
'@
            }
        }

        It 'executes through an injected runtime factory and returns the public summary shape' {
            $coordinator = New-Object -TypeName FakeBlackBoxCoordinator
            $summary = [BatchRunSummary]::new('InjectedRun')
            $summary.AddSuccess('finished')
            $summary.Complete()
            $coordinator.SummariesToReturn = @($summary)

            $runtime = [AutomationRuntime]::new(
                [EnvironmentContext]::new('prod'),
                @('ops@example.test'),
                $coordinator,
                [WorkItemLogService]::new((Join-Path -Path $TestDrive -ChildPath 'logs'))
            )
            $factory = New-Object -TypeName FakeBlackBoxRuntimeFactory -ArgumentList $runtime

            $result = Start-DhcpScopeAutomation `
                -RuntimeFactory $factory `
                -SkipDependencyImport `
                -SkipFailureMail `
                -SkipPrefixOnboarding `
                -SkipIpDnsOnboarding

            $result.Count | Should -Be 1
            $result[0].ProcessName | Should -Be 'InjectedRun'
            $result[0].SuccessCount | Should -Be 1
            $coordinator.LastSendFailureMail | Should -BeFalse
            $coordinator.LastSkipPrefixOnboarding | Should -BeTrue
            $coordinator.LastSkipIpDnsOnboarding | Should -BeTrue
            $coordinator.LastSkipIpDnsDecommissioning | Should -BeFalse
        }

        It 'imports dependencies when the caller does not skip them' {
            $coordinator = New-Object -TypeName FakeBlackBoxCoordinator
            $summary = [BatchRunSummary]::new('InjectedRun')
            $summary.Complete()
            $coordinator.SummariesToReturn = @($summary)

            $runtime = [AutomationRuntime]::new(
                [EnvironmentContext]::new('prod'),
                @('ops@example.test'),
                $coordinator,
                [WorkItemLogService]::new((Join-Path -Path $TestDrive -ChildPath 'logs-import'))
            )
            $factory = New-Object -TypeName FakeBlackBoxRuntimeFactory -ArgumentList $runtime
            $script:dependencyImportCount = 0

            Mock Import-AutomationDependencies {
                $script:dependencyImportCount++
            }

            $null = Start-DhcpScopeAutomation -RuntimeFactory $factory -SkipFailureMail

            $script:dependencyImportCount | Should -Be 1
        }

        It 'converts issues and forwards audit entries during public execution' {
            $coordinator = New-Object -TypeName FakeBlackBoxCoordinator
            $summary = [BatchRunSummary]::new('InjectedRun')
            $summary.AddAudit('Information', 'hello audit')
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
            $coordinator.SummariesToReturn = @($summary)

            $runtime = [AutomationRuntime]::new(
                [EnvironmentContext]::new('prod'),
                @('ops@example.test'),
                $coordinator,
                [WorkItemLogService]::new((Join-Path -Path $TestDrive -ChildPath 'logs-issues'))
            )
            $factory = New-Object -TypeName FakeBlackBoxRuntimeFactory -ArgumentList $runtime
            $script:writtenAuditMessages = [System.Collections.Generic.List[string]]::new()

            Mock Write-AutomationLogEntry {
                param($Entry)
                $null = $script:writtenAuditMessages.Add($Entry.Message)
            }

            $result = Start-DhcpScopeAutomation -RuntimeFactory $factory -SkipDependencyImport -SkipFailureMail

            $result[0].FailureCount | Should -Be 1
            $result[0].Issues[0].HandlingDepartment | Should -Be 'FIST'
            $result[0].Issues[0].HandlingHandler | Should -Be 'Alice'
            $result[0].Issues[0].ResourceUrl | Should -Be 'https://netbox.example.test/ipam/prefixes/7/'
            $script:writtenAuditMessages | Should -Contain 'hello audit'
            $script:writtenAuditMessages | Should -Contain 'failed'
        }

        It 'exposes the runtime factory base as an explicit extension seam' {
            { [AutomationRuntimeFactoryBase]::new().CreateRuntime() } | Should -Throw
        }
    }
}
