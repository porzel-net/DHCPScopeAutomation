Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' | Join-Path -ChildPath 'DHCPScopeAutomation.psd1') -Force
. (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'ExternalCommandStubs.ps1')

Describe 'Infrastructure adapters and module internals' {
    InModuleScope DHCPScopeAutomation {
        AfterEach {
            $overriddenCommands = @(
                'Invoke-RestMethod'
                'Get-DnsServerZone'
                'Resolve-DnsName'
                'Get-DnsServerResourceRecord'
                'Remove-DnsServerResourceRecord'
                'Add-DnsServerResourceRecordA'
                'Add-DnsServerResourceRecordPtr'
                'Get-ADDomainController'
                'Get-DhcpServerInDC'
                'Invoke-Command'
                'Get-DhcpServerv4Scope'
                'Add-DhcpServerv4Scope'
                'Set-DhcpServerv4DnsSetting'
                'Set-DhcpServerv4OptionValue'
                'Add-DhcpServerv4ExclusionRange'
                'Get-DhcpServerv4Failover'
                'Add-DhcpServerv4FailoverScope'
            )

            foreach ($commandName in $overriddenCommands) {
                if (Test-Path -Path ("Function:\Global:{0}" -f $commandName)) {
                    Remove-Item -Path ("Function:\Global:{0}" -f $commandName) -Force
                }
            }
        }

        Context 'NetBoxClient' {
            It 'builds deep links for prefixes and IP addresses' {
                $credential = [AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
                $client = [NetBoxClient]::new($credential)

                $client.GetPrefixUrl(12) | Should -Be 'https://netbox.example.test/ipam/prefixes/12/'
                $client.GetIpAddressUrl(34) | Should -Be 'https://netbox.example.test/ipam/ip-addresses/34/'
            }

            It 'builds query strings from scalar and array filter values while skipping nulls' {
                $credential = [AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
                $client = [NetBoxClient]::new($credential)

                $query = $client.BuildQueryString([ordered]@{
                    status = @('onboarding_open_dns', 'decommissioning_open_dns')
                    limit  = 0
                    domain = $null
                })

                $query | Should -Match 'status=onboarding_open_dns'
                $query | Should -Match 'status=decommissioning_open_dns'
                $query | Should -Match 'limit=0'
                $query | Should -Not -Match 'domain='
            }

            It 'follows paged NetBox results until no next link remains' {
                $credential = [AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
                $client = [NetBoxClient]::new($credential)
                $script:pagedUris = [System.Collections.Generic.List[string]]::new()

                function Global:Invoke-RestMethod {
                    param($Uri)
                    $null = $script:pagedUris.Add($Uri)

                    if ($Uri -match 'page=2') {
                        return [pscustomobject]@{
                            results = @([pscustomobject]@{ id = 2 })
                            next    = $null
                        }
                    }

                    return [pscustomobject]@{
                        results = @([pscustomobject]@{ id = 1 })
                        next    = 'https://netbox.example.test/api/ipam/prefixes/?status=test&page=2'
                    }
                }

                $results = $client.GetPaged('/api/ipam/prefixes/', @{ status = 'test' })

                $results.Count | Should -Be 2
                $results[0].id | Should -Be 1
                $results[1].id | Should -Be 2
                $script:pagedUris[0] | Should -Be 'https://netbox.example.test/api/ipam/prefixes/?status=test'
                $script:pagedUris[1] | Should -Be 'https://netbox.example.test/api/ipam/prefixes/?status=test&page=2'
            }

            It 'maps open prefix responses into prefix work items' {
                $credential = [AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
                $client = [NetBoxClient]::new($credential)
                $environment = [EnvironmentContext]::new('prod')

                function Global:Invoke-RestMethod {
                    param($Uri)

                    if (
                        $Uri -match '/api/ipam/prefixes/\?' -and
                        $Uri -match 'status=onboarding_open_dns_dhcp' -and
                        $Uri -match 'cf_domain=de\.mtu\.corp'
                    ) {
                        return [pscustomobject]@{
                            results = @(
                                [pscustomobject]@{
                                    id            = 7
                                    prefix        = '10.20.30.0/24'
                                    description   = 'Office'
                                    custom_fields = [pscustomobject]@{
                                        dhcp_type                        = 'dhcp_dynamic'
                                        domain                           = 'de.mtu.corp'
                                        default_gateway                  = [pscustomobject]@{ id = 101 }
                                        routing_type                     = 'routed'
                                        ad_sites_and_services_ticket_url = 'https://jira.example.test/browse/TCO-7'
                                    }
                                    scope         = [pscustomobject]@{
                                        id   = 17
                                        name = 'MUC'
                                    }
                                }
                            )
                            next    = $null
                        }
                    }

                    if ($Uri -match '/api/ipam/ip-addresses/101/$') {
                        return [pscustomobject]@{
                            address  = '10.20.30.254/24'
                            dns_name = 'gw102030.de.mtu.corp'
                        }
                    }

                    if ($Uri -match '/api/dcim/sites/17/$') {
                        return [pscustomobject]@{
                            custom_fields = [pscustomobject]@{
                                valuemation_site_mandant = 'MUC'
                            }
                        }
                    }

                    throw "Unexpected URI: $Uri"
                }

                $items = $client.GetOpenPrefixWorkItems($environment)

                $items.Count | Should -Be 1
                $items[0].Id | Should -Be 7
                $items[0].PrefixSubnet.Cidr | Should -Be '10.20.30.0/24'
                $items[0].DefaultGatewayAddress.Value | Should -Be '10.20.30.254'
                $items[0].ValuemationSiteMandant | Should -Be 'MUC'
                $items[0].ExistingTicketUrl | Should -Be 'https://jira.example.test/browse/TCO-7'
                $items[0].RoutingType | Should -Be 'routed'
            }

            It 'maps not_routed no_dhcp prefixes without resolving a default gateway' {
                $credential = [AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
                $client = [NetBoxClient]::new($credential)
                $environment = [EnvironmentContext]::new('prod')

                function Global:Invoke-RestMethod {
                    param($Uri)

                    if (
                        $Uri -match '/api/ipam/prefixes/\?' -and
                        $Uri -match 'status=onboarding_open_dns_dhcp' -and
                        $Uri -match 'cf_domain=de\.mtu\.corp'
                    ) {
                        return [pscustomobject]@{
                            results = @(
                                [pscustomobject]@{
                                    id            = 8
                                    prefix        = '10.20.38.0/24'
                                    description   = 'Transitless'
                                    custom_fields = [pscustomobject]@{
                                        dhcp_type                        = 'no_dhcp'
                                        domain                           = 'de.mtu.corp'
                                        default_gateway                  = $null
                                        routing_type                     = 'not_routed'
                                        ad_sites_and_services_ticket_url = $null
                                    }
                                    scope         = [pscustomobject]@{
                                        id   = 17
                                        name = 'MUC'
                                    }
                                }
                            )
                            next    = $null
                        }
                    }

                    if ($Uri -match '/api/dcim/sites/17/$') {
                        return [pscustomobject]@{
                            custom_fields = [pscustomobject]@{
                                valuemation_site_mandant = 'MUC'
                            }
                        }
                    }

                    throw "Unexpected URI: $Uri"
                }

                $items = $client.GetOpenPrefixWorkItems($environment)

                $items.Count | Should -Be 1
                $items[0].RequiresDefaultGateway() | Should -BeFalse
                $items[0].DefaultGatewayId | Should -Be 0
                $items[0].DefaultGatewayAddress | Should -BeNullOrEmpty
                $items[0].RoutingType | Should -Be 'not_routed'
            }

            It 'prefers the most specific prefix match for an IP address lookup' {
                $credential = [AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
                $client = [NetBoxClient]::new($credential)

                function Global:Invoke-RestMethod {
                    return [pscustomobject]@{
                        results = @(
                            [pscustomobject]@{ prefix = '10.20.0.0/16'; custom_fields = [pscustomobject]@{ domain = 'de.mtu.corp' } },
                            [pscustomobject]@{ prefix = '10.20.30.0/24'; custom_fields = [pscustomobject]@{ domain = 'de.mtu.corp' } }
                        )
                        next    = $null
                    }
                }

                $prefix = $client.GetMostSpecificPrefixForAddress('10.20.30.10')

                $prefix.prefix | Should -Be '10.20.30.0/24'
            }

            It 'filters IP work items by prefix presence and environment domain' {
                $credential = [AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
                $client = [NetBoxClient]::new($credential)
                $environment = [EnvironmentContext]::new('prod')

                function Global:Invoke-RestMethod {
                    param($Uri)

                    if ($Uri -match '/api/ipam/ip-addresses/\?status=onboarding_open_dns&status=decommissioning_open_dns$') {
                        return [pscustomobject]@{
                            results = @(
                                [pscustomobject]@{ id = 1; address = '10.20.30.10/24'; status = [pscustomobject]@{ value = 'onboarding_open_dns' }; dns_name = 'host-a' },
                                [pscustomobject]@{ id = 2; address = '10.20.30.11/24'; status = [pscustomobject]@{ value = 'onboarding_open_dns' }; dns_name = 'host-b' },
                                [pscustomobject]@{ id = 3; address = '10.20.30.12/24'; status = [pscustomobject]@{ value = 'decommissioning_open_dns' }; dns_name = 'host-c' }
                            )
                            next    = $null
                        }
                    }

                    if ($Uri -match 'contains=10\.20\.30\.10') {
                        return [pscustomobject]@{
                            results = @([pscustomobject]@{ prefix = '10.20.30.0/24'; custom_fields = [pscustomobject]@{ domain = 'de.mtu.corp' } })
                            next    = $null
                        }
                    }

                    if ($Uri -match 'contains=10\.20\.30\.11') {
                        return [pscustomobject]@{
                            results = @([pscustomobject]@{ prefix = '10.20.30.0/24'; custom_fields = [pscustomobject]@{ domain = $null } })
                            next    = $null
                        }
                    }

                    if ($Uri -match 'contains=10\.20\.30\.12') {
                        return [pscustomobject]@{
                            results = @([pscustomobject]@{ prefix = '10.20.30.0/24'; custom_fields = [pscustomobject]@{ domain = 'us.mtu.corp' } })
                            next    = $null
                        }
                    }

                    throw "Unexpected URI: $Uri"
                }

                $items = $client.GetIpWorkItems($environment, @('onboarding_open_dns', 'decommissioning_open_dns'))

                $items.Count | Should -Be 1
                $items[0].Id | Should -Be 1
                $items[0].Domain | Should -Be 'de.mtu.corp'
            }

            It 'sends expected patch and journal payloads to NetBox' {
                $credential = [AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))
                $client = [NetBoxClient]::new($credential)
                $script:capturedRestCalls = [System.Collections.Generic.List[object]]::new()

                function Global:Invoke-RestMethod {
                    param($Uri, $Method, $Headers, $Body)
                    $null = $script:capturedRestCalls.Add([pscustomobject]@{
                        Uri    = $Uri
                        Method = [string] $Method
                        Body   = $Body
                    })
                }

                $client.UpdatePrefixTicketUrl(7, 'https://jira.example.test/browse/TCO-7')
                $client.MarkPrefixOnboardingDone(8)
                $client.UpdateIpStatus(9, 'onboarding_done_dns')
                $client.AddJournalEntry('IPAddress', 9, 'done', 'info')

                $script:capturedRestCalls.Count | Should -Be 4
                $script:capturedRestCalls[0].Uri | Should -Match '/api/ipam/prefixes/7/$'
                $script:capturedRestCalls[0].Method | Should -Be 'Patch'
                ($script:capturedRestCalls[0].Body | ConvertFrom-Json).custom_fields.ad_sites_and_services_ticket_url | Should -Be 'https://jira.example.test/browse/TCO-7'
                ($script:capturedRestCalls[1].Body | ConvertFrom-Json).status | Should -Be 'onboarding_done_dns_dhcp'
                ($script:capturedRestCalls[2].Body | ConvertFrom-Json).status | Should -Be 'onboarding_done_dns'
                ($script:capturedRestCalls[3].Body | ConvertFrom-Json).assigned_object_type | Should -Be 'ipam.ipaddress'
            }
        }

        Context 'DnsServerAdapter' {
            It 'prefers an exact reverse zone match before suffix matches' {
                $adapter = [DnsServerAdapter]::new()
                $subnet = [IPv4Subnet]::new('10.20.30.0/24')

                function Global:Get-DnsServerZone {
                    @(
                        [pscustomobject]@{ ZoneName = '20.10.in-addr.arpa'; IsReverseLookupZone = $true },
                        [pscustomobject]@{ ZoneName = '30.20.10.in-addr.arpa'; IsReverseLookupZone = $true }
                    )
                }

                $adapter.FindBestReverseZoneName($subnet, 'dc01.example.test') | Should -Be '30.20.10.in-addr.arpa'
            }

            It 'falls back to the longest matching reverse zone suffix' {
                $adapter = [DnsServerAdapter]::new()
                $subnet = [IPv4Subnet]::new('10.20.30.0/24')

                function Global:Get-DnsServerZone {
                    @(
                        [pscustomobject]@{ ZoneName = '10.in-addr.arpa'; IsReverseLookupZone = $true },
                        [pscustomobject]@{ ZoneName = '20.10.in-addr.arpa'; IsReverseLookupZone = $true }
                    )
                }

                $adapter.FindBestReverseZoneName($subnet, 'dc01.example.test') | Should -Be '20.10.in-addr.arpa'
            }

            It 'detects DNS delegation across broader prefix fallbacks' {
                $adapter = [DnsServerAdapter]::new()
                $subnet = [IPv4Subnet]::new('10.20.30.0/24')
                $script:resolvedNames = [System.Collections.Generic.List[string]]::new()

                function Global:Resolve-DnsName {
                    param($Name)
                    $null = $script:resolvedNames.Add($Name)

                    if ($Name -eq '20.10.in-addr.arpa') {
                        return @([pscustomobject]@{ NameHost = 'ns01.de.mtu.corp' })
                    }

                    return @()
                }

                $adapter.TestReverseZoneDelegation($subnet, 'de.mtu.corp') | Should -BeTrue
                $script:resolvedNames | Should -Contain '30.20.10.in-addr.arpa'
                $script:resolvedNames | Should -Contain '20.10.in-addr.arpa'
            }

            It 'returns false when delegation lookups fail or point outside the domain' {
                $adapter = [DnsServerAdapter]::new()
                $subnet = [IPv4Subnet]::new('10.20.30.0/24')

                function Global:Resolve-DnsName {
                    param($Name)

                    if ($Name -eq '30.20.10.in-addr.arpa') {
                        throw 'lookup failed'
                    }

                    return @([pscustomobject]@{ NameHost = 'ns01.other.example' })
                }

                $adapter.TestReverseZoneDelegation($subnet, 'de.mtu.corp') | Should -BeFalse
            }

            It 'removes matching A and PTR records for an IP address' {
                $adapter = [DnsServerAdapter]::new()
                $script:removedDnsRecords = [System.Collections.Generic.List[string]]::new()

                function Global:Get-DnsServerResourceRecord {
                    param($ZoneName, $RRType)

                    if ($RRType -eq 'A') {
                        return @(
                            [pscustomobject]@{
                                HostName   = 'host102030'
                                RecordData = [pscustomobject]@{
                                    IPv4Address = [pscustomobject]@{
                                        IPAddressToString = '10.20.30.10'
                                    }
                                }
                            }
                        )
                    }

                    return @(
                        [pscustomobject]@{
                            HostName   = '10'
                            RecordData = [pscustomobject]@{ PtrDomainName = 'host102030.de.mtu.corp' }
                        }
                    )
                }

                function Global:Remove-DnsServerResourceRecord {
                    param($ZoneName, $Name, $RRType, $RecordData, $InputObject)
                    if ($null -ne $InputObject) {
                        $null = $script:removedDnsRecords.Add(('PTR|{0}|{1}' -f $ZoneName, $InputObject.HostName))
                        return
                    }

                    $null = $script:removedDnsRecords.Add(('A|{0}|{1}|{2}' -f $ZoneName, $Name, $RecordData))
                }

                $adapter.RemoveDnsRecordsForIp('dc01', 'de.mtu.corp', '30.20.10.in-addr.arpa', [IPv4Address]::new('10.20.30.10'))

                $script:removedDnsRecords | Should -Contain 'A|de.mtu.corp|host102030|10.20.30.10'
                $script:removedDnsRecords | Should -Contain 'PTR|30.20.10.in-addr.arpa|10'
            }

            It 'adds missing A and PTR records after cleaning stale DNS entries' {
                $adapter = [DnsServerAdapter]::new()
                $script:dnsAdds = [System.Collections.Generic.List[string]]::new()

                function Global:Get-DnsServerResourceRecord { return $null }
                function Global:Remove-DnsServerResourceRecord {}
                function Global:Add-DnsServerResourceRecordA {
                    param($ZoneName, $Name, $IPv4Address)
                    $null = $script:dnsAdds.Add(('A|{0}|{1}|{2}' -f $ZoneName, $Name, $IPv4Address))
                }
                function Global:Add-DnsServerResourceRecordPtr {
                    param($ZoneName, $Name, $PtrDomainName)
                    $null = $script:dnsAdds.Add(('PTR|{0}|{1}|{2}' -f $ZoneName, $Name, $PtrDomainName))
                }

                $adapter.EnsureDnsRecordsForIp(
                    'dc01',
                    'de.mtu.corp',
                    'host102030.de.mtu.corp',
                    [IPv4Address]::new('10.20.30.10'),
                    '30.20.10.in-addr.arpa',
                    'host102030.de.mtu.corp'
                )

                $script:dnsAdds | Should -Contain 'A|de.mtu.corp|host102030|10.20.30.10'
                $script:dnsAdds | Should -Contain 'PTR|30.20.10.in-addr.arpa|10|host102030.de.mtu.corp'
            }

            It 'skips adding DNS records when matching records already exist' {
                $adapter = [DnsServerAdapter]::new()

                function Global:Remove-DnsServerResourceRecord {}
                function Global:Get-DnsServerResourceRecord {
                    param($ZoneName, $Name, $RRType)
                    return [pscustomobject]@{ HostName = $Name; ZoneName = $ZoneName; Type = $RRType }
                }
                $script:dnsAddCount = 0
                function Global:Add-DnsServerResourceRecordA { $script:dnsAddCount++ }
                function Global:Add-DnsServerResourceRecordPtr { $script:dnsAddCount++ }

                $adapter.EnsureDnsRecordsForIp(
                    'dc01',
                    'de.mtu.corp',
                    'host102030.de.mtu.corp',
                    [IPv4Address]::new('10.20.30.10'),
                    '30.20.10.in-addr.arpa',
                    'host102030.de.mtu.corp'
                )

                $script:dnsAddCount | Should -Be 0
            }
        }

        Context 'DhcpServerAdapter' {
            It 'maps site patterns and supports the development prefix' {
                $adapter = [DhcpServerAdapter]::new()

                $adapter.GetSitePattern('muc', $false) | Should -Be 'm*'
                $adapter.GetSitePattern('muc', $true) | Should -Be 'devm*'
                { $adapter.GetSitePattern('zzz', $false) } | Should -Throw
            }

            It 'prefers the primary DHCP server within the current domain' {
                $adapter = [DhcpServerAdapter]::new()

                function Global:Get-ADDomainController {
                    [pscustomobject]@{ Domain = 'de.mtu.corp' }
                }
                function Global:Get-DhcpServerInDC {
                    @(
                        [pscustomobject]@{ DnsName = 'm-dhcp01.de.mtu.corp' },
                        [pscustomobject]@{ DnsName = 'm-dhcp02.de.mtu.corp' },
                        [pscustomobject]@{ DnsName = 'm-dhcp03.other.example' }
                    )
                }
                function Global:Invoke-Command {
                    param($ComputerName)
                    return $ComputerName -eq 'm-dhcp02.de.mtu.corp'
                }

                $adapter.GetPrimaryServerForSite('muc', $false) | Should -Be 'm-dhcp02.de.mtu.corp'
            }

            It 'throws when no DHCP server matches the requested site and domain' {
                $adapter = [DhcpServerAdapter]::new()

                function Global:Get-ADDomainController {
                    [pscustomobject]@{ Domain = 'de.mtu.corp' }
                }
                function Global:Get-DhcpServerInDC {
                    @([pscustomobject]@{ DnsName = 'v-dhcp01.us.mtu.corp' })
                }
                function Global:Invoke-Command { return $false }

                { $adapter.GetPrimaryServerForSite('muc', $false) } | Should -Throw
            }

            It 'creates a DHCP scope with dynamic DNS and strict exclusions' {
                $adapter = [DhcpServerAdapter]::new()
                $definition = [DhcpScopeDefinition]::FromPrefixWorkItem(
                    [PrefixWorkItem]::new(
                        1, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                        'MUC', 7, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed'
                    )
                )
                $script:dhcpCalls = [System.Collections.Generic.List[string]]::new()

                function Global:Get-DhcpServerv4Scope { return $null }
                function Global:Add-DhcpServerv4Scope {
                    param($ComputerName, $Name, $StartRange, $EndRange, $SubnetMask)
                    $null = $script:dhcpCalls.Add(('ADD_SCOPE|{0}|{1}|{2}|{3}|{4}' -f $ComputerName, $Name, $StartRange, $EndRange, $SubnetMask))
                }
                function Global:Set-DhcpServerv4DnsSetting {
                    param($ComputerName, $ScopeId, $DynamicUpdates)
                    $null = $script:dhcpCalls.Add(('DNS|{0}|{1}|{2}' -f $ComputerName, $ScopeId, $DynamicUpdates))
                }
                function Global:Set-DhcpServerv4OptionValue {
                    param($ComputerName, $ScopeId, $DnsDomain, $Router, $OptionId, $Value)
                    $null = $script:dhcpCalls.Add(('OPTION|{0}|{1}|{2}|{3}|{4}|{5}' -f $ComputerName, $ScopeId, $DnsDomain, $Router, $OptionId, $Value))
                }
                function Global:Add-DhcpServerv4ExclusionRange {
                    param($ComputerName, $ScopeId, $StartRange, $EndRange, $ErrorAction)
                    $null = $script:dhcpCalls.Add(('EXCLUDE|{0}|{1}|{2}|{3}|{4}' -f $ComputerName, $ScopeId, $StartRange, $EndRange, $ErrorAction))
                }

                $adapter.EnsureScope('m-dhcp02.de.mtu.corp', $definition)

                $script:dhcpCalls | Should -Contain 'DNS|m-dhcp02.de.mtu.corp|10.20.30.0|OnClientRequest'
                ($script:dhcpCalls | Where-Object { $_ -like 'ADD_SCOPE*' }).Count | Should -Be 1
                ($script:dhcpCalls | Where-Object { $_ -like 'EXCLUDE*Stop' }).Count | Should -Be 3
            }

            It 'configures non-strict exclusions for larger dynamic ranges and skips scope creation when present' {
                $adapter = [DhcpServerAdapter]::new()
                $definition = [DhcpScopeDefinition]::FromPrefixWorkItem(
                    [PrefixWorkItem]::new(
                        1, '10.20.30.0/23', 'Office', 'dhcp_dynamic', 'de.mtu.corp',
                        'MUC', 7, 101, '10.20.31.254', 'gw102030.de.mtu.corp', 'MUC', $null, 'routed'
                    )
                )
                $script:exclusionModes = [System.Collections.Generic.List[string]]::new()

                $script:addScopeCount = 0
                function Global:Get-DhcpServerv4Scope { return [pscustomobject]@{ ScopeId = '10.20.30.0' } }
                function Global:Add-DhcpServerv4Scope { $script:addScopeCount++ }
                function Global:Set-DhcpServerv4DnsSetting {}
                function Global:Set-DhcpServerv4OptionValue {}
                function Global:Add-DhcpServerv4ExclusionRange {
                    param($ErrorAction)
                    $null = $script:exclusionModes.Add([string] $ErrorAction)
                }

                $adapter.EnsureScope('m-dhcp02.de.mtu.corp', $definition)

                $script:addScopeCount | Should -Be 0
                ($script:exclusionModes | Select-Object -Unique) | Should -Be @('SilentlyContinue')
            }

            It 'adds a failover scope only when a named failover relationship exists' {
                $adapter = [DhcpServerAdapter]::new()
                $script:failoverScopeCalls = 0
                function Global:Get-DhcpServerv4Failover {
                    @([pscustomobject]@{ Name = 'FO-MUC' })
                }
                function Global:Add-DhcpServerv4FailoverScope { $script:failoverScopeCalls++ }

                $adapter.EnsureScopeFailover('m-dhcp02.de.mtu.corp', [IPv4Subnet]::new('10.20.30.0/24'))

                $script:failoverScopeCalls | Should -Be 1
            }

            It 'returns quietly when DHCP failover lookup fails' {
                $adapter = [DhcpServerAdapter]::new()

                $script:failoverScopeCalls = 0
                function Global:Get-DhcpServerv4Failover { throw 'DHCP failover unavailable.' }
                function Global:Add-DhcpServerv4FailoverScope { $script:failoverScopeCalls++ }

                { $adapter.EnsureScopeFailover('m-dhcp02.de.mtu.corp', [IPv4Subnet]::new('10.20.30.0/24')) } | Should -Not -Throw
                $script:failoverScopeCalls | Should -Be 0
            }

            It 'keeps prefix decommissioning intentionally unimplemented' {
                $adapter = [DhcpServerAdapter]::new()

                { $adapter.RemoveScope('m-dhcp02.de.mtu.corp', [IPv4Subnet]::new('10.20.30.0/24')) } | Should -Throw
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
                $informationMessages = [System.Collections.Generic.List[string]]::new()
                $errorMessages = [System.Collections.Generic.List[string]]::new()
                $verboseMessages = [System.Collections.Generic.List[string]]::new()

                Mock Write-Debug { param($Message) $null = $debugMessages.Add($Message) }
                Mock Write-Warning { param($Message) $null = $warningMessages.Add($Message) }
                Mock Write-Information { param($MessageData) $null = $informationMessages.Add([string] $MessageData) }
                Mock Write-Error { param($Message) $null = $errorMessages.Add($Message) }
                Mock Write-Verbose { param($Message) $null = $verboseMessages.Add($Message) }

                Write-AutomationLogEntry -Entry ([OperationAuditEntry]::new('Debug', 'debugged'))
                Write-AutomationLogEntry -Entry ([OperationAuditEntry]::new('Information', 'informed'))
                Write-AutomationLogEntry -Entry ([OperationAuditEntry]::new('Warning', 'warned'))
                Write-AutomationLogEntry -Entry ([OperationAuditEntry]::new('Error', 'errored'))
                Write-AutomationLogEntry -Entry ([OperationAuditEntry]::new('Verbose', 'verbosed'))

                $debugMessages.Count | Should -Be 1
                $informationMessages.Count | Should -Be 1
                $warningMessages.Count | Should -Be 1
                $errorMessages.Count | Should -Be 1
                $verboseMessages.Count | Should -Be 1
                $warningMessages[0] | Should -Match 'warned'
            }

            It 'fails fast when a required infrastructure module cannot be imported' {
                Mock Import-Module {
                    param($Name)
                    if ($Name -eq 'DhcpServer') {
                        throw 'missing'
                    }
                }

                { Import-AutomationDependencies } | Should -Throw
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

            It 'writes multi-summary run logs with audit and failure counts' {
                $logService = [WorkItemLogService]::new((Join-Path -Path $TestDrive -ChildPath 'logs-detailed'))
                $coordinator = [AutomationCoordinator]::new($null, $null, $null, $null)
                $runtime = [AutomationRuntime]::new([EnvironmentContext]::new('prod'), @('ops@example.test'), $coordinator, $logService)
                $firstSummary = [BatchRunSummary]::new('PrefixOnboarding')
                $firstSummary.AddAudit('Information', 'prefix ok')
                $firstSummary.AddSuccess('done')
                $firstSummary.Complete()
                $secondSummary = [BatchRunSummary]::new('IpDnsOnboarding')
                $secondSummary.AddFailure([OperationIssue]::new('IPAddress', '10.20.30.10', 'failed', 'details'))
                $secondSummary.Complete()

                $path = Write-AutomationRunLog -Runtime $runtime -Summaries @($firstSummary, $secondSummary)
                $content = Get-Content -Path $path -Raw

                $content | Should -Match 'Process: PrefixOnboarding'
                $content | Should -Match 'Process: IpDnsOnboarding'
                $content | Should -Match 'FailureCount: 1'
                $content | Should -Match 'prefix ok'
            }
        }
    }
}
