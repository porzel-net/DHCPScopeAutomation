@{
    RootModule        = 'DHCPScopeAutomation.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '8d7b5613-9c9f-4a8d-b11f-4ab13cdc6d02'
    Author            = 'OpenAI Codex'
    CompanyName       = 'OpenAI'
    Copyright         = '(c) OpenAI. All rights reserved.'
    Description       = 'Clean-code rewrite of DHCP scope automation for Windows PowerShell 5.x.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Start-DhcpScopeAutomation')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('PowerShell', 'DHCP', 'DNS', 'NetBox', 'Jira')
        }
    }
}
