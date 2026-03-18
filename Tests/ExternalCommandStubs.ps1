if (-not (Get-Command -Name 'Get-ADForest' -ErrorAction SilentlyContinue)) {
    function Global:Get-ADForest { throw 'Get-ADForest stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Get-ADReplicationSubnet' -ErrorAction SilentlyContinue)) {
    function Global:Get-ADReplicationSubnet { throw 'Get-ADReplicationSubnet stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Get-ADDomainController' -ErrorAction SilentlyContinue)) {
    function Global:Get-ADDomainController { throw 'Get-ADDomainController stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Get-ADDomain' -ErrorAction SilentlyContinue)) {
    function Global:Get-ADDomain { throw 'Get-ADDomain stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Get-DnsServerZone' -ErrorAction SilentlyContinue)) {
    function Global:Get-DnsServerZone { throw 'Get-DnsServerZone stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Resolve-DnsName' -ErrorAction SilentlyContinue)) {
    function Global:Resolve-DnsName { throw 'Resolve-DnsName stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Get-DnsServerResourceRecord' -ErrorAction SilentlyContinue)) {
    function Global:Get-DnsServerResourceRecord { throw 'Get-DnsServerResourceRecord stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Remove-DnsServerResourceRecord' -ErrorAction SilentlyContinue)) {
    function Global:Remove-DnsServerResourceRecord { throw 'Remove-DnsServerResourceRecord stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Add-DnsServerResourceRecordA' -ErrorAction SilentlyContinue)) {
    function Global:Add-DnsServerResourceRecordA { throw 'Add-DnsServerResourceRecordA stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Add-DnsServerResourceRecordPtr' -ErrorAction SilentlyContinue)) {
    function Global:Add-DnsServerResourceRecordPtr { throw 'Add-DnsServerResourceRecordPtr stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Get-DhcpServerInDC' -ErrorAction SilentlyContinue)) {
    function Global:Get-DhcpServerInDC { throw 'Get-DhcpServerInDC stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Get-DhcpServerv4Scope' -ErrorAction SilentlyContinue)) {
    function Global:Get-DhcpServerv4Scope { throw 'Get-DhcpServerv4Scope stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Add-DhcpServerv4Scope' -ErrorAction SilentlyContinue)) {
    function Global:Add-DhcpServerv4Scope { throw 'Add-DhcpServerv4Scope stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Set-DhcpServerv4DnsSetting' -ErrorAction SilentlyContinue)) {
    function Global:Set-DhcpServerv4DnsSetting { throw 'Set-DhcpServerv4DnsSetting stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Set-DhcpServerv4OptionValue' -ErrorAction SilentlyContinue)) {
    function Global:Set-DhcpServerv4OptionValue { throw 'Set-DhcpServerv4OptionValue stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Add-DhcpServerv4ExclusionRange' -ErrorAction SilentlyContinue)) {
    function Global:Add-DhcpServerv4ExclusionRange { throw 'Add-DhcpServerv4ExclusionRange stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Get-DhcpServerv4Failover' -ErrorAction SilentlyContinue)) {
    function Global:Get-DhcpServerv4Failover { throw 'Get-DhcpServerv4Failover stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Add-DhcpServerv4FailoverScope' -ErrorAction SilentlyContinue)) {
    function Global:Add-DhcpServerv4FailoverScope { throw 'Add-DhcpServerv4FailoverScope stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Invoke-Command' -ErrorAction SilentlyContinue)) {
    function Global:Invoke-Command { throw 'Invoke-Command stub should be mocked in tests.' }
}

if (-not (Get-Command -Name 'Send-MailMessage' -ErrorAction SilentlyContinue)) {
    function Global:Send-MailMessage { throw 'Send-MailMessage stub should be mocked in tests.' }
}
