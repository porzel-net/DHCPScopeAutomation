function New-TestSecureString {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    return (ConvertTo-SecureString -String $Value -AsPlainText -Force)
}

function New-TestAutomationCredential {
    param(
        [string] $Name = 'TestCredential',
        [string] $Appliance = 'https://example.test',
        [string] $ApiKey = 'secret'
    )

    return [AutomationCredential]::new($Name, $Appliance, (New-TestSecureString -Value $ApiKey))
}

function New-TestPrefixWorkItem {
    param(
        [int] $Id = 1,
        [string] $Prefix = '10.20.30.0/24',
        [string] $Description = 'Office',
        [string] $DhcpType = 'dhcp_dynamic',
        [string] $Domain = 'de.mtu.corp',
        [string] $SiteName = 'MUC',
        [int] $SiteId = 7,
        [int] $DefaultGatewayId = 101,
        [string] $DefaultGatewayAddress = '10.20.30.254',
        [string] $DnsName = 'gw102030.de.mtu.corp',
        [string] $ValuemationSiteMandant = 'MUC',
        [string] $ExistingTicketUrl = $null
    )

    return [PrefixWorkItem]::new(
        $Id,
        $Prefix,
        $Description,
        $DhcpType,
        $Domain,
        $SiteName,
        $SiteId,
        $DefaultGatewayId,
        $DefaultGatewayAddress,
        $DnsName,
        $ValuemationSiteMandant,
        $ExistingTicketUrl
    )
}

function New-TestIpAddressWorkItem {
    param(
        [int] $Id = 1,
        [string] $IpAddress = '10.20.30.10',
        [string] $Status = 'onboarding_open_dns',
        [string] $DnsName = 'host102030',
        [string] $Domain = 'de.mtu.corp',
        [string] $Prefix = '10.20.30.0/24'
    )

    return [IpAddressWorkItem]::new(
        $Id,
        $IpAddress,
        $Status,
        $DnsName,
        $Domain,
        $Prefix
    )
}
