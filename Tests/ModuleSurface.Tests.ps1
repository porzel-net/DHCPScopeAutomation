Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\DHCPScopeAutomation.psd1') -Force

Describe 'DHCPScopeAutomation module surface' {
    It 'exports Start-DhcpScopeAutomation' {
        (Get-Command -Name 'Start-DhcpScopeAutomation' -ErrorAction Stop).Name | Should -Be 'Start-DhcpScopeAutomation'
    }

    It 'exposes the expected runtime control switches' {
        $command = Get-Command -Name 'Start-DhcpScopeAutomation' -ErrorAction Stop

        $command.Parameters.ContainsKey('SkipDependencyImport') | Should -BeTrue
        $command.Parameters.ContainsKey('SkipFailureMail') | Should -BeTrue
        $command.Parameters.ContainsKey('SkipPrefixOnboarding') | Should -BeTrue
        $command.Parameters.ContainsKey('SkipIpDnsOnboarding') | Should -BeTrue
        $command.Parameters.ContainsKey('SkipIpDnsDecommissioning') | Should -BeTrue
        $command.Parameters.ContainsKey('RuntimeFactory') | Should -BeTrue
    }
}
