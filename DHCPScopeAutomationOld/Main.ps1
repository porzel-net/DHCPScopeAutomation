param(
    [string]$EmailRecipients,
    [string]$Environment
)

$startingProcessLogFilePath = ".\logs\StartingProcess_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $startingProcessLogFilePath -Append | Out-Null

Import-Module -Name "$PSScriptRoot\Utils.psm1" -ErrorAction Stop
Import-Module -Name "$PSScriptRoot\NetboxToolkit.psm1" -ErrorAction Stop
Import-Module -Name "$PSScriptRoot\JiraToolkit.psm1" -ErrorAction Stop
Import-Module -Name "$PSScriptRoot\SecureCredential.psm1" -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module DhcpServer -ErrorAction Stop

if(-not $EmailRecipients) {
    Write-Verbose "Parameter 'EmailRecipients' not provided. Loading from environment..."
    $EmailRecipients = (Get-EnvValue -KeyName "EmailRecipients" -Description "A comma seperated email list of recepients for all kinds of status alerts (e.g 'no-reply@mtu.de,no-reply@mtu.de')." -DataType "string")
} else {
    Write-Verbose "Using provided parameter 'EmailRecipients': $EmailRecipients"
}

[string[]]$EmailRecipients = ($EmailRecipients -split ",")

if(-not $Environment) {
    Write-Verbose "Parameter 'Environment' not provided. Loading from environment..."
    $Environment     =  Get-EnvValue -KeyName "Environment"     -Description "The enviroment of the script ('dev', 'test', 'prod')." -DataType "string"
} else {
    Write-Verbose "Using provided parameter 'Environment': $Environment"
}


$dev   = $Environment -eq "dev"
$test  = $Environment -eq "test"
$prod   = $Environment -eq "prod"
$gov   = $Environment -eq "gov"
$china = $Environment -eq "china"

if(-not ($dev -or $test -or $prod -or $gov -or $china)) {
    throw "No valid enviroment provided (provided = '$Environment')!"
}

$NetboxApiCredentials = Get-SecureCredential -CredentialName "DHCPScopeAutomationNetboxApiKey" -Appliance -ApiKey
$NetboxApiCredentials.ExpectAppliance()
$NetboxApiCredentials.ExpectApiKey()

$JiraApiCredentials = Get-SecureCredential -CredentialName "DHCPScopeAutomationJiraApiKey" -Appliance -ApiKey
$NetboxApiCredentials.ExpectAppliance()
$NetboxApiCredentials.ExpectApiKey()

$NetboxBaseUrl = $NetboxApiCredentials.GetAppliance()
$NetboxApiKey  = $NetboxApiCredentials.GetPlainApiKey()
$JiraBaseUrl   = $JiraApiCredentials.GetAppliance()
$JiraApiKey    = $JiraApiCredentials.GetPlainApiKey()

class DHCPServer {
    [string]$ServerName
    [bool]$Primary
}

$dhcpNetboxMapping = @{
    "dhcp_static"  = "STATIC"
    "dhcp_dynamic" = "DYNAMIC"
    "no_dhcp"      = "NODHCP"
}

<#
.SYNOPSIS
Retrieves the primary DHCP server for a specified AD site, optionally in a development environment.

.DESCRIPTION
This function identifies DHCP servers in Active Directory for a given site and determines which one is marked as primary by querying a registry key remotely. If no primary is found, it returns the first available DHCP server as a fallback.

.PARAMETER Site
The site code (e.g., "muc", "eme") used to filter DHCP servers.

.PARAMETER dev
Optional switch to indicate whether to search in the development environment.

.OUTPUTS
String - The DNS name of the primary DHCP server or a fallback server.

.EXAMPLE
Get-PrimaryDHCPServer -Site "muc"
#>
function Get-PrimaryDHCPServer(){
    param(
        [Parameter(Mandatory=$true)]
        [String]$Site,
        [bool]$dev = $false
    )

    $Site = $Site.ToLower()

    $DHCPServers=@()
    $EnvironmentLetter=$null
    $DNSNames=@()

    $sitePrefix = ""

    if($dev) {
        $sitePrefix = "dev"
    }

    switch($Site){
        "$($sitePrefix)eme"{
            $EnvironmentLetter="e*"
        }
        "$($sitePrefix)rze"{
            $EnvironmentLetter="r*"
        }
        "$($sitePrefix)haj"{
            $EnvironmentLetter="h*"
        }
        "$($sitePrefix)muc"{
            $EnvironmentLetter="m*"
        }
        "$($sitePrefix)mal"{
            $EnvironmentLetter="m*"
        }
        "$($sitePrefix)beg"{
            $EnvironmentLetter="o*"
        }
        "$($sitePrefix)yvr"{
            $EnvironmentLetter="v*"
        }
        "$($sitePrefix)lud"{
            $EnvironmentLetter="l*"
        }
    }

    if($dev) {
        $EnvironmentLetter = "dev" + $EnvironmentLetter
    }

    $DNSNames+=(Get-ADDomainController).Domain

    $DHCPServersinDC=@()

    [Object[]]$DHCPServers = Get-DhcpServerInDC | Where-Object{$_.DnsName -ilike $($EnvironmentLetter)} | Select-Object -ExpandProperty DnsName
    foreach($D in $DHCPServers){
        foreach($DNSName in $DNSNames){
            if($D -like $("*"+$DNSName)){
                $DHCPServersinDC+=$D
            }
        }
    }

    foreach($DHCPServer in $DHCPServersinDC){
        $DS = New-Object DHCPServer
        $DS.ServerName = $DhcpServer

        $RetVal=$null


        $RetVal = Invoke-Command -ComputerName $DHCPServer -ScriptBlock{
            try{
                $value = Get-ItemProperty HKLM:\SOFTWARE\ACW\DHCP -Name Primary -ErrorAction Stop
            }
            catch{
                $value = 0
            }

            return $value.Primary
        }

        $DS.Primary = $RetVal
        $DHCPServers += $DS
    }

    $PrimaryDHCPServer = $null
    $PrimaryDHCPServer = $DHCPServers | Where-Object{$_.Primary}

    if ($PrimaryDHCPServer) {
        Write-Host "    $($PrimaryDHCPServer.ServerName) has been identified as the primary DHCP server." -ForegroundColor Green
        return $PrimaryDHCPServer.ServerName
    } elseif ($DHCPServersinDC.Count -gt 0) {
        Write-Host "    $($DHCPServersinDC[0]) has been identified as a fallback DHCP server." -ForegroundColor Green
        return $DHCPServersinDC[0]
    } else {
        throw "No primary DHCP server could be identified, and no fallback server is available."
    }
}

<#
.SYNOPSIS
Converts a subnet in CIDR notation to its corresponding reverse DNS zone name.

.PARAMETER Subnet
The subnet in CIDR notation (e.g., 192.168.1.0/24).

.OUTPUTS
A string representing the reverse DNS zone name, or $null if the input is invalid.

.EXAMPLE
Convert-SubnetToReverseZone -Subnet "192.168.1.0/24"
# Returns: 1.168.192.in-addr.arpa
#>
function Convert-SubnetToReverseZone {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subnet
    )

    if (-not ($Subnet -match '^\d{1,3}(\.\d{1,3}){3}\/\d{1,2}$')) {
        Write-Error "Invalid subnet format. Use a format like '192.168.1.0/24'."
        return $null
    }

    $parts = $Subnet.Split('/')
    $ipString = $parts[0]
    $prefix = [int]$parts[1]

    $octets = $ipString.Split('.') | ForEach-Object {
        if ($_ -match '^\d+$' -and [int]$_ -ge 0 -and [int]$_ -le 255) {
            [int]$_
        }
        else {
            Write-Error "Invalid IP component: '$_'"
            return $null
        }
    }

    if ($octets -contains $null -or $octets.Count -ne 4) {
        Write-Error "Invalid IP address provided."
        return $null
    }

    $fullOctets = [math]::Floor($prefix / 8)
    if ($fullOctets -lt 1 -or $fullOctets -gt 4) {
        Write-Error "Unsupported prefix length for reverse zone conversion."
        return $null
    }

    $zoneName = switch ($fullOctets) {
        1 { "{0}.in-addr.arpa" -f $octets[0] }
        2 { "{0}.{1}.in-addr.arpa" -f $octets[1], $octets[0] }
        3 { "{0}.{1}.{2}.in-addr.arpa" -f $octets[2], $octets[1], $octets[0] }
        4 { "{0}.{1}.{2}.{3}.in-addr.arpa" -f $octets[3], $octets[2], $octets[1], $octets[0] }
    }

    return $zoneName
}

<#
.SYNOPSIS
Retrieves reverse DNS zone information for a given subnet from a specified DNS server.

.DESCRIPTION
This function validates a subnet in CIDR format, constructs the corresponding reverse DNS zone name, and queries the specified DNS server to find the best matching reverse lookup zone.

.PARAMETER Subnet
The subnet in CIDR notation (e.g., "10.24.0.0/24").

.PARAMETER DNSComputerName
The DNS server to query for reverse zone information.

.OUTPUTS
Microsoft.Management.Infrastructure.CimInstance - The matching reverse DNS zone object, or $false if none is found.

.EXAMPLE
Get-ReverseZoneInfo -Subnet "10.24.0.0/24" -DNSComputerName "dns01.example.com"
#>
function Get-ReverseZoneInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subnet,

        [Parameter(Mandatory = $true)]
        [string]$DNSComputerName
    )

    $zoneName = Convert-SubnetToReverseZone -Subnet $Subnet

    try {
        $reverseZones = Get-DnsServerZone -ComputerName $DNSComputerName -ErrorAction Stop | Where-Object { $_.IsReverseLookupZone -eq $true }
    }
    catch {
        Write-Error "Error querying DNS server $($DNSComputerName): $_"
        return $false
    }

    $matchedZone = $null

    foreach ($zone in $reverseZones) {
        if ($zoneName -ieq $zone.ZoneName) {
            $matchedZone = $zone
            break
        }

        $zoneLabels = $zone.ZoneName -split '\.'
        $zoneNameLabels = $zoneName -split '\.'

        if ($zoneNameLabels.Length -ge $zoneLabels.Length) {
            $endingLabels = $zoneNameLabels[-$zoneLabels.Length..-1]
            if ($endingLabels -join '.' -ieq $zone.ZoneName) {
                if (-not $matchedZone -or $zoneLabels.Length -gt ($matchedZone.ZoneName -split '\.').Length) {
                    $matchedZone = $zone
                }
            }
        }
    }


    if (-not $matchedZone) {
        return $false
    }

    return $matchedZone
}

<#
.SYNOPSIS
Checks whether a DNS delegation exists for a given subnet and matches a specified domain.

.DESCRIPTION
This function uses a subnet in CIDR notation (e.g., 192.168.1.0/24), converts it to the appropriate reverse DNS zone using Convert-SubnetToReverseZone, and queries for NS records. If any NS record ends with the specified domain, it returns $true.

.PARAMETER Subnet
The subnet in CIDR notation (e.g., 192.168.1.0/24) to check for reverse DNS delegation.

.PARAMETER Domain
The domain name to match against the NS records (e.g., "example.com").

.OUTPUTS
Boolean - Returns $true if a matching delegation exists, otherwise $false.

.EXAMPLE
Test-ReverseZoneDelegation -Subnet "53.150.79.0/24" -Domain "example.com"
#>
function Test-ReverseZoneDelegation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subnet,

        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $parts = $Subnet.Split('/')
    $ip = $parts[0]
    $prefix = [int]$parts[1]

    while ($prefix -ge 8) {
        $currentSubnet = "$ip/$prefix"
        $reverseZone = Convert-SubnetToReverseZone -Subnet $currentSubnet

        if (-not $reverseZone) {
            return $false
        }

        try {
            $nsResult = Resolve-DnsName -Name $reverseZone -Type NS -ErrorAction SilentlyContinue

            if ($nsResult) {
                foreach ($record in $nsResult) {
                    if ($record.NameHost -like "*.$Domain") {
                        return $true
                    }
                }
            }
        }
        catch {
            Write-Warning "Error resolving $($reverseZone): $_"
        }

        $prefix -= 8
    }

    return $false
}

<#
.SYNOPSIS
    Creates a DNS A record on a specified DNS server.

.DESCRIPTION
    This function adds an A record to a DNS zone on a specified DNS server using the provided DNS name and IP address.
    If any A record already exists for the given DNS name in the zone, it will only log the existing entry.
    If no A record exists for the name, it creates a new A record.

.PARAMETER DnsServer
    The DNS server where the A record should be created.

.PARAMETER DnsName
    The name of the A record to create.

.PARAMETER DnsZone
    The DNS zone in which the A record should be created.

.PARAMETER IpAddress
    The IPv4 address to associate with the A record.

.OUTPUTS
    String - Confirmation message upon successful creation of the A record.

.EXAMPLE
    Set-DnsARecord -DnsServer "dns01.example.com" -DnsName "host1" -DnsZone "example.com" -IpAddress "192.168.1.10"
#>
function Set-DnsARecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DnsServer,

        [Parameter(Mandatory = $true)]
        [string]$DnsName,

        [Parameter(Mandatory = $true)]
        [string]$DnsZone,

        [Parameter(Mandatory = $true)]
        [string]$IpAddress
    )

    try {
        if ($DnsName -like "*.$DnsZone") {
            $DnsName = $DnsName -replace "\.$DnsZone$", ""
        }

        Write-Host "    Adding DNS A-Record..."
        Write-Host "    Determined DNS A-Record data:"
        Write-Host "     - DNS Server: $DnsServer"
        Write-Host "     - DNS Name:   $DnsName"
        Write-Host "     - DNS Zone:   $DnsZone"
        Write-Host "     - IP Address: $IpAddress"

        $existingRecords = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $DnsZone -Name $DnsName -RRType "A" -ErrorAction SilentlyContinue

        if ($existingRecords -and $existingRecords.RecordData.IPv4Address) {
            Write-Host "    A record(s) already exist for '$DnsName' in zone '$DnsZone'. No changes will be applied." -ForegroundColor Yellow

            foreach ($rec in $existingRecords) {
                $existingIp = $rec.RecordData.IPv4Address.IPAddressToString
                Write-Host "        Existing A target: $existingIp"
            }

            return
        }

        Add-DnsServerResourceRecordA -Name $DnsName -ZoneName $DnsZone -IPv4Address $IpAddress -ComputerName $DnsServer -ErrorAction Stop
        Write-Host "    Successfully added A record." -ForegroundColor Green
    }
    catch {
        throw "Failed to add A record for '$DnsName': $_"
    }
}

<#
.SYNOPSIS
Removes a DNS A record from a specified DNS server.

.DESCRIPTION
This function deletes an A record from a DNS zone on a specified DNS server using the provided DNS name and IP address.

.PARAMETER DnsServer
The DNS server where the A record should be removed.

.PARAMETER DnsName
The name of the A record to remove.

.PARAMETER DnsZone
The DNS zone from which the A record should be removed.

.PARAMETER IpAddress
The IPv4 address associated with the A record to remove.

.OUTPUTS
String - Confirmation message upon successful removal of the A record.

.EXAMPLE
Remove-DnsARecord -DnsServer "dns01.example.com" -DnsName "host1" -DnsZone "example.com" -IpAddress "192.168.1.10"
#>
function Remove-DnsARecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DnsServer,

        [Parameter(Mandatory = $true)]
        [string]$DnsName,

        [Parameter(Mandatory = $true)]
        [string]$DnsZone,

        [Parameter(Mandatory = $true)]
        [string]$IpAddress
    )

    try {
        if ($DnsName -like "*.$DnsZone") {
            $DnsName = $DnsName -replace "\.$DnsZone$", ""
        }

        Write-Host "    Determined DNS A-Record data:"
        Write-Host "     - DNS Server: $DnsServer"
        Write-Host "     - DNS Name:   $DnsName"
        Write-Host "     - DNS Zone:   $DnsZone"
        Write-Host "     - IP Address: $IpAddress"

        $existingRecord = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $DnsZone -Name $DnsName -ErrorAction SilentlyContinue |
                Where-Object { $_.RecordType -eq "A" -and $_.RecordData.IPv4Address.IPAddressToString -eq $IpAddress }

        if ($existingRecord) {
            Remove-DnsServerResourceRecord -ZoneName $DnsZone -Name $DnsName -RRType "A" -RecordData $IpAddress -ComputerName $DnsServer -Force -ErrorAction Stop
            Write-Host "    Successfully removed A record for '$DnsName' with IP '$IpAddress' from zone '$DnsZone'."
        } else {
            Write-Host "    No matching A record found for '$DnsName' with IP '$IpAddress' in zone '$DnsZone'."
        }
    }
    catch {
        throw "Failed to remove A record for '$DnsName': $_"
    }
}

<#
.SYNOPSIS
Removes all DNS A records that point to a given IPv4 address within a specified zone.

.DESCRIPTION
This function discovers all A records in the given zone that point to the provided IP address.
For each discovered record, it calls Remove-DnsARecord (pure remove function) to delete it.

.PARAMETER DnsServer
The DNS server where the A records should be removed.

.PARAMETER DnsZone
The forward lookup zone to search in.

.PARAMETER IpAddress
The IPv4 address to match. CIDR notation (e.g., /32) is supported and will be normalized.

.EXAMPLE
Remove-AllCorrespondingDnsARecord -DnsServer "DEVMDC012" -DnsZone "de.mtudev.corp" -IpAddress "10.24.0.223/32"
#>
function Remove-AllCorrespondingDnsARecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DnsServer,

        [Parameter(Mandatory = $true)]
        [string]$DnsZone,

        [Parameter(Mandatory = $true)]
        [string]$IpAddress
    )

    try {
        $ipAddressString = ([string]$IpAddress).Split('/')[0].Trim()

        # --- Discover ALL A records in the zone that point to the IP ---
        $matchingARecords = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $DnsZone -RRType "A" -ErrorAction SilentlyContinue |
                Where-Object { $_.RecordData.IPv4Address.IPAddressToString -eq $ipAddressString }

        if (-not $matchingARecords) {
            Write-Host "    No A records in zone '$DnsZone' pointing to '$ipAddressString' were found."
            return
        }

        Write-Host "    Removing all A record(s) in zone '$DnsZone' that point to '$ipAddressString'..." -ForegroundColor Yellow
        foreach ($rec in $matchingARecords) {
            # HostName is the record name relative to the zone
            $dnsName = $rec.HostName
            if ([string]::IsNullOrWhiteSpace($dnsName)) { $dnsName = "@" }

            # --- Call the pure remove function ---
            Remove-DnsARecord -DnsServer $DnsServer -DnsName $dnsName -DnsZone $DnsZone -IpAddress $ipAddressString
        }

        Write-Host "    Successfully processed all matching A record(s) for IP '$ipAddressString' in zone '$DnsZone'." -ForegroundColor Green
    }
    catch {
        throw "Failed to remove all corresponding A records for IP '$IpAddress' from zone '$DnsZone': $_"
    }
}


<#
.SYNOPSIS
    Adds a DNS PTR record to a specified reverse lookup zone on a DNS server.

.DESCRIPTION
    This function checks whether a PTR record already exists for a given owner name in the specified reverse zone.
    If a PTR record already exists, it will only log the existing entry.
    If the record does not exist, it creates a new PTR record pointing to the provided domain name.

.PARAMETER DnsServer
    The DNS server where the PTR record should be added.

.PARAMETER ReverseZone
    The reverse lookup zone (e.g., '1.168.192.in-addr.arpa') where the PTR record will be created.

.PARAMETER Name
    The name portion of the IP address (e.g., '10' for 192.168.1.10) used in the reverse zone.
    If a full IPv4 address is provided, the relative owner name will be derived based on the reverse zone depth (/24, /16, /8).

.PARAMETER PtrDomainName
    The fully qualified domain name (FQDN) that the PTR record should point to.

.NOTES
    Ensure that the PtrDomainName is a complete FQDN (e.g., 'host.test.mtu.corp').

.EXAMPLE
    Set-DnsPtrRecord -DnsServer "dns01.test.mtu.corp" -ReverseZone "1.168.192.in-addr.arpa" -Name "10" -PtrDomainName "host.test.mtu.corp"
#>
function Set-DnsPtrRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DnsServer,

        [Parameter(Mandatory = $true)]
        [string]$ReverseZone,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$PtrDomainName
    )

    # --- Normalize -Name if it is a full IPv4; compute relative owner for the reverse zone depth ---
    $normalizedName = $Name
    if ($Name -match '^\d{1,3}(\.\d{1,3}){3}$') {
        $oct = $Name.Split('.')

        # Remove the trailing "in-addr.arpa" and count labels to detect depth (3=/24, 2=/16, 1=/8)
        $zonePart = ($ReverseZone.TrimEnd('.').ToLower() -replace '\.?in-addr\.arpa$', '').Trim('.')
        $labels = @()
        if (-not [string]::IsNullOrWhiteSpace($zonePart)) { $labels = $zonePart.Split('.') | Where-Object { $_ } }
        $depth = $labels.Count

        switch ($depth) {
            3 { $normalizedName = $oct[3] }                                 # /24  -> "last"
            2 { $normalizedName = "$($oct[3]).$($oct[2])" }                  # /16  -> "last.second-last"
            1 { $normalizedName = "$($oct[3]).$($oct[2]).$($oct[1])" }       # /8   -> "last.second-last.third-last"
            default { throw "Unsupported reverse zone format '$ReverseZone' for IPv4 PTR owner computation." }
        }
    }

    Write-Host "    Adding DNS PTR-Record..."
    Write-Host "    Determined DNS PTR Record data:"
    Write-Host "     - DNS Server:    $DnsServer"
    Write-Host "     - Reverse Zone:  $ReverseZone"
    Write-Host "     - Name:          $Name"
    Write-Host "     - Name (owner):  $normalizedName"
    Write-Host "     - PtrDomainName: $PtrDomainName"

    try {
        $existing = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $ReverseZone -Name $normalizedName -RRType PTR -ErrorAction SilentlyContinue

        if ($existing) {
            $currentTargets = @()
            foreach ($rec in $existing) {
                $t = $rec.RecordData.PtrDomainName
                if ($t) { $currentTargets += $t.TrimEnd('.') }
            }

            Write-Host "    PTR record(s) already exist for '$normalizedName.$ReverseZone'. No changes will be applied." -ForegroundColor Yellow
            if ($currentTargets.Count -gt 0) {
                foreach ($target in $currentTargets) {
                    Write-Host "        Existing PTR target: $target"
                }
            }
            return
        }

        Add-DnsServerResourceRecordPtr -ComputerName $DnsServer -ZoneName $ReverseZone -Name $normalizedName -PtrDomainName $PtrDomainName -ErrorAction Stop
        Write-Host "    Successfully added PTR record." -ForegroundColor Green
    }
    catch {
        throw "Failed to set PTR record for owner '$normalizedName' in zone '$ReverseZone': $_"
    }
}

<#
.SYNOPSIS
Removes DNS PTR record(s) from a reverse lookup zone on a DNS server.

.DESCRIPTION
This function deletes PTR record(s) from a reverse lookup zone on a specified DNS server.
If -Name is a full IPv4 address, the function derives the relative PTR owner name based on the reverse zone depth (/24, /16, /8).
If -PtrDomainName is provided, only PTR records matching that target are removed; otherwise all PTR records for the owner are removed.

.PARAMETER DnsServer
The DNS server where the PTR record(s) should be removed.

.PARAMETER ReverseZone
The reverse lookup zone (e.g., '0.24.10.in-addr.arpa') from which PTR record(s) will be removed.

.PARAMETER Name
The PTR owner name in the reverse zone (e.g., '223'), or a full IPv4 address (e.g., '10.24.0.223').

.PARAMETER PtrDomainName
Optional. If specified, only PTR records pointing to this FQDN are removed.

.EXAMPLE
Remove-DnsPtrRecord -DnsServer "DEVMDC012" -ReverseZone "0.24.10.in-addr.arpa" -Name "10.24.0.223"
#>
function Remove-DnsPtrRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DnsServer,

        [Parameter(Mandatory = $true)]
        [string]$ReverseZone,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$PtrDomainName
    )

    # --- Normalize -Name if it is a full IPv4; compute relative owner for the reverse zone depth ---
    $normalizedName = $Name
    if ($Name -match '^\d{1,3}(\.\d{1,3}){3}$') {
        $oct = $Name.Split('.')

        # Remove the trailing "in-addr.arpa" and count labels to detect depth (3=/24, 2=/16, 1=/8)
        $zonePart = ($ReverseZone.TrimEnd('.').ToLower() -replace '\.?in-addr\.arpa$', '').Trim('.')
        $labels   = @()
        if (-not [string]::IsNullOrWhiteSpace($zonePart)) { $labels = $zonePart.Split('.') | Where-Object { $_ } }
        $depth = $labels.Count

        switch ($depth) {
            3 { $normalizedName = $oct[3] }                                 # /24  -> "last"
            2 { $normalizedName = "$($oct[3]).$($oct[2])" }                  # /16  -> "last.second-last"
            1 { $normalizedName = "$($oct[3]).$($oct[2]).$($oct[1])" }       # /8   -> "last.second-last.third-last"
            default { throw "Unsupported reverse zone format '$ReverseZone' for IPv4 PTR owner computation." }
        }
    }

    Write-Host "    Determined DNS PTR Record data:"
    Write-Host "     - DNS Server:    $DnsServer"
    Write-Host "     - Reverse Zone:  $ReverseZone"
    Write-Host "     - Name:          $Name"
    Write-Host "     - Name (owner):  $normalizedName"
    if ($PtrDomainName) { Write-Host "     - PtrDomainName: $PtrDomainName" }

    try {
        # --- Robust query: enumerate PTR records and filter by HostName (more reliable than -Name in some setups) ---
        $existing = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $ReverseZone -RRType PTR -ErrorAction SilentlyContinue |
                Where-Object { $_.HostName -eq $normalizedName }

        if (-not $existing) {
            Write-Host "    No matching PTR record found for owner '$normalizedName' in zone '$ReverseZone'."
            return
        }

        if ($PtrDomainName) {
            $targetWanted = $PtrDomainName.TrimEnd('.').ToLower()
            $existing = $existing | Where-Object {
                $_.RecordData.PtrDomainName -and $_.RecordData.PtrDomainName.TrimEnd('.').ToLower() -eq $targetWanted
            }

            if (-not $existing) {
                Write-Host "    No matching PTR record found for owner '$normalizedName' pointing to '$PtrDomainName' in zone '$ReverseZone'."
                return
            }
        }

        Write-Host "    Removing PTR record(s) for '$normalizedName.$ReverseZone'..." -ForegroundColor Yellow
        foreach ($ptrRecord in $existing) {
            $currentTarget = $ptrRecord.RecordData.PtrDomainName
            if ($currentTarget) { $currentTarget = $currentTarget.TrimEnd('.') }

            Remove-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $ReverseZone -InputObject $ptrRecord -Force -ErrorAction Stop

            if ($currentTarget) {
                Write-Host "        Removed DNS PTR record '$normalizedName.$ReverseZone' -> '$currentTarget'."
            }
            else {
                Write-Host "        Removed DNS PTR record '$normalizedName.$ReverseZone'."
            }
        }

        Write-Host "    Successfully removed PTR record(s) for owner '$normalizedName' from zone '$ReverseZone'." -ForegroundColor Green
    }
    catch {
        throw "Failed to remove PTR record(s) for owner '$normalizedName' in zone '$ReverseZone': $_"
    }
}

<#
.SYNOPSIS
Removes all DNS PTR record(s) corresponding to a given IPv4 address within a specified reverse lookup zone.

.DESCRIPTION
This function removes PTR record(s) corresponding to the provided IPv4 address.
It calls Remove-DnsPtrRecord (pure remove function) and passes the IPv4 so the owner can be derived.

.PARAMETER DnsServer
The DNS server where the PTR record(s) should be removed.

.PARAMETER ReverseZone
The reverse lookup zone (e.g., '0.24.10.in-addr.arpa').

.PARAMETER IpAddress
The IPv4 address to match. CIDR notation is supported and will be normalized.

.EXAMPLE
Remove-AllCorrespondingDnsPtrRecord -DnsServer "DEVMDC012" -ReverseZone "0.24.10.in-addr.arpa" -IpAddress "10.24.0.223/32"
#>
function Remove-AllCorrespondingDnsPtrRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DnsServer,

        [Parameter(Mandatory = $true)]
        [string]$ReverseZone,

        [Parameter(Mandatory = $true)]
        [string]$IpAddress
    )

    try {
        $ipAddressString = ([string]$IpAddress).Split('/')[0].Trim()


        Write-Host "    Removing all PTR record(s) in reverse zone '$ReverseZone' that point to '$IpAddress'..." -ForegroundColor Yellow
        Remove-DnsPtrRecord -DnsServer $DnsServer -ReverseZone $ReverseZone -Name $ipAddressString
    }
    catch {
        throw "Failed to remove all corresponding PTR record(s) for IP '$IpAddress' from zone '$ReverseZone': $_"
    }
}

<#
.SYNOPSIS
Adds a DHCPv4 scope to an existing failover relationship.

.DESCRIPTION
    This function checks if a DHCP failover relationship exists on the specified server.
    If a relationship is found, it adds the given scope to the failover configuration.
    If no relationship exists, the function exits silently.

.PARAMETER DHCPServer
    The name of the DHCP server where the scope is configured.

.PARAMETER NetworkID
    The IPv4 network ID of the scope to be added to the failover relationship (e.g. "192.168.10.0").

.EXAMPLE
    Configure-FailoverForScope -DHCPServer "dhcp01.muc.domain.local" -NetworkID "192.168.10.0"
#>
function Configure-FailoverForScope {
    param (
        [string]$DHCPServer,
        [string]$NetworkID
    )

    try {
        $failOverName = (Get-DhcpServerv4Failover -ComputerName $DHCPServer).Name

        if (-not [string]::IsNullOrEmpty($failOverName)) {
            Add-DhcpServerv4FailoverScope -ScopeId $NetworkID -ComputerName $DHCPServer -Name $failOverName -ErrorAction Stop
            Write-Host "    Failover (=$failOverName) configured for Scope." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "    Failover not configured for Scope. Exception: $($_)" -ForegroundColor Red
        return
    }
}

<#
.SYNOPSIS
    Creates A and PTR DNS record for a given IP in a network.

.DESCRIPTION
    This function registers a DNS A record and a corresponding PTR record for a IP address.
    It uses Active Directory to determine the domain controller and reverse DNS zone information.

    IMPORTANT:
    Prior to creating the records, it calls the cleanup methods to remove all existing A/PTR records corresponding to the IP.

.PARAMETER Network
    A PSCustomObject containing network details:
        - NetworkName: Subnet
        - DnsName: Hostname for gateway to be registered
        - Domain: DNS zone name

.PARAMETER IpAddress
    The IpAddress for the A and PTR DNS record.
#>
function Set-IpAddressDNSRecordHelper {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Network,

        [Parameter(Mandatory = $true)]
        [string]$IpAddress
    )

    $domainController = (Get-ADDomainController).Name
    $reverseZoneName = (Get-ReverseZoneInfo -DNSComputerName $domainController -Subnet $Network.NetworkName).ZoneName

    if ($Network.DnsName.EndsWith($Network.Domain)) { $ptrDomainName = $Network.DnsName }
    else { $ptrDomainName = "$($Network.DnsName).$($Network.Domain)" }

    Remove-IpAddressDNSRecordHelper -NetworkName $Network.NetworkName -Domain $Network.Domain -IpAddress $IpAddress

    Set-DnsARecord -DnsServer $domainController -DnsName $Network.DnsName -IpAddress $IpAddress -DnsZone $Network.Domain
    Set-DnsPtrRecord -DnsServer $domainController -ReverseZone $reverseZoneName -Name $IpAddress -PtrDomainName $ptrDomainName
}


<#
.SYNOPSIS
    Removes A and PTR DNS record(s) for a given IP in a network.

.DESCRIPTION
    This function removes DNS A record(s) and corresponding PTR record(s) for a given IP address.
    It determines the domain controller and reverse zone information and removes records based on the IP address.

.PARAMETER NetworkName
    Subnet in CIDR notation (e.g., '10.24.0.0/24').

.PARAMETER Domain
    The forward DNS zone name (e.g., 'de.mtudev.corp').

.PARAMETER IpAddress
    The IP address (optionally with CIDR, e.g. '10.24.0.223/32') for which DNS records should be removed.

.PARAMETER DnsName
    Optional. Only used for logging context (this is the NEW name, not used for removal discovery).
#>
function Remove-IpAddressDNSRecordHelper {
    param (
        [Parameter(Mandatory = $true)]
        [string]$NetworkName,

        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$IpAddress
    )

    try {
        $domainController = (Get-ADDomainController).Name
        $reverseZoneName  = (Get-ReverseZoneInfo -DNSComputerName $domainController -Subnet $NetworkName).ZoneName
        $ipAddressString  = ([string]$IpAddress).Split('/')[0].Trim()

        Remove-AllCorrespondingDnsARecord   -DnsServer $domainController -DnsZone $Domain -IpAddress $ipAddressString
        Remove-AllCorrespondingDnsPtrRecord -DnsServer $domainController -ReverseZone $reverseZoneName -IpAddress $ipAddressString
    }
    catch {
        throw "Failed to remove DNS A/PTR record(s) for IP '$IpAddress' in domain '$Domain': $_"
    }
}

<#
.SYNOPSIS
Creates a new DHCP scope on a specified DHCP server based on a given network object.

.DESCRIPTION
This function checks if a DHCP scope already exists for the provided network. If not, it calculates the DHCP range, gateway, and broadcast address, then creates the scope and sets the appropriate DHCP options. It also creates a corresponding DNS A record and PTR for the gateway.

.PARAMETER Network
A PSCustomObject representing the network, including properties like NetworkName, DHCPType, Description, Domain, and DnsName.

.PARAMETER DHCPServer
The name of the DHCP server where the scope should be created.

.OUTPUTS
None. Writes status messages to the host and throws on failure.

.EXAMPLE
New-DHCPScope -Network $networkObject -DHCPServer "dhcp01.example.com"
#>
function New-DHCPScope {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Network,

        [Parameter(Mandatory=$true)]
        [string]$DHCPServer
    )

    $parts = $Network.NetworkName -split '/'
    if ($parts.Length -ne 2) {
        Write-Host "Invalid network prefix format: $($Network.NetworkName)"
        return
    }
    $subnet = $parts[0]
    $maskBits = [int]$parts[1]

    # --- Check, if Scope already exists ---
    try {
        $existingScope = Get-DhcpServerv4Scope -ComputerName $DHCPServer -ScopeId $subnet -ErrorAction SilentlyContinue
    }
    catch {
        throw "Error retrieving DHCP scopes. Please ensure that the DHCP server module is installed and configured: $_"
    }

    # Converts a CIDR prefix length (e.g., 27) into dotted-decimal notation (e.g., 255.255.255.224)
    function Convert-MaskToDottedDecimal {
        param([int]$mask)
        $maskBin = ("1" * $mask).PadRight(32, "0")
        $bytes = @()
        for ($i=0; $i -lt 4; $i++) {
            $byte = $maskBin.Substring($i*8, 8)
            $bytes += [Convert]::ToInt32($byte, 2)
        }
        return $bytes -join '.'
    }

    function Get-DhcpRange {
        param (
            [string]$networkWithMask
        )
        $parts = $networkWithMask -split '/'
        if ($parts.Count -ne 2) {
            throw "Invalid network prefix format: $networkWithMask"
        }
        $networkAddress = $parts[0]
        $mask = [int]$parts[1]

        # Convert the network address to a UInt32
        $ip = [System.Net.IPAddress]::Parse($networkAddress)
        $bytes = $ip.GetAddressBytes()
        [Array]::Reverse($bytes)
        $ipInt = [BitConverter]::ToUInt32($bytes, 0)

        $hostBits = 32 - $mask
        $totalAddresses = [math]::Pow(2, $hostBits)
        $broadcastInt = $ipInt + $totalAddresses - 1

        # Reserve IPs:
        # - First IP: network address
        # - Last IP: broadcast
        # - Second-to-last: gateway
        # - For /25 to /22: reserve 5 more IPs after gateway
        $gatewayIpInt = $broadcastInt - 1

        $reservedAfterGateway = 0
        if ($mask -ge 22 -and $mask -le 25) {
            $reservedAfterGateway = 5
        }

        $startIpInt = $ipInt + 1
        $endIpInt = $gatewayIpInt - $reservedAfterGateway - 1

        function IntToIp {
            param([UInt32]$ipInt)
            $b = [BitConverter]::GetBytes($ipInt)
            [Array]::Reverse($b)
            return ([System.Net.IPAddress]::Parse(($b -join '.'))).ToString()
        }

        $startIp = IntToIp $startIpInt
        $endIp = IntToIp $endIpInt
        $gateway = IntToIp $gatewayIpInt
        $broadcast = IntToIp $broadcastInt

        return @{
            Start     = $startIp
            End       = $endIp
            Gateway   = $gateway
            Broadcast = $broadcast
            Reserved  = $reservedAfterGateway
        }
    }

    $netmask = Convert-MaskToDottedDecimal -mask $maskBits
    $dhcpRange = Get-DhcpRange -networkWithMask $Network.NetworkName

    if($Network.DHCPType -eq "dhcp_static") {
        $dhcpRange.End = $dhcpRange.Start
    }

    $scopeName = "$($dhcpNetboxMapping[$Network.DHCPType]) $($Network.NetworkName) $($Network.Site) $($Network.Description)"
    $dnsDomain = $Network.Domain

    if ($existingScope) {
        Write-Host "    DHCP scope for network $($Network.NetworkName) already exists."
    }
    else {
        Write-Host "    DHCP scope for network $($Network.NetworkName) does not exist yet."

        Write-Host "    Determined DHCP scope data:"
        Write-Host "     - Scope Name: $scopeName"
        Write-Host "     - Subnet:     $subnet"
        Write-Host "     - Netmask:    $netmask"
        Write-Host "     - DHCP Range: $($dhcpRange.Start) - $($dhcpRange.End)"
        Write-Host "     - Gateway:    $($dhcpRange.Gateway)"
        Write-Host "     - Broadcast:  $($dhcpRange.Broadcast)"

        try {
            if (-not ($dhcpRange.Gateway -eq $Network.DefaultGatewayIpAddress)) {
                throw "The defined gateway IP in the netbox '$($Network.DefaultGatewayIpAddress)' doesn't match the MTU standart (expected '$($dhcpRange.Gateway)')."
            }

            Add-DhcpServerv4Scope -ComputerName $DHCPServer -Name $scopeName -StartRange $dhcpRange.Start -EndRange $dhcpRange.End -SubnetMask $netmask -State Active -LeaseDuration (New-TimeSpan -Days 3) -ErrorAction Stop

            Write-Host "    DHCP scope for network $($Network.NetworkName) successfully created!" -ForegroundColor Green

            if ($Network.DHCPType -eq "dhcp_dynamic") {
                try {
                    Set-DhcpServerv4DnsSetting `
                        -ComputerName $DHCPServer `
                        -ScopeId $subnet `
                        -DynamicUpdates OnClientRequest `
                        -DeleteDnsRRonLeaseExpiry $true `
                        -UpdateDnsRRForOlderClients $true `
                        -DisableDnsPtrRRUpdate $false `
                        -ErrorAction Stop

                    Write-Host "    Dynamic DNS successfully configured for scope $subnet."
                }
                catch {
                    throw "Error configuring Dynamic DNS settings for scope $subnet : $_"
                }
            }

            Set-DhcpServerv4OptionValue -ComputerName $DHCPServer -ScopeId $subnet -DnsDomain $dnsDomain -Router $dhcpRange.Gateway -ErrorAction Stop

            Set-DhcpServerv4OptionValue -ComputerName $DHCPServer -ScopeId $subnet -OptionId 28 -Value $dhcpRange.Broadcast -ErrorAction Stop

            Write-Host "    Configured DHCP scope options 003 (= $($dhcpRange.Gateway)), 015 (= $($Network.Domain)) and 028 (= $($dhcpRange.Broadcast))." -ForegroundColor Green

            if($Network.DHCPType -eq "dhcp_static") {
                Add-DhcpServerv4ExclusionRange -ScopeId $subnet -StartRange $dhcpRange.Start -EndRange $dhcpRange.End -ComputerName $DHCPServer -ErrorAction Stop

                Write-Host "    Set DHCP exclusion range from $($dhcpRange.Start) to $($dhcpRange.End)." -ForegroundColor Green
            }
        }
        catch {
            throw "Error creating DHCP scope for network $($Network.NetworkName): $_"
        }
    }

    Set-IpAddressDNSRecordHelper -Network $Network -IpAddress $Network.DefaultGatewayIpAddress

    Configure-FailoverForScope -DHCPServer $DHCPServer -NetworkID $subnet

    # Local helpers (kept inside function to minimize global changes)
    function Convert-IPv4ToUInt32 {
        param([string]$ipAddress)
        $ip = [System.Net.IPAddress]::Parse($ipAddress)
        $bytes = $ip.GetAddressBytes()
        [Array]::Reverse($bytes)
        return [BitConverter]::ToUInt32($bytes, 0)
    }
    function Convert-UInt32ToIPv4 {
        param([uint32]$value)
        $b = [BitConverter]::GetBytes($value)
        [Array]::Reverse($b)
        return ([System.Net.IPAddress]::Parse(($b -join '.'))).ToString()
    }

    # --- Post: Add /24-based exclusions if scope spans multiple /24s ---
    # Your requirement: For every included /24 in a larger scope (e.g., /16, /22, /23),
    # exclude .0, .1 and .249-.255 (clipped to the actual DHCP range).
    if (($maskBits -lt 24) -and ($Network.DHCPType -eq "dhcp_dynamic")) {
        $dhcpRange = Get-DhcpRange -networkWithMask $Network.NetworkName
        Write-Host "    Applying /24-based exclusion ranges (because the scope contains multiple /24s)..."

        $startInt = Convert-IPv4ToUInt32 $dhcpRange.Start
        $endInt   = Convert-IPv4ToUInt32 $dhcpRange.End

        # Iterate each /24 block intersecting the DHCP range
        for ($block = $startInt - ($startInt % 256); $block -le $endInt; $block += 256) {

            # Single-IP exclusions: .0 and .1
            $candidates = @($block, ($block + 1))

            foreach ($addr in $candidates) {
                if ($addr -gt $startInt -and $addr -le $endInt) {
                    $ip = Convert-UInt32ToIPv4 $addr

                    Add-DhcpServerv4ExclusionRange -ScopeId $subnet -StartRange $ip -EndRange $ip -ComputerName $DHCPServer -ErrorAction SilentlyContinue
                    Write-Host "    Excluded single IP $ip in scope $subnet"
                }
            }

            # Range exclusion: .249 - .255 (clip to scope bounds)
            $rangeStart = [Math]::Max($block + 249, $startInt)
            $rangeEnd   = [Math]::Min($block + 255, $endInt)

            if ($rangeStart -le $rangeEnd) {
                $startIp = Convert-UInt32ToIPv4 $rangeStart
                $endIp   = Convert-UInt32ToIPv4 $rangeEnd

                Add-DhcpServerv4ExclusionRange -ScopeId $subnet -StartRange $startIp -EndRange $endIp -ComputerName $DHCPServer -ErrorAction SilentlyContinue
                Write-Host "    Excluded range $startIp - $endIp in scope $subnet"
            }
        }

        Write-Host "    Finished applying /24-based exclusions for scope $subnet."
    }
    # --- Post: Add /24-based exclusions if scope is exactly /24 ---
    elseif (($maskBits -eq 24) -and ($Network.DHCPType -eq "dhcp_dynamic")) {
        $dhcpRange = Get-DhcpRange -networkWithMask $Network.NetworkName
        Write-Host "    Applying /24-based exclusion ranges for a /24 scope..."

        $startInt = Convert-IPv4ToUInt32 $dhcpRange.Start

        $blockBase = $startInt - ($startInt % 256)

        $singleCandidates = @($blockBase, ($blockBase + 1))
        foreach ($addr in $singleCandidates) {
            $ip = Convert-UInt32ToIPv4 $addr
            Add-DhcpServerv4ExclusionRange -ScopeId $subnet -StartRange $ip -EndRange $ip -ComputerName $DHCPServer -ErrorAction Stop
            Write-Host "    Excluded single IP $ip in scope $subnet"
        }

        $startIp = Convert-UInt32ToIPv4 ($blockBase + 249)
        $endIp   = Convert-UInt32ToIPv4 ($blockBase + 255)

        Add-DhcpServerv4ExclusionRange -ScopeId $subnet -StartRange $startIp -EndRange $endIp -ComputerName $DHCPServer -ErrorAction Stop
        Write-Host "    Excluded range $startIp - $endIp in scope $subnet"
    }
}

<#
.SYNOPSIS
Checks if a given subnet exists in Active Directory and returns its associated site name.

.DESCRIPTION
This function queries Active Directory for a replication subnet using the specified domain controller. If the subnet exists, it extracts and returns the associated site name.

.PARAMETER Subnet
The subnet in CIDR notation (e.g., "10.24.0.0/24") to check in Active Directory.

.PARAMETER DomainController
The domain controller to query for the subnet information.

.OUTPUTS
String - The name of the associated AD site if found; otherwise, $false.

.EXAMPLE
Test-ADSubnetSite -Subnet "10.24.0.0/24" -DomainController "dc01.example.com"
#>
function Test-ADSubnetSite {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Subnet,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $DomainController
    )

    $parts  = $Subnet -split '/'
    if ($parts.Count -ne 2) {
        throw "Invalid subnet format. Expected CIDR notation like '10.24.0.0/24'."
    }

    $ip     = $parts[0]
    try { $prefix = [int]$parts[1] } catch { throw "Invalid prefix length in subnet '$Subnet'." }

    if ($prefix -lt 0 -or $prefix -gt 32) {
        throw "Prefix length must be between 0 and 32."
    }

    $octets = $ip -split '\.'
    if ($octets.Count -ne 4 -or ($octets | Where-Object { ($_ -as [int]) -lt 0 -or ($_ -as [int]) -gt 255 }).Count ) {
        throw "Invalid IPv4 address in subnet '$Subnet'."
    }
    $o0 = [int]$octets[0]; $o1 = [int]$octets[1]; $o2 = [int]$octets[2]; $o3 = [int]$octets[3]

    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add($Subnet)

    $levels = 24,16,8 |
            Where-Object { $_ -le $prefix } |
            Sort-Object -Descending

    foreach ($level in $levels) {
        switch ($level) {
            24 { $network = "{0}.{1}.{2}.0/24" -f $o0, $o1, $o2 }
            16 { $network = "{0}.{1}.0.0/16"   -f $o0, $o1 }
            8 { $network = "{0}.0.0.0/8"      -f $o0 }
        }
        if ($network -ne $Subnet -and -not $candidates.Contains($network)) {
            $candidates.Add($network)
        }
    }

    Write-Verbose ("Candidates to query (in order): {0}" -f ($candidates -join ', '))

    foreach ($network in $candidates) {
        try {
            $entry = Get-ADReplicationSubnet `
                        -Server $DomainController `
                        -Filter "Name -eq '$network'" `
                        -ErrorAction Stop
        }
        catch {
            Write-Verbose "Query failed or subnet not found for '$network': $($_.Exception.Message)"
            continue
        }

        if ($null -ne $entry) {
            foreach ($e in @($entry)) {
                if ($e.Site) {
                    $siteName = ($e.Site -split ',')[0] -replace '^CN='
                    Write-Verbose "Match found: '$network' -> Site '$siteName'"
                    return $siteName
                }
            }
        }
    }

    Write-Verbose "No matching AD replication subnet found for '$Subnet' (including top-level fallbacks)."
    return $false
}

<#
.SYNOPSIS
    Retrieves and simplifies the forest name associated with a given Active Directory domain.

.DESCRIPTION
    This function queries Active Directory to determine the forest to which a specified domain belongs.
    It then maps known forest DNS names to simplified identifiers for easier reference in scripts or reports.

.PARAMETER Domain
    The fully qualified domain name (FQDN) of the Active Directory domain to query.

.OUTPUTS
    [string] A simplified forest name (e.g., 'MTU', 'MTUDEV'), or the original forest name if no mapping is defined.

.EXAMPLE
    Get-ForestShortNameFromDomain -Domain "de.mtudev.corp"
    Returns: "MTUDEV"
#>
function Get-ForestShortNameFromDomain {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    try {
        $forest = Get-ADForest -Server $Domain

        switch ($forest.Name.ToLower()) {
            "mtu.corp" { return "MTU" }
            "mtudev.corp" { return "MTUDEV" }
            "ads.mtugov.de" { return "MTUGOV" }
            "ads.mtuchina.app" { return "MTUCHINA" }
            default { return $forest.Name }
        }
    }
    catch {
        Write-Error "Error retrieving forest name for domain '$Domain': $_"
        throw
    }
}

function Invoke-Process {
    $statusMessages = @();

    $DomainControllerName = (Get-ADDomainController).Name

    Write-Host "Fetching onboarding open networks from Netbox..."

    $netboxNetworkFilter = @{"status" = "onboarding_open_dns_dhcp"}

    if ($dev)   { $dnsZone = "de.mtudev.corp" }
    if ($test)  { $dnsZone = "test.mtu.corp" }
    if ($prod)  { $dnsZone = "de.mtu.corp" }
    if ($gov)   { $dnsZone = "ads.mtugov.de" }
    if ($china) { $dnsZone = "ads.mtuchina.app" }

    $netboxNetworkFilter.cf_domain = $dnsZone

    $openOnboardingNetworks = Get-NetworkInfo -NetboxBaseUrl $NetboxBaseUrl -NetboxApiKey $NetboxApiKey -Filter $netboxNetworkFilter

    Write-Host "Retrieved $($openOnboardingNetworks.Count) networks."
    Write-Host
    Write-Host "Logs for each processed network are stored in separate files..."

    foreach ($network in $openOnboardingNetworks) {
        $logFilePath = ".\logs\network_$($network.NetworkName -replace '/', '_')_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        try {
            try { Stop-Transcript -ErrorAction Stop | Out-Null } catch {}
            Start-Transcript -Path $logFilePath -Append | Out-Null

            Write-Host
            Write-Host "Processing open onboarded network: $($network.NetworkName) $($network.DHCPType)"

            $missingFields = @()
            foreach ($key in $network | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name) {
                if ($key -eq 'ADSitesAndServicesTicketUrl') {
                    continue
                }
                $value = $network.$key
                if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) {
                    $missingFields += $key
                }
            }

            if ($missingFields.Count -gt 0) {
                $logMessage = "Following required fields are not defined in the netbox: $($missingFields -join ', ' )"
                Write-Host "    $logMessage"
                throw $logMessage
            }

            $forestShortName = Get-ForestShortNameFromDomain -Domain $network.Domain

            $subnetSite = Test-ADSubnetSite -DomainController $DomainControllerName -Subnet $network.NetworkName

            $TempDomain = $network.Domain

            if($network.Domain -eq "test.mtu.corp") {
                $TempDomain = "de.mtu.corp"
            }

            $dnsZoneDelegated = (Test-ReverseZoneDelegation -Subnet $network.NetworkName -Domain $TempDomain) -eq $true

            if(-not ($subnetSite)) {
                Write-Host "    Network not assigned to any AD site." -ForegroundColor Red

                if($network.ADSitesAndServicesTicketUrl) {
                    $logMessage = "Jira Ticket for AD-Site configuration already exists and site not yet assigned (ticket maybe still in proccess): $($network.ADSitesAndServicesTicketUrl)"
                    Write-Host "    $logMessage"
                    throw $logMessage
                } else {
                    $jiraTicket = New-ReverseZoneAndSiteAndServicesMaintainJiraTicket -JiraApiKey $JiraApiKey -JiraBaseUrl $JiraBaseUrl -Subnet $network.NetworkName -Site $network.Site -ForestShortName $forestShortName -DnsZoneDelegated $dnsZoneDelegated

                    if($jiraTicket.key) {
                        $jiraTicketLink = "$($JiraBaseUrl)/browse/$($jiraTicket.key)"

                        Update-NetboxNetworkJiraTicketLink -NetworkNumber $network.Id -NetboxApiKey $NetboxApiKey -NetboxBaseUrl $NetboxBaseUrl -jiraTicketLink $jiraTicketLink | Out-Null
                    }
                    else {
                        throw "An unknown error occurred while creating the jira ticket!"
                    }
                }

                continue;
            }
            elseif(-not ($subnetSite.toUpper() -eq $network.ValuemationSiteMandant.toUpper())) {
                 throw "    Network is assigned to AD site $subnetSite, but expected $($network.ValuemationSiteMandant)!"
            }

            Write-Host "    Network is assigned to AD site $subnetSite." -ForegroundColor Green

            # REVERSE ZONE CHECK
            if((Get-ReverseZoneInfo -Subnet $network.NetworkName -DNSComputerName $DomainControllerName) -eq $false) {
                Write-Host "    Expected a Reverse-Zone configuration, but none was found." -ForegroundColor Red

                if($network.ADSitesAndServicesTicketUrl) {
                    $logMessage = "Jira Ticket for Reverse-Zone-Configuration already exists and no expected Reverse-Zone configured yet, ticket maybe still in proccess (Ticket: $($network.ADSitesAndServicesTicketUrl))"
                    Write-Host "    $logMessage"
                    throw $logMessage
                } else {
                    $jiraTicket = New-ReverseZoneAndSiteAndServicesMaintainJiraTicket -JiraApiKey $JiraApiKey -JiraBaseUrl $JiraBaseUrl -Subnet $network.NetworkName -Site $network.Site -ForestShortName $forestShortName -DnsZoneDelegated $dnsZoneDelegated

                    if($jiraTicket.key) {
                        $jiraTicketLink = "$($JiraBaseUrl)/browse/$($jiraTicket.key)"

                        Update-NetboxNetworkJiraTicketLink -NetworkNumber $network.Id -NetboxApiKey $NetboxApiKey -NetboxBaseUrl $NetboxBaseUrl -jiraTicketLink $jiraTicketLink | Out-Null
                    }
                    else {
                        throw "An unknown error occurred while creating the jira ticket!"
                    }
                }

                continue;
            }

            Write-Host "    Reverse zone configured."  -ForegroundColor Green

            # DNS DELEGATION HANDLE
            if($dnsZoneDelegated -eq $false) {
                Write-Host "    Expected a DNS Delegation configuration, but none was found." -ForegroundColor Red

                if($network.ADSitesAndServicesTicketUrl) {
                    $logMessage = "Jira Ticket for DNS Delegation Configuration already exists and no expected DNS Delegation configured yet, ticket maybe still in proccess (Ticket: $($network.ADSitesAndServicesTicketUrl))"
                    Write-Host "    $logMessage"
                    throw $logMessage
                } else {
                    $jiraTicket = New-ReverseZoneAndSiteAndServicesMaintainJiraTicket -JiraApiKey $JiraApiKey -JiraBaseUrl $JiraBaseUrl -Subnet $network.NetworkName -Site $network.Site -ForestShortName $forestShortName -DnsZoneDelegated $dnsZoneDelegated

                    if($jiraTicket.key) {
                        $jiraTicketLink = "$($JiraBaseUrl)/browse/$($jiraTicket.key)"

                        Update-NetboxNetworkJiraTicketLink -NetworkNumber $network.Id -NetboxApiKey $NetboxApiKey -NetboxBaseUrl $NetboxBaseUrl -jiraTicketLink $jiraTicketLink | Out-Null
                    }
                    else {
                        throw "An unknown error occurred while creating the jira ticket!"
                    }
                }

                continue;
            }

            Write-Host "    DNS Delegation configured."  -ForegroundColor Green

            if($network.ADSitesAndServicesTicketUrl) {
                $ADSitesAndServicesTicketKey = Get-JiraTicketKeyFromUrl -JiraUrl $network.ADSitesAndServicesTicketUrl

                if((Get-JiraTicketStatus -JiraBaseUrl $JiraBaseUrl -JiraApiKey $JiraApiKey -TicketKey $ADSitesAndServicesTicketKey) -eq "Verify") {
                    Set-JiraIssueStatus  -JiraBaseUrl $JiraBaseUrl -JiraApiKey $JiraApiKey -TicketKey $ADSitesAndServicesTicketKey -TargetStatus "Close"
                } else {
                    if(-not ((Get-JiraTicketStatus -JiraBaseUrl $JiraBaseUrl -JiraApiKey $JiraApiKey -TicketKey $ADSitesAndServicesTicketKey) -eq "Geschlossen")) {
                        Write-Host

                        $logMessage = "The site, reverse zone and DNS delegation for the subnet has been configured, but the Jira ticket has not been closed yet (Ticket: $ADSitesAndServicesTicketKey)."
                        Write-Host "    $logMessage" -ForegroundColor Red
                        throw $logMessage
                    }
                }
            }

            if ($network.DHCPType -eq "no_dhcp") {
                Write-Host "    No DHCP configuration needed (DHCP-Type: no_dhcp) -> skipping DHCP scope creation." -ForegroundColor Green
                Set-IpAddressDNSRecordHelper -Network $Network -IpAddress $Network.DefaultGatewayIpAddress
                Update-NetboxNetworkPrefixStatusOnboardingDone -NetworkNumber $network.Id -NetboxApiKey $NetboxApiKey -NetboxBaseUrl $NetboxBaseUrl | Out-Null
            }
            elseif ($network.DHCPType -eq "dhcp_static" -or $network.DHCPType -eq "dhcp_dynamic") {
                Write-Host "    Identified network dns name $($network.DnsName)." -ForegroundColor Green

                if ($dev -or $test) {
                    $primaryDhcpServer = Get-PrimaryDHCPServer -Site "muc" -dev $dev
                    Write-Host "    Using a MUC DHCP Server in Test or Dev Environment!" -ForegroundColor Yellow
                }
                else {
                    $primaryDhcpServer = Get-PrimaryDHCPServer -Site $subnetSite -dev $dev
                }

                New-DHCPScope -Network $network -DHCPServer $primaryDhcpServer

                Update-NetboxNetworkPrefixStatusOnboardingDone -NetworkNumber $network.Id -NetboxApiKey $NetboxApiKey -NetboxBaseUrl $NetboxBaseUrl | Out-Null
            }

            $transcriptContent = Get-Content -Path $logFilePath -Raw
            Add-NetboxJournalEntry -NetboxBaseUrl $NetboxBaseUrl -NetboxApiKey $NetboxApiKey -Kind info -TargetType Prefix -TargetId $network.Id -Message ($transcriptContent -replace "`n", "<br>") | Out-Null
        } catch {
            $errorMessage = "An error occurred creating the DHCP scope for the network $($network.NetworkName): $_"
            try {
                $transcriptContent = Get-Content -Path $logFilePath -Raw
                Add-NetboxJournalEntry -NetboxBaseUrl $NetboxBaseUrl -NetboxApiKey $NetboxApiKey -Kind danger -TargetType Prefix -TargetId $network.Id -Message (($transcriptContent + "`n" + $errorMessage) -replace "`n", "<br>") | Out-Null
            }
            catch {
                $errorMessage =  " & the error couldn't be logged in the netbox journal: $_!"
            }

            Write-Error $errorMessage

            $statusMessages = $statusMessages + "<a href='$NetboxBaseUrl/ipam/prefixes/$($network.Id)/'><strong>$($network.NetworkName) - $($network.Domain)</strong></a>: $errorMessage"
        }
    }

    Start-Transcript -Path $startingProcessLogFilePath -Append | Out-Null

    $netboxIpFilter = @{
        "status" = @("onboarding_open_dns","decommissioning_open_dns")
    }

    if ($dev)   { $dnsZone = "de.mtudev.corp" }
    if ($test)  { $dnsZone = "test.mtu.corp" }
    if ($prod)  { $dnsZone = "de.mtu.corp" }
    if ($gov)   { $dnsZone = "ads.mtugov.de" }
    if ($china) { $dnsZone = "ads.mtuchina.app" }

    $IPs = Find-IpAddresses -NetboxBaseUrl $NetboxBaseUrl -NetboxApiKey $NetboxApiKey -Filter $netboxIpFilter | ForEach-Object {
        $IP = $_

        $prefix = Get-PrefixesForAddress -NetboxBaseUrl $NetboxBaseUrl -NetboxApiKey $NetboxApiKey -AddressOrPrefix $ip.IpAddress | Select-Object -Last 1

        $IP | Add-Member -MemberType NoteProperty -Name "Domain" -Value $prefix.Domain -Force
        $IP | Add-Member -MemberType NoteProperty -Name "Prefix" -Value $prefix.Prefix -Force

        return $IP
    } | Where-Object { $_.Domain -eq $dnsZone }

    Write-Host "Retrieved $($IPs.Count) IPs."
    Write-Host
    Write-Host "Logs for each processed IP are stored in separate files..."

    foreach($IP in $IPs) {
        $logFilePath = ".\logs\ip_$($IP.IpAddress -replace '/', '_')_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        try {
            try { Stop-Transcript -ErrorAction Stop | Out-Null } catch {}
            Start-Transcript -Path $logFilePath -Append | Out-Null

            Write-Host

            if($IP.Status -eq "onboarding_open_dns") {
                Write-Host "Processing open onboarded ip: $($IP.IpAddress)"
                if(-not $IP.DnsName) {
                    throw "IP is onboarding-open but no DNS Name is defined."
                }

                $network = @{
                    "NetworkName" = $IP.Prefix
                    "DnsName" = $IP.DnsName
                    "Domain" = $IP.Domain
                }

                if((Get-ReverseZoneInfo -Subnet $network.NetworkName -DNSComputerName (Get-ADDomainController).Name) -eq $false) {
                    throw "    Expected a Reverse-Zone configuration, but none was found."
                }

                Set-IpAddressDNSRecordHelper -Network $network -IpAddress $IP.IpAddress

                $ipUpdateObject = @{
                    "status"   = "onboarding_done_dns"
                }
            } elseif($IP.Status -eq "decommissioning_open_dns") {
                Write-Host "Processing open decomissioning ip: $($IP.IpAddress)"

                Remove-IpAddressDNSRecordHelper -NetworkName $IP.Prefix -Domain $IP.Domain -IpAddress $IP.IpAddress

                $ipUpdateObject = @{
                    "status"   = "decommissioning_done_dns"
                }
            }

            Update-NetboxIPAddress -IpAddressId $IP.Id -UpdateObject $ipUpdateObject -NetboxApiKey $NetboxApiKey -NetboxBaseUrl $NetboxBaseUrl | Out-Null

            $transcriptContent = Get-Content -Path $logFilePath -Raw
            Add-NetboxJournalEntry -NetboxBaseUrl $NetboxBaseUrl -NetboxApiKey $NetboxApiKey -Kind info -TargetType IPAddress -TargetId $IP.Id -Message ($transcriptContent -replace "`n", "<br>") | Out-Null
        }
        catch {
            $errorMessage = "An error occurred processing a IP $($IP.IpAddress): $_"
            try {
                $transcriptContent = Get-Content -Path $logFilePath -Raw
                Add-NetboxJournalEntry -NetboxBaseUrl $NetboxBaseUrl -NetboxApiKey $NetboxApiKey -Kind danger -TargetType IPAddress -TargetId $IP.Id -Message (($transcriptContent + "`n" + $errorMessage) -replace "`n", "<br>") | Out-Null
            }
            catch {
                $errorMessage =  " & the error couldn't be logged in the netbox journal: $_!"
            }

            Write-Error $errorMessage

            $statusMessages = $statusMessages + "<a href='$NetboxBaseUrl/ipam/ip-addresses/$($IP.Id)/'><strong>$($IP.IpAddress) - $($IP.DnsName)</strong></a>: $errorMessage"
        }
    }

    if ($statusMessages) {
        $body = @"
<p>During the execution of the <strong>DHCP Scope Automation</strong> script, the process was aborted for the following networks/ips:</p>
<p>$($statusMessages -join '<br/>')</p>
<p>Please review the issues listed above and take the necessary actions to restore full network functionality.</p>
<p><em>This is an automated message. No reply is required.</em></p>
"@

        foreach($EmailRecipient in $EmailRecipients) {
            Send-Mail -To $EmailRecipient -Subject "DHCP Scope Automation Script" -BodyAsHtml -Body $Body
        }
    }

    try { Stop-Transcript -ErrorAction Stop | Out-Null } catch {}

    Write-Host ""
    Write-Host "Bye!"
}

Invoke-Process
