# Generated from Classes/* by Scripts/Sync-ClassFiles.ps1.
# Keep module loading on this single file for PowerShell 5.1 class parser compatibility.

# Captures a single structured audit event for logs, summaries, and user-facing output.
class OperationAuditEntry {
    [datetime] $TimestampUtc
    [string] $Level
    [string] $Message

    OperationAuditEntry([string] $level, [string] $message) {
        if ([string]::IsNullOrWhiteSpace($level)) {
            throw [System.ArgumentException]::new('Level is required.')
        }

        if ([string]::IsNullOrWhiteSpace($message)) {
            throw [System.ArgumentException]::new('Message is required.')
        }

        $normalizedLevel = $level.Trim()
        $allowedLevels = @('Debug', 'Information', 'Warning', 'Error', 'Verbose')
        if ($normalizedLevel -notin $allowedLevels) {
            throw [System.ArgumentOutOfRangeException]::new('level', "Unsupported log level '$level'.")
        }

        $this.TimestampUtc = [datetime]::UtcNow
        $this.Level = $normalizedLevel
        $this.Message = $message
    }
}

# Holds future routing metadata so failures can later be assigned to the right department or handler.
class IssueHandlingContext {
    [string] $Department
    [string] $Handler

    IssueHandlingContext([string] $department, [string] $handler) {
        $this.Department = $this.NormalizeValue($department)
        $this.Handler = $this.NormalizeValue($handler)
    }

    static [IssueHandlingContext] CreateUnassigned() {
        return [IssueHandlingContext]::new($null, $null)
    }

    hidden [string] NormalizeValue([string] $value) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $null
        }

        return $value.Trim()
    }

    [string] GetDepartmentOrDefault() {
        if ([string]::IsNullOrWhiteSpace($this.Department)) {
            return 'Unassigned'
        }

        return $this.Department
    }

    [string] GetHandlerOrDefault() {
        if ([string]::IsNullOrWhiteSpace($this.Handler)) {
            return 'Unassigned'
        }

        return $this.Handler
    }

    [bool] HasAssignedDepartment() {
        return -not [string]::IsNullOrWhiteSpace($this.Department)
    }

    [bool] HasAssignedHandler() {
        return -not [string]::IsNullOrWhiteSpace($this.Handler)
    }
}

# Represents a recoverable processing failure with enough context for mailing, journaling, and reporting.
class OperationIssue {
    [datetime] $TimestampUtc
    [string] $WorkItemType
    [string] $WorkItemIdentifier
    [string] $Message
    [string] $Details
    [IssueHandlingContext] $HandlingContext
    [string] $ResourceUrl

    OperationIssue([string] $workItemType, [string] $workItemIdentifier, [string] $message, [string] $details) {
        $this.Initialize($workItemType, $workItemIdentifier, $message, $details, [IssueHandlingContext]::CreateUnassigned(), $null)
    }

    OperationIssue([string] $workItemType, [string] $workItemIdentifier, [string] $message, [string] $details, [IssueHandlingContext] $issueHandlingContext) {
        $this.Initialize($workItemType, $workItemIdentifier, $message, $details, $issueHandlingContext, $null)
    }

    OperationIssue(
        [string] $workItemType,
        [string] $workItemIdentifier,
        [string] $message,
        [string] $details,
        [IssueHandlingContext] $issueHandlingContext,
        [string] $resourceUrl
    ) {
        $this.Initialize($workItemType, $workItemIdentifier, $message, $details, $issueHandlingContext, $resourceUrl)
    }

    hidden [void] Initialize(
        [string] $workItemType,
        [string] $workItemIdentifier,
        [string] $message,
        [string] $details,
        [IssueHandlingContext] $issueHandlingContext,
        [string] $resourceUrl
    ) {
        if ([string]::IsNullOrWhiteSpace($workItemType)) {
            throw [System.ArgumentException]::new('WorkItemType is required.')
        }

        if ([string]::IsNullOrWhiteSpace($message)) {
            throw [System.ArgumentException]::new('Message is required.')
        }

        if ($null -eq $issueHandlingContext) {
            $issueHandlingContext = [IssueHandlingContext]::CreateUnassigned()
        }

        $this.TimestampUtc = [datetime]::UtcNow
        $this.WorkItemType = $workItemType
        $this.WorkItemIdentifier = $workItemIdentifier
        $this.Message = $message
        $this.Details = $details
        $this.HandlingContext = $issueHandlingContext
        $this.ResourceUrl = $resourceUrl
    }

    [string] GetHandlingDepartment() {
        return $this.HandlingContext.GetDepartmentOrDefault()
    }

    [string] GetHandlingHandler() {
        return $this.HandlingContext.GetHandlerOrDefault()
    }

    [bool] HasResourceUrl() {
        return -not [string]::IsNullOrWhiteSpace($this.ResourceUrl)
    }
}

# Aggregates the outcome of one batch-style use case execution.
class BatchRunSummary {
    [string] $ProcessName
    [datetime] $StartedUtc
    [datetime] $FinishedUtc
    [int] $SuccessCount
    [int] $FailureCount
    [OperationIssue[]] $Issues
    [OperationAuditEntry[]] $AuditEntries

    BatchRunSummary([string] $processName) {
        if ([string]::IsNullOrWhiteSpace($processName)) {
            throw [System.ArgumentException]::new('ProcessName is required.')
        }

        $this.ProcessName = $processName
        $this.StartedUtc = [datetime]::UtcNow
        $this.Issues = @()
        $this.AuditEntries = @()
    }

    [void] AddSuccess([string] $message) {
        $this.SuccessCount++
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            $this.AddAudit('Information', $message)
        }
    }

    [void] AddFailure([OperationIssue] $issue) {
        if ($null -eq $issue) {
            throw [System.ArgumentNullException]::new('issue')
        }

        $this.FailureCount++
        $this.Issues = @($this.Issues + $issue)
        $this.AddAudit('Error', $issue.Message)
    }

    [void] AddAudit([string] $level, [string] $message) {
        $entry = [OperationAuditEntry]::new($level, $message)
        $this.AuditEntries = @($this.AuditEntries + $entry)
    }

    [void] Complete() {
        $this.FinishedUtc = [datetime]::UtcNow
    }

    [bool] HasFailures() {
        return $this.FailureCount -gt 0
    }
}

# Encapsulates environment-specific behavior such as DNS zones and delegation rules.
class EnvironmentContext {
    [string] $Name
    [string] $DnsZone

    EnvironmentContext([string] $name) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [System.ArgumentException]::new('Environment name is required.')
        }

        $normalizedName = $name.Trim().ToLowerInvariant()
        switch ($normalizedName) {
            'dev'   { $this.DnsZone = 'de.mtudev.corp' }
            'test'  { $this.DnsZone = 'test.mtu.corp' }
            'prod'  { $this.DnsZone = 'de.mtu.corp' }
            'gov'   { $this.DnsZone = 'ads.mtugov.de' }
            'china' { $this.DnsZone = 'ads.mtuchina.app' }
            default { throw [System.ArgumentOutOfRangeException]::new('name', "Unsupported environment '$name'.") }
        }

        $this.Name = $normalizedName
    }

    [bool] IsDevelopment() {
        return $this.Name -eq 'dev'
    }

    [bool] IsTest() {
        return $this.Name -eq 'test'
    }

    [bool] IsProduction() {
        return $this.Name -eq 'prod'
    }

    [string] GetDelegationValidationDomain() {
        if ($this.DnsZone -eq 'test.mtu.corp') {
            return 'de.mtu.corp'
        }

        return $this.DnsZone
    }
}

# Wraps a validated IPv4 address and provides conversion helpers for subnet calculations.
class IPv4Address {
    [string] $Value

    IPv4Address([string] $value) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw [System.ArgumentException]::new('IPv4 address value is required.')
        }

        $normalized = $value.Trim()
        $ip = [System.Net.IPAddress]::Parse($normalized)
        if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            throw [System.ArgumentException]::new("Only IPv4 addresses are supported. Found '$value'.")
        }

        $this.Value = $ip.ToString()
    }

    hidden static [uint32] ConvertToUInt32([string] $ipAddress) {
        $parsed = [System.Net.IPAddress]::Parse($ipAddress)
        $bytes = $parsed.GetAddressBytes()
        [Array]::Reverse($bytes)
        return [BitConverter]::ToUInt32($bytes, 0)
    }

    hidden static [string] ConvertFromUInt32([uint32] $value) {
        $bytes = [BitConverter]::GetBytes($value)
        [Array]::Reverse($bytes)
        return ([System.Net.IPAddress]::new($bytes)).ToString()
    }

    [uint32] GetUInt32() {
        return [IPv4Address]::ConvertToUInt32($this.Value)
    }

    [IPv4Address] AddOffset([int] $offset) {
        $target = [uint32]([int64] $this.GetUInt32() + [int64] $offset)
        return [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($target))
    }

    [string] ToString() {
        return $this.Value
    }
}

# Models an IPv4 network and centralizes address arithmetic used across the domain layer.
class IPv4Subnet {
    [string] $Cidr
    [IPv4Address] $NetworkAddress
    [int] $PrefixLength

    IPv4Subnet([string] $cidr) {
        if ([string]::IsNullOrWhiteSpace($cidr)) {
            throw [System.ArgumentException]::new('CIDR value is required.')
        }

        $parts = $cidr.Trim().Split('/')
        if ($parts.Length -ne 2) {
            throw [System.ArgumentException]::new("Invalid CIDR '$cidr'.")
        }

        $prefix = 0
        if (-not [int]::TryParse($parts[1], [ref] $prefix)) {
            throw [System.ArgumentException]::new("Invalid prefix length in '$cidr'.")
        }

        if ($prefix -lt 0 -or $prefix -gt 32) {
            throw [System.ArgumentOutOfRangeException]::new('cidr', "Prefix length must be between 0 and 32. Found '$prefix'.")
        }

        $baseAddress = [IPv4Address]::new($parts[0])
        $networkNumber = [IPv4Subnet]::MaskAddress($baseAddress.GetUInt32(), $prefix)

        $this.NetworkAddress = [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($networkNumber))
        $this.PrefixLength = $prefix
        $this.Cidr = '{0}/{1}' -f $this.NetworkAddress.Value, $prefix
    }

    hidden static [uint32] GetMask([int] $prefixLength) {
        if ($prefixLength -eq 0) {
            return [uint32] 0
        }

        return [uint32] ([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefixLength))
    }

    hidden static [uint32] MaskAddress([uint32] $address, [int] $prefixLength) {
        $mask = [IPv4Subnet]::GetMask($prefixLength)
        return [uint32] ($address -band $mask)
    }

    [string] GetSubnetMaskString() {
        return [IPv4Address]::ConvertFromUInt32([IPv4Subnet]::GetMask($this.PrefixLength))
    }

    [IPv4Address] GetBroadcastAddress() {
        $hostBits = 32 - $this.PrefixLength
        $broadcastNumber = [uint32] ($this.NetworkAddress.GetUInt32() + [uint32]([math]::Pow(2, $hostBits) - 1))
        return [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($broadcastNumber))
    }

    [IPv4Address] GetAddressAtOffset([int] $offset) {
        return $this.NetworkAddress.AddOffset($offset)
    }

    [string] GetReverseZoneName() {
        $fullOctets = [math]::Floor($this.PrefixLength / 8)
        if ($fullOctets -lt 1 -or $fullOctets -gt 4) {
            throw [System.InvalidOperationException]::new("Prefix '$($this.Cidr)' does not map to an octet-based reverse zone.")
        }

        $octets = $this.NetworkAddress.Value.Split('.')
        switch ($fullOctets) {
            1 { return '{0}.in-addr.arpa' -f $octets[0] }
            2 { return '{0}.{1}.in-addr.arpa' -f $octets[1], $octets[0] }
            3 { return '{0}.{1}.{2}.in-addr.arpa' -f $octets[2], $octets[1], $octets[0] }
            4 { return '{0}.{1}.{2}.{3}.in-addr.arpa' -f $octets[3], $octets[2], $octets[1], $octets[0] }
        }

        throw [System.InvalidOperationException]::new("Unable to derive reverse zone for '$($this.Cidr)'.")
    }

    [string[]] GetAdLookupCandidates() {
        $candidates = @($this.Cidr)
        $octets = $this.NetworkAddress.Value.Split('.')
        $levels = @(24, 16, 8)

        foreach ($level in $levels) {
            if ($level -gt $this.PrefixLength) {
                continue
            }

            $candidate = $null
            switch ($level) {
                24 { $candidate = '{0}.{1}.{2}.0/24' -f $octets[0], $octets[1], $octets[2] }
                16 { $candidate = '{0}.{1}.0.0/16' -f $octets[0], $octets[1] }
                8 { $candidate = '{0}.0.0.0/8' -f $octets[0] }
            }

            if ($candidate -notin $candidates) {
                $candidates += $candidate
            }
        }

        return $candidates
    }

    [string[]] Get24BlockBaseAddresses() {
        $blocks = @()
        $startNumber = $this.NetworkAddress.GetUInt32()
        $endNumber = $this.GetBroadcastAddress().GetUInt32()
        $blockBase = [uint32] ($startNumber - ($startNumber % 256))

        while ($blockBase -le $endNumber) {
            $blocks += [IPv4Address]::ConvertFromUInt32($blockBase)
            $blockBase = [uint32] ($blockBase + 256)
        }

        return $blocks
    }

    [string] ToString() {
        return $this.Cidr
    }
}

# Describes a DHCP exclusion range and whether failing to apply it should abort the scope setup.
class DhcpExclusionRange {
    [IPv4Address] $StartAddress
    [IPv4Address] $EndAddress
    [bool] $MustSucceed

    DhcpExclusionRange([IPv4Address] $startAddress, [IPv4Address] $endAddress) {
        $this.Initialize($startAddress, $endAddress, $true)
    }

    DhcpExclusionRange([IPv4Address] $startAddress, [IPv4Address] $endAddress, [bool] $mustSucceed) {
        $this.Initialize($startAddress, $endAddress, $mustSucceed)
    }

    hidden [void] Initialize([IPv4Address] $startAddress, [IPv4Address] $endAddress, [bool] $mustSucceed) {
        if ($null -eq $startAddress) {
            throw [System.ArgumentNullException]::new('startAddress')
        }

        if ($null -eq $endAddress) {
            throw [System.ArgumentNullException]::new('endAddress')
        }

        if ($startAddress.GetUInt32() -gt $endAddress.GetUInt32()) {
            throw [System.ArgumentException]::new('Start address must be less than or equal to end address.')
        }

        $this.StartAddress = $startAddress
        $this.EndAddress = $endAddress
        $this.MustSucceed = $mustSucceed
    }
}

# Represents the usable address range that should be handed out by a DHCP scope.
class DhcpRange {
    [IPv4Address] $StartAddress
    [IPv4Address] $EndAddress
    [IPv4Address] $GatewayAddress
    [IPv4Address] $BroadcastAddress
    [int] $ReservedAfterGateway

    DhcpRange(
        [IPv4Address] $startAddress,
        [IPv4Address] $endAddress,
        [IPv4Address] $gatewayAddress,
        [IPv4Address] $broadcastAddress,
        [int] $reservedAfterGateway
    ) {
        if ($null -eq $startAddress) { throw [System.ArgumentNullException]::new('startAddress') }
        if ($null -eq $endAddress) { throw [System.ArgumentNullException]::new('endAddress') }
        if ($null -eq $gatewayAddress) { throw [System.ArgumentNullException]::new('gatewayAddress') }
        if ($null -eq $broadcastAddress) { throw [System.ArgumentNullException]::new('broadcastAddress') }
        if ($startAddress.GetUInt32() -gt $endAddress.GetUInt32()) {
            throw [System.ArgumentException]::new('StartAddress must be less than or equal to EndAddress.')
        }

        $this.StartAddress = $startAddress
        $this.EndAddress = $endAddress
        $this.GatewayAddress = $gatewayAddress
        $this.BroadcastAddress = $broadcastAddress
        $this.ReservedAfterGateway = $reservedAfterGateway
    }

    static [DhcpRange] FromSubnet([IPv4Subnet] $subnet, [string] $dhcpType) {
        if ($null -eq $subnet) {
            throw [System.ArgumentNullException]::new('subnet')
        }

        if ([string]::IsNullOrWhiteSpace($dhcpType)) {
            throw [System.ArgumentException]::new('dhcpType is required.')
        }

        $hostBits = 32 - $subnet.PrefixLength
        $totalAddresses = [uint32] [math]::Pow(2, $hostBits)

        $networkNumber = $subnet.NetworkAddress.GetUInt32()
        $broadcastNumber = [uint32] ($networkNumber + $totalAddresses - 1)
        $gatewayNumber = [uint32] ($broadcastNumber - 1)
        $reservedCount = 0

        if ($subnet.PrefixLength -ge 22 -and $subnet.PrefixLength -le 25) {
            $reservedCount = 5
        }

        $startNumber = [uint32] ($networkNumber + 1)
        $endNumber = [uint32] ($gatewayNumber - $reservedCount - 1)

        if ($dhcpType -eq 'dhcp_static') {
            $endNumber = $startNumber
        }

        return [DhcpRange]::new(
            [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($startNumber)),
            [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($endNumber)),
            [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($gatewayNumber)),
            [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($broadcastNumber)),
            $reservedCount
        )
    }
}

# Maps a NetBox prefix payload into the domain shape required for prefix onboarding.
class PrefixWorkItem {
    [int] $Id
    [IPv4Subnet] $PrefixSubnet
    [string] $Description
    [string] $DHCPType
    [string] $Domain
    [string] $SiteName
    [int] $SiteId
    [int] $DefaultGatewayId
    [IPv4Address] $DefaultGatewayAddress
    [string] $DnsName
    [string] $ValuemationSiteMandant
    [string] $ExistingTicketUrl

    PrefixWorkItem(
        [int] $id,
        [string] $prefix,
        [string] $description,
        [string] $dhcpType,
        [string] $domain,
        [string] $siteName,
        [int] $siteId,
        [int] $defaultGatewayId,
        [string] $defaultGatewayAddress,
        [string] $dnsName,
        [string] $valuemationSiteMandant,
        [string] $existingTicketUrl
    ) {
        if ($id -le 0) { throw [System.ArgumentOutOfRangeException]::new('id', 'Id must be positive.') }
        if ([string]::IsNullOrWhiteSpace($description)) { throw [System.ArgumentException]::new('Description is required.') }
        if ([string]::IsNullOrWhiteSpace($dhcpType)) { throw [System.ArgumentException]::new('DHCPType is required.') }
        if ([string]::IsNullOrWhiteSpace($domain)) { throw [System.ArgumentException]::new('Domain is required.') }
        if ([string]::IsNullOrWhiteSpace($siteName)) { throw [System.ArgumentException]::new('SiteName is required.') }
        if ($siteId -le 0) { throw [System.ArgumentOutOfRangeException]::new('siteId', 'SiteId must be positive.') }
        if ($defaultGatewayId -le 0) { throw [System.ArgumentOutOfRangeException]::new('defaultGatewayId', 'DefaultGatewayId must be positive.') }
        if ([string]::IsNullOrWhiteSpace($dnsName)) { throw [System.ArgumentException]::new('DnsName is required.') }
        if ([string]::IsNullOrWhiteSpace($valuemationSiteMandant)) { throw [System.ArgumentException]::new('ValuemationSiteMandant is required.') }

        $this.Id = $id
        $this.PrefixSubnet = [IPv4Subnet]::new($prefix)
        $this.Description = $description.Trim()
        $this.DHCPType = $dhcpType.Trim()
        $this.Domain = $domain.Trim().ToLowerInvariant()
        $this.SiteName = $siteName.Trim()
        $this.SiteId = $siteId
        $this.DefaultGatewayId = $defaultGatewayId
        $this.DefaultGatewayAddress = [IPv4Address]::new($defaultGatewayAddress)
        $this.DnsName = $dnsName.Trim()
        $this.ValuemationSiteMandant = $valuemationSiteMandant.Trim()
        $this.ExistingTicketUrl = $existingTicketUrl
    }

    [string] GetGatewayFqdn() {
        if ($this.DnsName.ToLowerInvariant().EndsWith($this.Domain.ToLowerInvariant())) {
            return $this.DnsName
        }

        return '{0}.{1}' -f $this.DnsName, $this.Domain
    }

    [string] GetIdentifier() {
        return $this.PrefixSubnet.Cidr
    }
}

# Maps a NetBox IP address payload into the domain shape required for DNS lifecycle processing.
class IpAddressWorkItem {
    [int] $Id
    [IPv4Address] $IpAddress
    [string] $Status
    [string] $DnsName
    [string] $Domain
    [IPv4Subnet] $PrefixSubnet

    IpAddressWorkItem(
        [int] $id,
        [string] $ipAddress,
        [string] $status,
        [string] $dnsName,
        [string] $domain,
        [string] $prefix
    ) {
        if ($id -le 0) { throw [System.ArgumentOutOfRangeException]::new('id', 'Id must be positive.') }
        if ([string]::IsNullOrWhiteSpace($status)) { throw [System.ArgumentException]::new('Status is required.') }
        if ([string]::IsNullOrWhiteSpace($domain)) { throw [System.ArgumentException]::new('Domain is required.') }
        if ([string]::IsNullOrWhiteSpace($prefix)) { throw [System.ArgumentException]::new('Prefix is required.') }

        $this.Id = $id
        $this.IpAddress = [IPv4Address]::new($ipAddress)
        $this.Status = $status.Trim()
        $this.DnsName = $dnsName
        $this.Domain = $domain.Trim().ToLowerInvariant()
        $this.PrefixSubnet = [IPv4Subnet]::new($prefix)
    }

    [string] GetIdentifier() {
        return $this.IpAddress.Value
    }

    [string] GetFqdn() {
        if ([string]::IsNullOrWhiteSpace($this.DnsName)) {
            return $null
        }

        if ($this.DnsName.ToLowerInvariant().EndsWith($this.Domain)) {
            return $this.DnsName
        }

        return '{0}.{1}' -f $this.DnsName, $this.Domain
    }
}

# Converts a prefix work item into the DHCP-specific configuration needed by the infrastructure adapter.
class DhcpScopeDefinition {
    [string] $Name
    [IPv4Subnet] $Subnet
    [string] $SubnetMask
    [DhcpRange] $Range
    [string] $DnsDomain
    [int] $LeaseDurationDays
    [bool] $ConfigureDynamicDns
    [DhcpExclusionRange[]] $ExclusionRanges

    DhcpScopeDefinition(
        [string] $name,
        [IPv4Subnet] $subnet,
        [string] $subnetMask,
        [DhcpRange] $range,
        [string] $dnsDomain,
        [int] $leaseDurationDays,
        [bool] $configureDynamicDns,
        [DhcpExclusionRange[]] $exclusionRanges
    ) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw [System.ArgumentException]::new('Name is required.') }
        if ($null -eq $subnet) { throw [System.ArgumentNullException]::new('subnet') }
        if ([string]::IsNullOrWhiteSpace($subnetMask)) { throw [System.ArgumentException]::new('SubnetMask is required.') }
        if ($null -eq $range) { throw [System.ArgumentNullException]::new('range') }
        if ([string]::IsNullOrWhiteSpace($dnsDomain)) { throw [System.ArgumentException]::new('DnsDomain is required.') }

        $this.Name = $name
        $this.Subnet = $subnet
        $this.SubnetMask = $subnetMask
        $this.Range = $range
        $this.DnsDomain = $dnsDomain
        $this.LeaseDurationDays = $leaseDurationDays
        $this.ConfigureDynamicDns = $configureDynamicDns
        $this.ExclusionRanges = $exclusionRanges
    }

    static [DhcpScopeDefinition] FromPrefixWorkItem([PrefixWorkItem] $workItem) {
        if ($null -eq $workItem) {
            throw [System.ArgumentNullException]::new('workItem')
        }

        $mappedType = ''
        switch ($workItem.DHCPType) {
            'dhcp_static' { $mappedType = 'STATIC' }
            'dhcp_dynamic' { $mappedType = 'DYNAMIC' }
            'no_dhcp' { $mappedType = 'NODHCP' }
            default { throw [System.InvalidOperationException]::new("Unsupported DHCP type '$($workItem.DHCPType)'.") }
        }

        $scopeName = '{0} {1} {2} {3}' -f $mappedType, $workItem.PrefixSubnet.Cidr, $workItem.SiteName, $workItem.Description
        $calculatedRange = [DhcpRange]::FromSubnet($workItem.PrefixSubnet, $workItem.DHCPType)
        $exclusions = @()
        $strictDynamicExclusions = $workItem.PrefixSubnet.PrefixLength -eq 24

        if ($workItem.DHCPType -eq 'dhcp_static') {
            $exclusions += [DhcpExclusionRange]::new($calculatedRange.StartAddress, $calculatedRange.EndAddress, $true)
        }
        elseif ($workItem.DHCPType -eq 'dhcp_dynamic' -and $workItem.PrefixSubnet.PrefixLength -le 24) {
            foreach ($blockBase in $workItem.PrefixSubnet.Get24BlockBaseAddresses()) {
                $blockAddress = [IPv4Address]::new($blockBase)
                $blockNumber = $blockAddress.GetUInt32()
                $exclusions += [DhcpExclusionRange]::new(
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($blockNumber)),
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32($blockNumber)),
                    $strictDynamicExclusions
                )
                $exclusions += [DhcpExclusionRange]::new(
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32([uint32] ($blockNumber + 1))),
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32([uint32] ($blockNumber + 1))),
                    $strictDynamicExclusions
                )
                $exclusions += [DhcpExclusionRange]::new(
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32([uint32] ($blockNumber + 249))),
                    [IPv4Address]::new([IPv4Address]::ConvertFromUInt32([uint32] ($blockNumber + 255))),
                    $strictDynamicExclusions
                )
            }
        }

        return [DhcpScopeDefinition]::new(
            $scopeName,
            $workItem.PrefixSubnet,
            $workItem.PrefixSubnet.GetSubnetMaskString(),
            $calculatedRange,
            $workItem.Domain,
            3,
            $workItem.DHCPType -eq 'dhcp_dynamic',
            $exclusions
        )
    }
}

# Captures the result of prerequisite checks before a prefix can move into provisioning.
class PrerequisiteEvaluation {
    [bool] $CanContinue
    [bool] $RequiresNewJiraTicket
    [bool] $RequiresExistingJiraWait
    [bool] $HasAdSite
    [bool] $HasMatchingMandant
    [bool] $HasReverseZone
    [bool] $HasDnsDelegation
    [string] $ObservedAdSite
    [string] $ReverseZoneName
    [string[]] $Reasons

    PrerequisiteEvaluation() {
        $this.CanContinue = $false
        $this.RequiresNewJiraTicket = $false
        $this.RequiresExistingJiraWait = $false
        $this.HasAdSite = $false
        $this.HasMatchingMandant = $false
        $this.HasReverseZone = $false
        $this.HasDnsDelegation = $false
        $this.Reasons = @()
    }

    [void] AddReason([string] $reason) {
        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            $this.Reasons = @($this.Reasons + $reason)
        }
    }
}

# Stores a username and secure password for external system access.
class AutomationCredential {
    [string] $Name
    [string] $Appliance
    [securestring] $ApiKey

    AutomationCredential([string] $name, [string] $appliance, [securestring] $apiKey) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw [System.ArgumentException]::new('Name is required.') }
        if ([string]::IsNullOrWhiteSpace($appliance)) { throw [System.ArgumentException]::new('Appliance is required.') }
        if ($null -eq $apiKey) { throw [System.ArgumentNullException]::new('apiKey') }

        $this.Name = $name
        $this.Appliance = $appliance
        $this.ApiKey = $apiKey
    }

    [string] GetPlainApiKey() {
        $pointer = [System.IntPtr]::Zero
        try {
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.ApiKey)
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        }
        finally {
            if ($pointer -ne [System.IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
            }
        }
    }
}

# Bundles resolved DNS execution dependencies so downstream services do not repeat lookups.
class DnsExecutionContext {
    [string] $DomainController
    [string] $ReverseZone

    DnsExecutionContext([string] $domainController, [string] $reverseZone) {
        if ([string]::IsNullOrWhiteSpace($domainController)) {
            throw [System.ArgumentException]::new('DomainController is required.')
        }

        if ([string]::IsNullOrWhiteSpace($reverseZone)) {
            throw [System.ArgumentException]::new('ReverseZone is required.')
        }

        $this.DomainController = $domainController
        $this.ReverseZone = $reverseZone
    }
}

# Reads flat key-value automation settings from the relative environment file.
class EnvFileConfigurationProvider {
    [string] $Path
    [hashtable] $Values

    EnvFileConfigurationProvider([string] $filePath) {
        if ([string]::IsNullOrWhiteSpace($filePath)) {
            $filePath = '.env'
        }

        $this.Path = $filePath
        $this.Values = @{}

        if (Test-Path -Path $this.Path) {
            foreach ($line in Get-Content -Path $this.Path) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line.TrimStart().StartsWith('#')) { continue }

                $parts = $line -split '=', 2
                if ($parts.Count -eq 2) {
                    $key = $parts[0].Trim()
                    $value = $parts[1].Trim()
                    $this.Values[$key] = $value
                }
            }
        }
    }

    [string] GetValue([string] $keyName, [string] $description) {
        if ([string]::IsNullOrWhiteSpace($keyName)) {
            throw [System.ArgumentException]::new('KeyName is required.')
        }

        if (-not $this.Values.ContainsKey($keyName)) {
            throw [System.InvalidOperationException]::new("Environment value '$keyName' is missing. $description")
        }

        return [string] $this.Values[$keyName]
    }

    [string[]] GetStringArray([string] $keyName, [string] $description) {
        $rawValue = $this.GetValue($keyName, $description)
        return @($rawValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
}

# Loads persisted secure credential files and converts them into automation credentials.
class SecureFileCredentialProvider {
    [string] $BasePath

    SecureFileCredentialProvider([string] $credentialBasePath) {
        if ([string]::IsNullOrWhiteSpace($credentialBasePath)) {
            $credentialBasePath = '.secureCreds'
        }

        $this.BasePath = $credentialBasePath

        if (-not (Test-Path -Path $this.BasePath)) {
            New-Item -Path $this.BasePath -ItemType Directory | Out-Null
        }
    }

    [AutomationCredential] GetApiCredential([string] $credentialName) {
        if ([string]::IsNullOrWhiteSpace($credentialName)) {
            throw [System.ArgumentException]::new('CredentialName is required.')
        }

        $path = Join-Path -Path $this.BasePath -ChildPath ('{0}.xml' -f $credentialName)
        $loaded = $null

        if (Test-Path -Path $path) {
            try {
                $loaded = Import-Clixml -Path $path
            }
            catch {
                throw [System.InvalidOperationException]::new(
                    ("Credential file '{0}' could not be read. Recreate the file or fix access permissions. {1}" -f $path, $_.Exception.Message)
                )
            }
        }

        if ($null -ne $loaded) {
            if ($loaded.Appliance -and $loaded.ApiKey) {
                return [AutomationCredential]::new($credentialName, $loaded.Appliance, $loaded.ApiKey)
            }

            throw [System.InvalidOperationException]::new(
                ("Credential file '{0}' is missing required fields 'Appliance' and/or 'ApiKey'." -f $path)
            )
        }

        $appliance = Read-Host ('Enter appliance/base URL for {0}' -f $credentialName)
        $apiKey = Read-Host ('Enter API key for {0}' -f $credentialName) -AsSecureString

        $record = [pscustomobject]@{
            Appliance = $appliance
            ApiKey    = $apiKey
        }

        $record | Export-Clixml -Path $path

        return [AutomationCredential]::new($credentialName, $appliance, $apiKey)
    }
}

# Wraps NetBox API access and shields the application layer from raw REST details.
class NetBoxClient {
    [string] $BaseUrl
    [AutomationCredential] $Credential

    NetBoxClient([AutomationCredential] $credential) {
        if ($null -eq $credential) {
            throw [System.ArgumentNullException]::new('credential')
        }

        $this.Credential = $credential
        $this.BaseUrl = $credential.Appliance.TrimEnd('/')
    }

    hidden [hashtable] GetJsonHeaders() {
        return @{
            Authorization = ('Token {0}' -f $this.Credential.GetPlainApiKey())
            Accept        = 'application/json'
            'Content-Type' = 'application/json'
        }
    }

    hidden [string] BuildQueryString([hashtable] $filter) {
        if ($null -eq $filter -or $filter.Count -eq 0) {
            return ''
        }

        $parts = @()
        foreach ($key in $filter.Keys) {
            $value = $filter[$key]
            if ($null -eq $value) { continue }

            if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                foreach ($item in $value) {
                    if ($null -ne $item) {
                        $parts += '{0}={1}' -f [uri]::EscapeDataString([string] $key), [uri]::EscapeDataString([string] $item)
                    }
                }
            }
            else {
                $parts += '{0}={1}' -f [uri]::EscapeDataString([string] $key), [uri]::EscapeDataString([string] $value)
            }
        }

        return ($parts -join '&')
    }

    hidden [object[]] GetPaged([string] $relativePath, [hashtable] $filter) {
        $headers = $this.GetJsonHeaders()
        $queryString = $this.BuildQueryString($filter)
        $uri = '{0}{1}' -f $this.BaseUrl, $relativePath

        if (-not [string]::IsNullOrWhiteSpace($queryString)) {
            if ($uri.Contains('?')) {
                $uri = '{0}&{1}' -f $uri, $queryString
            }
            else {
                $uri = '{0}?{1}' -f $uri, $queryString
            }
        }

        $results = @()
        $nextUri = $uri

        while (-not [string]::IsNullOrWhiteSpace($nextUri)) {
            $response = Invoke-RestMethod -Uri $nextUri -Method Get -Headers $headers -ErrorAction Stop
            $results += @($response.results)
            $nextUri = $response.next
        }

        return $results
    }

    hidden [pscustomobject] GetIpAddressById([int] $ipAddressId) {
        $uri = '{0}/api/ipam/ip-addresses/{1}/' -f $this.BaseUrl, $ipAddressId
        return Invoke-RestMethod -Uri $uri -Method Get -Headers $this.GetJsonHeaders() -ErrorAction Stop
    }

    hidden [pscustomobject] GetSiteById([int] $siteId) {
        $uri = '{0}/api/dcim/sites/{1}/' -f $this.BaseUrl, $siteId
        return Invoke-RestMethod -Uri $uri -Method Get -Headers $this.GetJsonHeaders() -ErrorAction Stop
    }

    [PrefixWorkItem[]] GetOpenPrefixWorkItems([EnvironmentContext] $environment) {
        $filter = @{
            status    = 'onboarding_open_dns_dhcp'
            cf_domain = $environment.DnsZone
        }

        $prefixes = $this.GetPaged('/api/ipam/prefixes/', $filter)
        $workItems = @()

        foreach ($prefix in $prefixes) {
            $defaultGateway = $this.GetIpAddressById([int] $prefix.custom_fields.default_gateway.id)
            $site = $this.GetSiteById([int] $prefix.scope.id)

            $workItems += [PrefixWorkItem]::new(
                [int] $prefix.id,
                [string] $prefix.prefix,
                [string] $prefix.description,
                [string] $prefix.custom_fields.dhcp_type,
                [string] $prefix.custom_fields.domain,
                [string] $prefix.scope.name,
                [int] $prefix.scope.id,
                [int] $prefix.custom_fields.default_gateway.id,
                [string] (($defaultGateway.address -split '/')[0]),
                [string] $defaultGateway.dns_name,
                [string] $site.custom_fields.valuemation_site_mandant,
                [string] $prefix.custom_fields.ad_sites_and_services_ticket_url
            )
        }

        return $workItems
    }

    hidden [pscustomobject] GetMostSpecificPrefixForAddress([string] $address) {
        $filter = @{ contains = $address; limit = 0 }
        $prefixes = $this.GetPaged('/api/ipam/prefixes/', $filter)
        if (-not $prefixes) {
            return $null
        }

        return $prefixes |
            Sort-Object -Property @{ Expression = { [int] (($_.prefix -split '/')[1]) } } -Descending |
            Select-Object -First 1
    }

    [IpAddressWorkItem[]] GetIpWorkItems([EnvironmentContext] $environment, [string[]] $statuses) {
        $filter = @{ status = $statuses }
        $ipAddresses = $this.GetPaged('/api/ipam/ip-addresses/', $filter)
        $workItems = @()

        foreach ($ipAddress in $ipAddresses) {
            $hostIp = ($ipAddress.address -split '/')[0]
            $prefix = $this.GetMostSpecificPrefixForAddress($hostIp)
            if ($null -eq $prefix) {
                continue
            }

            $domain = [string] $prefix.custom_fields.domain
            if ([string]::IsNullOrWhiteSpace($domain)) {
                continue
            }

            if ($domain.ToLowerInvariant() -ne $environment.DnsZone.ToLowerInvariant()) {
                continue
            }

            $workItems += [IpAddressWorkItem]::new(
                [int] $ipAddress.id,
                $hostIp,
                [string] $ipAddress.status.value,
                [string] $ipAddress.dns_name,
                $domain,
                [string] $prefix.prefix
            )
        }

        return $workItems
    }

    [void] UpdatePrefixTicketUrl([int] $prefixId, [string] $ticketUrl) {
        $uri = '{0}/api/ipam/prefixes/{1}/' -f $this.BaseUrl, $prefixId
        $body = @{
            custom_fields = @{
                ad_sites_and_services_ticket_url = $ticketUrl
            }
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $uri -Method Patch -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    [void] MarkPrefixOnboardingDone([int] $prefixId) {
        $uri = '{0}/api/ipam/prefixes/{1}/' -f $this.BaseUrl, $prefixId
        $body = @{ status = 'onboarding_done_dns_dhcp' } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri $uri -Method Patch -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    [void] UpdateIpStatus([int] $ipId, [string] $status) {
        $uri = '{0}/api/ipam/ip-addresses/{1}/' -f $this.BaseUrl, $ipId
        $body = @{ status = $status } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri $uri -Method Patch -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    [void] AddJournalEntry([string] $targetType, [int] $targetId, [string] $message, [string] $kind) {
        $contentTypeMap = @{
            Prefix    = 'ipam.prefix'
            IPAddress = 'ipam.ipaddress'
        }

        $uri = '{0}/api/extras/journal-entries/' -f $this.BaseUrl
        $body = @{
            assigned_object_type = $contentTypeMap[$targetType]
            assigned_object_id   = $targetId
            comments             = $message
            kind                 = $kind
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $uri -Method Post -Headers $this.GetJsonHeaders() -Body $body -ErrorAction Stop | Out-Null
    }

    [string] GetPrefixUrl([int] $prefixId) {
        return '{0}/ipam/prefixes/{1}/' -f $this.BaseUrl, $prefixId
    }

    [string] GetIpAddressUrl([int] $ipAddressId) {
        return '{0}/ipam/ip-addresses/{1}/' -f $this.BaseUrl, $ipAddressId
    }
}

# Wraps Jira issue creation and workflow transitions used for manual prerequisite handling.
class JiraClient {
    [string] $BaseUrl
    [AutomationCredential] $Credential

    JiraClient([AutomationCredential] $credential) {
        if ($null -eq $credential) {
            throw [System.ArgumentNullException]::new('credential')
        }

        $this.Credential = $credential
        $this.BaseUrl = $credential.Appliance.TrimEnd('/')
    }

    hidden [hashtable] GetHeaders() {
        return @{
            Authorization = ('Bearer {0}' -f $this.Credential.GetPlainApiKey())
            Accept        = 'application/json'
        }
    }

    [string] GetTicketKeyFromUrl([string] $jiraUrl) {
        if ([string]::IsNullOrWhiteSpace($jiraUrl)) {
            throw [System.ArgumentException]::new('JiraUrl is required.')
        }

        $pattern = 'browse/([A-Z]+-\d+)'
        if ($jiraUrl -match $pattern) {
            return $matches[1]
        }

        throw [System.ArgumentException]::new("No valid Jira ticket key found in '$jiraUrl'.")
    }

    [string] GetTicketStatus([string] $ticketKey) {
        $uri = '{0}/rest/api/2/issue/{1}' -f $this.BaseUrl, $ticketKey
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $this.GetHeaders() -ContentType 'application/json; charset=utf-8' -ErrorAction Stop
        return [string] $response.fields.status.name
    }

    [void] SetTicketStatus([string] $ticketKey, [string] $targetStatus) {
        $transitionsUri = '{0}/rest/api/2/issue/{1}/transitions?expand=transitions.fields' -f $this.BaseUrl, $ticketKey
        $transitionResponse = Invoke-RestMethod -Uri $transitionsUri -Method Get -Headers $this.GetHeaders() -ContentType 'application/json; charset=utf-8' -ErrorAction Stop
        $transition = $transitionResponse.transitions | Where-Object { $_.name -eq $targetStatus } | Select-Object -First 1

        if ($null -eq $transition) {
            throw [System.InvalidOperationException]::new("Target status '$targetStatus' is not available for ticket '$ticketKey'.")
        }

        $body = @{
            transition = @{
                id = [string] $transition.id
            }
        } | ConvertTo-Json -Depth 10

        $postUri = '{0}/rest/api/2/issue/{1}/transitions' -f $this.BaseUrl, $ticketKey
        Invoke-RestMethod -Uri $postUri -Method Post -Headers $this.GetHeaders() -ContentType 'application/json; charset=utf-8' -Body $body -ErrorAction Stop | Out-Null
    }

    [void] EnsureTicketClosed([string] $jiraUrl) {
        $ticketKey = $this.GetTicketKeyFromUrl($jiraUrl)
        $status = $this.GetTicketStatus($ticketKey)

        if ($status -eq 'Verify') {
            $this.SetTicketStatus($ticketKey, 'Close')
            return
        }

        if ($status -ne 'Geschlossen') {
            throw [System.InvalidOperationException]::new("Jira ticket '$ticketKey' is not closed. Current status: '$status'.")
        }
    }

    [string] CreatePrerequisiteTicket([PrefixWorkItem] $workItem, [string] $forestShortName, [bool] $dnsZoneDelegated) {
        $delegationText = 'nicht vorhanden'
        if ($dnsZoneDelegated) {
            $delegationText = 'vorhanden'
        }

        $networkIp = $workItem.PrefixSubnet.NetworkAddress.Value
        $networkMask = $workItem.PrefixSubnet.PrefixLength

        $description = @"
||Subnetz ID||Prefix ||Forest (MTU, MTUDEV, MTUGOV, MTUCHINA)||Site Zuordnung||Windows/Linux||Delegation ||
|$networkIp|/$networkMask| $forestShortName | $($workItem.SiteName) | unbekannt | $delegationText |
Confluence Doku:
[Tier0-Operations CR Ticket erstellen - Tier0-CAS-Operations - MTU Confluence (dasa.de)|https://cpwa-confluence-p.muc.mtu.dasa.de:8453/display/TCO/Tier0-Operations+CR+Ticket+erstellen]
"@

        $body = @{
            fields = @{
                project = @{ key = 'TCO' }
                summary = 'DNS-Zonen pflegen - Reverse Lookup Zone anlegen / Sites und Services pflegen'
                description = $description
                issuetype = @{ name = 'Story' }
                labels = @('FIPI-Abnahme-nicht-benötigt', 'FIPI-Freigabe-nicht-benötigt', 'Tier0-Operations')
                assignee = @{ name = 'YAT5495' }
            }
        } | ConvertTo-Json -Depth 10

        $createUri = '{0}/rest/api/2/issue/' -f $this.BaseUrl
        $ticket = Invoke-RestMethod -Uri $createUri -Method Post -Headers $this.GetHeaders() -Body $body -ContentType 'application/json; charset=utf-8' -ErrorAction Stop

        $ticketKey = [string] $ticket.key
        if ([string]::IsNullOrWhiteSpace($ticketKey)) {
            throw [System.InvalidOperationException]::new('Jira did not return a ticket key.')
        }

        $this.SetTicketStatus($ticketKey, 'Commit')
        return '{0}/browse/{1}' -f $this.BaseUrl, $ticketKey
    }
}

# Isolates Active Directory lookups behind a testable adapter boundary.
class ActiveDirectoryAdapter {
    [string] GetDomainControllerName() {
        return [string] (Get-ADDomainController).Name
    }

    [string] GetDomainDnsRoot() {
        return [string] (Get-ADDomain).DNSRoot
    }

    [string] GetForestShortName([string] $domain) {
        $forest = Get-ADForest -Server $domain
        $shortName = $null
        switch ($forest.Name.ToLowerInvariant()) {
            'mtu.corp' { $shortName = 'MTU' }
            'mtudev.corp' { $shortName = 'MTUDEV' }
            'ads.mtugov.de' { $shortName = 'MTUGOV' }
            'ads.mtuchina.app' { $shortName = 'MTUCHINA' }
            default { $shortName = [string] $forest.Name }
        }

        return $shortName
    }

    [string] GetSubnetSite([IPv4Subnet] $subnet, [string] $domainController) {
        foreach ($candidate in $subnet.GetAdLookupCandidates()) {
            try {
                $entry = Get-ADReplicationSubnet -Server $domainController -Filter ("Name -eq '{0}'" -f $candidate) -ErrorAction Stop
            }
            catch {
                continue
            }

            if ($null -ne $entry) {
                foreach ($item in @($entry)) {
                    if ($item.Site) {
                        return (($item.Site -split ',')[0] -replace '^CN=')
                    }
                }
            }
        }

        return $null
    }
}

# Isolates DNS server queries and record management behind a testable adapter boundary.
class DnsServerAdapter {
    [string] FindBestReverseZoneName([IPv4Subnet] $subnet, [string] $dnsComputerName) {
        $zoneName = $subnet.GetReverseZoneName()
        $reverseZones = Get-DnsServerZone -ComputerName $dnsComputerName -ErrorAction Stop | Where-Object { $_.IsReverseLookupZone -eq $true }
        $matchedZone = $null

        foreach ($zone in $reverseZones) {
            if ($zone.ZoneName -ieq $zoneName) {
                return [string] $zone.ZoneName
            }

            $zoneLabels = $zone.ZoneName -split '\.'
            $targetLabels = $zoneName -split '\.'
            if ($targetLabels.Length -ge $zoneLabels.Length) {
                $endingLabels = $targetLabels[-$zoneLabels.Length..-1]
                if (($endingLabels -join '.') -ieq $zone.ZoneName) {
                    if ($null -eq $matchedZone -or $zoneLabels.Length -gt (($matchedZone.ZoneName -split '\.').Length)) {
                        $matchedZone = $zone
                    }
                }
            }
        }

        if ($null -eq $matchedZone) {
            return $null
        }

        return [string] $matchedZone.ZoneName
    }

    [bool] TestReverseZoneDelegation([IPv4Subnet] $subnet, [string] $domain) {
        $prefix = $subnet.PrefixLength
        while ($prefix -ge 8) {
            $candidateSubnet = [IPv4Subnet]::new('{0}/{1}' -f $subnet.NetworkAddress.Value, $prefix)
            $reverseZone = $candidateSubnet.GetReverseZoneName()

            try {
                $nsResult = Resolve-DnsName -Name $reverseZone -Type NS -ErrorAction SilentlyContinue
            }
            catch {
                $nsResult = $null
            }

            foreach ($record in @($nsResult)) {
                if ($record.NameHost -and $record.NameHost.ToLowerInvariant().EndsWith('.{0}' -f $domain.ToLowerInvariant())) {
                    return $true
                }
            }

            $prefix -= 8
        }

        return $false
    }

    hidden [string] GetRelativeDnsName([string] $dnsName, [string] $dnsZone) {
        if ($dnsName.ToLowerInvariant().EndsWith('.{0}' -f $dnsZone.ToLowerInvariant())) {
            return ($dnsName -replace ('\.{0}$' -f [regex]::Escape($dnsZone)), '')
        }

        return $dnsName
    }

    hidden [string] GetPtrOwnerName([string] $reverseZone, [IPv4Address] $ipAddress) {
        $zonePart = ($reverseZone.TrimEnd('.').ToLowerInvariant() -replace '\.?in-addr\.arpa$', '').Trim('.')
        $labels = @()
        if (-not [string]::IsNullOrWhiteSpace($zonePart)) {
            $labels = @($zonePart.Split('.') | Where-Object { $_ })
        }

        $octets = $ipAddress.Value.Split('.')
        $ownerName = $null
        switch ($labels.Count) {
            1 { $ownerName = '{0}.{1}.{2}' -f $octets[3], $octets[2], $octets[1] }
            2 { $ownerName = '{0}.{1}' -f $octets[3], $octets[2] }
            3 { $ownerName = '{0}' -f $octets[3] }
            default { throw [System.InvalidOperationException]::new("Unsupported reverse zone '$reverseZone'.") }
        }

        return $ownerName
    }

    [void] RemoveDnsRecordsForIp([string] $dnsServer, [string] $dnsZone, [string] $reverseZone, [IPv4Address] $ipAddress) {
        $ipValue = $ipAddress.Value

        $matchingARecords = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $dnsZone -RRType A -ErrorAction SilentlyContinue |
            Where-Object { $_.RecordData.IPv4Address.IPAddressToString -eq $ipValue }

        foreach ($record in @($matchingARecords)) {
            Remove-DnsServerResourceRecord -ZoneName $dnsZone -Name $record.HostName -RRType A -RecordData $ipValue -ComputerName $dnsServer -Force -ErrorAction Stop
        }

        $ptrOwnerName = $this.GetPtrOwnerName($reverseZone, $ipAddress)
        $matchingPtrRecords = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $reverseZone -RRType PTR -ErrorAction SilentlyContinue |
            Where-Object { $_.HostName -eq $ptrOwnerName }

        foreach ($ptrRecord in @($matchingPtrRecords)) {
            Remove-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $reverseZone -InputObject $ptrRecord -Force -ErrorAction Stop
        }
    }

    [void] EnsureDnsRecordsForIp(
        [string] $dnsServer,
        [string] $dnsZone,
        [string] $dnsName,
        [IPv4Address] $ipAddress,
        [string] $reverseZone,
        [string] $ptrDomainName
    ) {
        $relativeDnsName = $this.GetRelativeDnsName($dnsName, $dnsZone)
        $this.RemoveDnsRecordsForIp($dnsServer, $dnsZone, $reverseZone, $ipAddress)

        $existingARecord = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $dnsZone -Name $relativeDnsName -RRType A -ErrorAction SilentlyContinue
        if (-not $existingARecord) {
            Add-DnsServerResourceRecordA -ComputerName $dnsServer -ZoneName $dnsZone -Name $relativeDnsName -IPv4Address $ipAddress.Value -ErrorAction Stop
        }

        $ptrOwnerName = $this.GetPtrOwnerName($reverseZone, $ipAddress)
        $existingPtrRecord = Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $reverseZone -Name $ptrOwnerName -RRType PTR -ErrorAction SilentlyContinue
        if (-not $existingPtrRecord) {
            Add-DnsServerResourceRecordPtr -ComputerName $dnsServer -ZoneName $reverseZone -Name $ptrOwnerName -PtrDomainName $ptrDomainName -ErrorAction Stop
        }
    }
}

# Isolates DHCP server discovery and scope provisioning behind a testable adapter boundary.
class DhcpServerAdapter {
    hidden [string] GetSitePattern([string] $site, [bool] $isDevelopment) {
        $normalizedSite = $site.Trim().ToLowerInvariant()
        $pattern = $null
        switch ($normalizedSite) {
            'eme' { $pattern = 'e*' }
            'rze' { $pattern = 'r*' }
            'haj' { $pattern = 'h*' }
            'muc' { $pattern = 'm*' }
            'mal' { $pattern = 'm*' }
            'beg' { $pattern = 'o*' }
            'yvr' { $pattern = 'v*' }
            'lud' { $pattern = 'l*' }
            default { throw [System.InvalidOperationException]::new("Unsupported site '$site'.") }
        }

        if ($isDevelopment) {
            return 'dev{0}' -f $pattern
        }

        return $pattern
    }

    hidden [bool] IsPrimaryServer([string] $dhcpServer) {
        $result = Invoke-Command -ComputerName $dhcpServer -ScriptBlock {
            try {
                $value = Get-ItemProperty -Path 'HKLM:\SOFTWARE\ACW\DHCP' -Name 'Primary' -ErrorAction Stop
                return [bool] $value.Primary
            }
            catch {
                return $false
            }
        }

        return [bool] $result
    }

    hidden [string] GetCurrentDomainSuffix() {
        return [string] (Get-ADDomainController).Domain
    }

    [string] GetPrimaryServerForSite([string] $site, [bool] $isDevelopment) {
        $pattern = $this.GetSitePattern($site, $isDevelopment)
        $domainSuffix = $this.GetCurrentDomainSuffix()
        $servers = @(
            Get-DhcpServerInDC |
                Where-Object {
                    $_.DnsName -ilike $pattern -and
                    $_.DnsName.ToLowerInvariant().EndsWith($domainSuffix.ToLowerInvariant())
                } |
                Select-Object -ExpandProperty DnsName
        )

        if (-not $servers) {
            throw [System.InvalidOperationException]::new("No DHCP servers found for site '$site'.")
        }

        foreach ($server in $servers) {
            if ($this.IsPrimaryServer($server)) {
                return $server
            }
        }

        return [string] $servers[0]
    }

    [void] EnsureScope([string] $dhcpServer, [DhcpScopeDefinition] $definition) {
        $scopeId = $definition.Subnet.NetworkAddress.Value
        $existingScope = Get-DhcpServerv4Scope -ComputerName $dhcpServer -ScopeId $scopeId -ErrorAction SilentlyContinue

        if (-not $existingScope) {
            Add-DhcpServerv4Scope `
                -ComputerName $dhcpServer `
                -Name $definition.Name `
                -StartRange $definition.Range.StartAddress.Value `
                -EndRange $definition.Range.EndAddress.Value `
                -SubnetMask $definition.SubnetMask `
                -State Active `
                -LeaseDuration (New-TimeSpan -Days $definition.LeaseDurationDays) `
                -ErrorAction Stop
        }

        if ($definition.ConfigureDynamicDns) {
            Set-DhcpServerv4DnsSetting `
                -ComputerName $dhcpServer `
                -ScopeId $scopeId `
                -DynamicUpdates OnClientRequest `
                -DeleteDnsRRonLeaseExpiry $true `
                -UpdateDnsRRForOlderClients $true `
                -DisableDnsPtrRRUpdate $false `
                -ErrorAction Stop
        }

        Set-DhcpServerv4OptionValue -ComputerName $dhcpServer -ScopeId $scopeId -DnsDomain $definition.DnsDomain -Router $definition.Range.GatewayAddress.Value -ErrorAction Stop
        Set-DhcpServerv4OptionValue -ComputerName $dhcpServer -ScopeId $scopeId -OptionId 28 -Value $definition.Range.BroadcastAddress.Value -ErrorAction Stop

        foreach ($range in @($definition.ExclusionRanges)) {
            if ($range.MustSucceed) {
                Add-DhcpServerv4ExclusionRange `
                    -ComputerName $dhcpServer `
                    -ScopeId $scopeId `
                    -StartRange $range.StartAddress.Value `
                    -EndRange $range.EndAddress.Value `
                    -ErrorAction Stop | Out-Null
                continue
            }

            Add-DhcpServerv4ExclusionRange `
                -ComputerName $dhcpServer `
                -ScopeId $scopeId `
                -StartRange $range.StartAddress.Value `
                -EndRange $range.EndAddress.Value `
                -ErrorAction SilentlyContinue | Out-Null
        }
    }

    [void] EnsureScopeFailover([string] $dhcpServer, [IPv4Subnet] $subnet) {
        try {
            $failover = Get-DhcpServerv4Failover -ComputerName $dhcpServer -ErrorAction Stop | Select-Object -First 1
        }
        catch {
            return
        }

        if ($null -eq $failover -or [string]::IsNullOrWhiteSpace($failover.Name)) {
            return
        }

        Add-DhcpServerv4FailoverScope -ComputerName $dhcpServer -Name $failover.Name -ScopeId $subnet.NetworkAddress.Value -ErrorAction SilentlyContinue | Out-Null
    }

    [void] RemoveScope([string] $dhcpServer, [IPv4Subnet] $subnet) {
        throw [System.NotImplementedException]::new('Prefix decommissioning is intentionally not implemented yet.')
    }
}

# Wraps SMTP delivery for operational notifications.
class SmtpMailClient {
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter

    SmtpMailClient([ActiveDirectoryAdapter] $activeDirectoryAdapter) {
        if ($null -eq $activeDirectoryAdapter) {
            throw [System.ArgumentNullException]::new('activeDirectoryAdapter')
        }

        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
    }

    [void] SendHtmlMail([string[]] $recipients, [string] $subject, [string] $htmlBody) {
        if (-not $recipients) {
            return
        }

        $smtpServer = ('smtpmail.{0}' -f $this.ActiveDirectoryAdapter.GetDomainDnsRoot())
        Send-MailMessage -From 'reports@mtu.de' -To $recipients -Subject $subject -Body $htmlBody -BodyAsHtml -SmtpServer $smtpServer -ErrorAction Stop
    }
}

# Creates relative log paths and persists per-run or per-work-item text logs.
class WorkItemLogService {
    [string] $BasePath

    WorkItemLogService([string] $logBasePath) {
        if ([string]::IsNullOrWhiteSpace($logBasePath)) {
            $logBasePath = 'logs'
        }

        $this.BasePath = $logBasePath

        if (-not (Test-Path -Path $this.BasePath)) {
            New-Item -Path $this.BasePath -ItemType Directory -Force | Out-Null
        }
    }

    hidden [string] SanitizeIdentifier([string] $identifier) {
        if ([string]::IsNullOrWhiteSpace($identifier)) {
            return 'unknown'
        }

        $sanitized = $identifier -replace '[\\/:*?"<>|]', '_'
        $sanitized = $sanitized -replace '\s+', '_'
        return $sanitized
    }

    [string] CreateLogPath([string] $category, [string] $identifier) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $fileName = '{0}_{1}_{2}.log' -f $category, $this.SanitizeIdentifier($identifier), $timestamp
        return (Join-Path -Path $this.BasePath -ChildPath $fileName)
    }

    [void] WriteLog([string] $relativePath, [string[]] $lines) {
        $content = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
        Set-Content -Path $relativePath -Value $content -Encoding UTF8
    }
}

# Writes normalized journal entries back to NetBox targets.
class WorkItemJournalService {
    [NetBoxClient] $NetBoxClient

    WorkItemJournalService([NetBoxClient] $netBoxClient) {
        $this.NetBoxClient = $netBoxClient
    }

    hidden [string] JoinLines([string[]] $lines) {
        return ((@($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine) -replace [Environment]::NewLine, '<br>')
    }

    [void] WriteEntry([string] $targetType, [int] $targetId, [string[]] $lines, [string] $kind) {
        $this.NetBoxClient.AddJournalEntry($targetType, $targetId, $this.JoinLines($lines), $kind)
    }

    [void] WritePrefixInfo([PrefixWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('Prefix', $workItem.Id, $lines, 'info')
    }

    [void] WritePrefixError([PrefixWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('Prefix', $workItem.Id, $lines, 'danger')
    }

    [void] WriteIpInfo([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('IPAddress', $workItem.Id, $lines, 'info')
    }

    [void] WriteIpError([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $this.WriteEntry('IPAddress', $workItem.Id, $lines, 'danger')
    }
}

# Evaluates whether a prefix is ready for provisioning without performing side effects.
class PrerequisiteValidationService {
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter
    [DnsServerAdapter] $DnsServerAdapter
    [JiraClient] $JiraClient

    PrerequisiteValidationService(
        [ActiveDirectoryAdapter] $activeDirectoryAdapter,
        [DnsServerAdapter] $dnsServerAdapter,
        [JiraClient] $jiraClient
    ) {
        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
        $this.DnsServerAdapter = $dnsServerAdapter
        $this.JiraClient = $jiraClient
    }

    # Runs the prerequisite pipeline as a pure validation step so callers can decide how to react to blocked work.
    [PrerequisiteEvaluation] Evaluate([PrefixWorkItem] $workItem, [EnvironmentContext] $environment) {
        $evaluation = [PrerequisiteEvaluation]::new()
        $domainController = $this.ActiveDirectoryAdapter.GetDomainControllerName()
        $evaluation.ObservedAdSite = $this.ActiveDirectoryAdapter.GetSubnetSite($workItem.PrefixSubnet, $domainController)

        if ([string]::IsNullOrWhiteSpace($evaluation.ObservedAdSite)) {
            $evaluation.AddReason('Network is not assigned to any AD site.')
            $evaluation.RequiresNewJiraTicket = [string]::IsNullOrWhiteSpace($workItem.ExistingTicketUrl)
            $evaluation.RequiresExistingJiraWait = -not $evaluation.RequiresNewJiraTicket
            return $evaluation
        }

        $evaluation.HasAdSite = $true

        if ($evaluation.ObservedAdSite.ToUpperInvariant() -ne $workItem.ValuemationSiteMandant.ToUpperInvariant()) {
            $evaluation.AddReason("Network is assigned to AD site '$($evaluation.ObservedAdSite)', but expected '$($workItem.ValuemationSiteMandant)'.")
            return $evaluation
        }

        $evaluation.HasMatchingMandant = $true
        $evaluation.ReverseZoneName = $this.DnsServerAdapter.FindBestReverseZoneName($workItem.PrefixSubnet, $domainController)

        if ([string]::IsNullOrWhiteSpace($evaluation.ReverseZoneName)) {
            $evaluation.AddReason('Expected a reverse DNS zone, but none was found.')
            $evaluation.RequiresNewJiraTicket = [string]::IsNullOrWhiteSpace($workItem.ExistingTicketUrl)
            $evaluation.RequiresExistingJiraWait = -not $evaluation.RequiresNewJiraTicket
            return $evaluation
        }

        $evaluation.HasReverseZone = $true
        $evaluation.HasDnsDelegation = $this.DnsServerAdapter.TestReverseZoneDelegation($workItem.PrefixSubnet, $environment.GetDelegationValidationDomain())

        if (-not $evaluation.HasDnsDelegation) {
            $evaluation.AddReason('Expected a DNS delegation, but none was found.')
            $evaluation.RequiresNewJiraTicket = [string]::IsNullOrWhiteSpace($workItem.ExistingTicketUrl)
            $evaluation.RequiresExistingJiraWait = -not $evaluation.RequiresNewJiraTicket
            return $evaluation
        }

        if (-not [string]::IsNullOrWhiteSpace($workItem.ExistingTicketUrl)) {
            $this.JiraClient.EnsureTicketClosed($workItem.ExistingTicketUrl)
        }

        $evaluation.CanContinue = $true
        return $evaluation
    }
}

# Selects the target DHCP server for a prefix based on environment, site, and directory context.
class DhcpServerSelectionService {
    [DhcpServerAdapter] $DhcpServerAdapter

    DhcpServerSelectionService([DhcpServerAdapter] $dhcpServerAdapter) {
        $this.DhcpServerAdapter = $dhcpServerAdapter
    }

    [string] SelectServer([EnvironmentContext] $environment, [string] $adSite) {
        if ($environment.IsDevelopment()) {
            return $this.DhcpServerAdapter.GetPrimaryServerForSite('muc', $true)
        }

        if ($environment.IsTest()) {
            return $this.DhcpServerAdapter.GetPrimaryServerForSite('muc', $false)
        }

        return $this.DhcpServerAdapter.GetPrimaryServerForSite($adSite, $false)
    }
}

# Applies gateway and host DNS changes for prefix and IP lifecycle operations.
class GatewayDnsService {
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter
    [DnsServerAdapter] $DnsServerAdapter

    GatewayDnsService([ActiveDirectoryAdapter] $activeDirectoryAdapter, [DnsServerAdapter] $dnsServerAdapter) {
        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
        $this.DnsServerAdapter = $dnsServerAdapter
    }

    # Internal facade step that resolves all DNS execution dependencies once and hides AD/DNS lookup choreography from use cases.
    hidden [DnsExecutionContext] ResolveDnsExecutionContext([IPv4Subnet] $subnet) {
        $domainController = $this.ActiveDirectoryAdapter.GetDomainControllerName()
        $reverseZone = $this.DnsServerAdapter.FindBestReverseZoneName($subnet, $domainController)

        if ([string]::IsNullOrWhiteSpace($reverseZone)) {
            throw [System.InvalidOperationException]::new("No reverse zone found for prefix '$($subnet.Cidr)'.")
        }

        return [DnsExecutionContext]::new($domainController, $reverseZone)
    }

    # Facade method for prefix onboarding: the application layer asks for gateway DNS as one intent, not as individual DNS operations.
    [void] EnsurePrefixGatewayDns([PrefixWorkItem] $workItem) {
        $dnsContext = $this.ResolveDnsExecutionContext($workItem.PrefixSubnet)

        $this.DnsServerAdapter.EnsureDnsRecordsForIp(
            $dnsContext.DomainController,
            $workItem.Domain,
            $workItem.DnsName,
            $workItem.DefaultGatewayAddress,
            $dnsContext.ReverseZone,
            $workItem.GetGatewayFqdn()
        )
    }

    # Facade method for IP onboarding so future DNS-specific extensions stay behind one stable boundary.
    [void] EnsureIpDns([IpAddressWorkItem] $workItem) {
        if ([string]::IsNullOrWhiteSpace($workItem.DnsName)) {
            throw [System.InvalidOperationException]::new("DNS name is missing for IP '$($workItem.IpAddress.Value)'.")
        }

        $dnsContext = $this.ResolveDnsExecutionContext($workItem.PrefixSubnet)

        $this.DnsServerAdapter.EnsureDnsRecordsForIp(
            $dnsContext.DomainController,
            $workItem.Domain,
            $workItem.DnsName,
            $workItem.IpAddress,
            $dnsContext.ReverseZone,
            $workItem.GetFqdn()
        )
    }

    # Facade method for IP decommissioning; keeps deletion semantics centralized for later lifecycle growth.
    [void] RemoveIpDns([IpAddressWorkItem] $workItem) {
        $dnsContext = $this.ResolveDnsExecutionContext($workItem.PrefixSubnet)

        $this.DnsServerAdapter.RemoveDnsRecordsForIp(
            $dnsContext.DomainController,
            $workItem.Domain,
            $dnsContext.ReverseZone,
            $workItem.IpAddress
        )
    }
}

# Formats grouped operational failures into a mail body that humans can triage quickly.
class OperationIssueMailFormatter {
    hidden [string] EscapeHtml([string] $value) {
        if ($null -eq $value) {
            return ''
        }

        return [System.Security.SecurityElement]::Escape($value)
    }

    hidden [hashtable] GroupByDepartment([OperationIssue[]] $issues) {
        $groups = @{}

        foreach ($issue in @($issues)) {
            $department = $issue.GetHandlingDepartment()
            if (-not $groups.ContainsKey($department)) {
                $groups[$department] = @()
            }

            $groups[$department] = @($groups[$department] + $issue)
        }

        return $groups
    }

    hidden [string] BuildIssueMarkup([OperationIssue] $issue) {
        $handlerMarkup = ''
        if ($issue.HandlingContext.HasAssignedHandler()) {
            $handlerMarkup = ('<br><small>Handler: {0}</small>' -f $this.EscapeHtml($issue.GetHandlingHandler()))
        }

        $identifierMarkup = ('<strong>{0}</strong>' -f $this.EscapeHtml($issue.WorkItemIdentifier))
        if ($issue.HasResourceUrl()) {
            $identifierMarkup = ('<a href="{0}"><strong>{1}</strong></a>' -f $this.EscapeHtml($issue.ResourceUrl), $this.EscapeHtml($issue.WorkItemIdentifier))
        }

        return '<li>{0} [{1}] {2}{3}</li>' -f `
            $identifierMarkup, `
            $this.EscapeHtml($issue.WorkItemType), `
            $this.EscapeHtml($issue.Message), `
            $handlerMarkup
    }

    hidden [string] BuildDepartmentSection([string] $department, [OperationIssue[]] $issues) {
        $items = @()
        foreach ($issue in @($issues)) {
            $items += $this.BuildIssueMarkup($issue)
        }

        return @"
<h3>$($this.EscapeHtml($department)) ($($issues.Count))</h3>
<ul>
$($items -join [Environment]::NewLine)
</ul>
"@
    }

    [string] BuildFailureSummaryBody([OperationIssue[]] $issues) {
        if (-not $issues) {
            return $null
        }

        $departmentSections = @()
        $groupedIssues = $this.GroupByDepartment($issues)

        foreach ($department in @($groupedIssues.Keys | Sort-Object)) {
            $departmentSections += $this.BuildDepartmentSection($department, @($groupedIssues[$department]))
        }

        return @"
<p>During the execution of the <strong>DHCPScopeAutomation</strong> rewrite, work items failed.</p>
<p>Failures are grouped by handling department. Department ownership is prepared in the model, but explicit assignment rules are not configured yet.</p>
$($departmentSections -join [Environment]::NewLine)
<p><em>This is an automated message. No reply is required.</em></p>
"@
    }
}

# Sends aggregated failure notifications after all enabled batch processes finished.
class BatchNotificationService {
    [SmtpMailClient] $MailClient
    [OperationIssueMailFormatter] $MailFormatter

    BatchNotificationService([SmtpMailClient] $mailClient, [OperationIssueMailFormatter] $mailFormatter) {
        if ($null -eq $mailClient) {
            throw [System.ArgumentNullException]::new('mailClient')
        }

        if ($null -eq $mailFormatter) {
            throw [System.ArgumentNullException]::new('mailFormatter')
        }

        $this.MailClient = $mailClient
        $this.MailFormatter = $mailFormatter
    }

    hidden [OperationIssue[]] CollectIssues([BatchRunSummary[]] $summaries) {
        $issues = @()

        foreach ($summary in @($summaries)) {
            foreach ($issue in @($summary.Issues)) {
                $issues = @($issues + $issue)
            }
        }

        return $issues
    }

    [void] SendFailureSummary([string[]] $recipients, [BatchRunSummary[]] $summaries) {
        $issues = $this.CollectIssues($summaries)

        if (-not $issues) {
            return
        }

        $body = $this.MailFormatter.BuildFailureSummaryBody($issues)
        if ([string]::IsNullOrWhiteSpace($body)) {
            return
        }

        $this.MailClient.SendHtmlMail($recipients, 'DHCPScopeAutomation', $body)
    }
}

# Orchestrates the end-to-end prefix onboarding use case.
class PrefixOnboardingService {
    [NetBoxClient] $NetBoxClient
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter
    [JiraClient] $JiraClient
    [PrerequisiteValidationService] $PrerequisiteValidationService
    [DhcpServerSelectionService] $DhcpServerSelectionService
    [DhcpServerAdapter] $DhcpServerAdapter
    [GatewayDnsService] $GatewayDnsService
    [WorkItemJournalService] $JournalService
    [WorkItemLogService] $LogService

    PrefixOnboardingService(
        [NetBoxClient] $netBoxClient,
        [ActiveDirectoryAdapter] $activeDirectoryAdapter,
        [JiraClient] $jiraClient,
        [PrerequisiteValidationService] $prerequisiteValidationService,
        [DhcpServerSelectionService] $dhcpServerSelectionService,
        [DhcpServerAdapter] $dhcpServerAdapter,
        [GatewayDnsService] $gatewayDnsService,
        [WorkItemJournalService] $journalService,
        [WorkItemLogService] $logService
    ) {
        $this.NetBoxClient = $netBoxClient
        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
        $this.JiraClient = $jiraClient
        $this.PrerequisiteValidationService = $prerequisiteValidationService
        $this.DhcpServerSelectionService = $dhcpServerSelectionService
        $this.DhcpServerAdapter = $dhcpServerAdapter
        $this.GatewayDnsService = $gatewayDnsService
        $this.JournalService = $journalService
        $this.LogService = $logService
    }

    # Batch entry point for the use case. It acts as the application-service orchestrator and keeps iteration outside the domain model.
    [BatchRunSummary] ProcessBatch([EnvironmentContext] $environment) {
        $workItems = $this.NetBoxClient.GetOpenPrefixWorkItems($environment)
        return $this.ProcessWorkItems($environment, $workItems)
    }

    # Exposes the invariant batch shell separately from data loading so tests can drive the use case with explicit work items.
    [BatchRunSummary] ProcessWorkItems([EnvironmentContext] $environment, [PrefixWorkItem[]] $workItems) {
        $summary = [BatchRunSummary]::new('PrefixOnboarding')
        $loadedWorkItems = @($workItems)
        $summary.AddAudit('Debug', "Loaded $($loadedWorkItems.Count) prefix work item(s) for environment '$($environment.Name)'.")

        foreach ($workItem in $loadedWorkItems) {
            $this.ProcessWorkItem($environment, $workItem, $summary)
        }

        $summary.Complete()
        return $summary
    }

    # Template-style work-item flow: validate, branch by policy, execute provisioning, translate all failures into one reporting model.
    hidden [void] ProcessWorkItem([EnvironmentContext] $environment, [PrefixWorkItem] $workItem, [BatchRunSummary] $summary) {
        $lines = @(('Processing prefix {0}' -f $workItem.GetIdentifier()))
        $summary.AddAudit('Debug', "Starting prefix work item '$($workItem.GetIdentifier())'.")

        try {
            $evaluation = $this.PrerequisiteValidationService.Evaluate($workItem, $environment)
            $lines += $evaluation.Reasons

            if (-not $evaluation.CanContinue) {
                $this.HandleBlockedPrerequisites($workItem, $evaluation, $lines, $summary)
                return
            }

            if ($workItem.DHCPType -eq 'no_dhcp') {
                $this.CompleteNoDhcpPrefix($workItem, $lines, $summary)
                return
            }

            $this.CompleteDhcpBackedPrefix($environment, $workItem, $evaluation, $lines, $summary)
        }
        catch {
            $this.HandleProcessingFailure($workItem, $lines, $summary, $_.Exception)
        }
    }

    # Separates prerequisite handling from provisioning so the Jira/manual-work policy can evolve without touching DHCP or DNS steps.
    hidden [void] HandleBlockedPrerequisites(
        [PrefixWorkItem] $workItem,
        [PrerequisiteEvaluation] $evaluation,
        [string[]] $lines,
        [BatchRunSummary] $summary
    ) {
        if ($evaluation.RequiresNewJiraTicket) {
            $forestShortName = $this.ActiveDirectoryAdapter.GetForestShortName($workItem.Domain)
            $ticketUrl = $this.JiraClient.CreatePrerequisiteTicket($workItem, $forestShortName, $evaluation.HasDnsDelegation)
            $this.NetBoxClient.UpdatePrefixTicketUrl($workItem.Id, $ticketUrl)
            $lines += 'Created Jira ticket {0}' -f $ticketUrl
            $lines = $this.WriteExecutionLog($workItem, $lines)
            $this.JournalService.WritePrefixInfo($workItem, $lines)
            $summary.AddAudit('Information', "Created Jira ticket for prefix '$($workItem.GetIdentifier())'.")
            $summary.AddSuccess(('Created Jira ticket for prefix {0}' -f $workItem.GetIdentifier()))
            return
        }

        $message = ($evaluation.Reasons -join ' ')
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = 'Prefix prerequisites are not satisfied.'
        }

        throw [System.InvalidOperationException]::new($message)
    }

    hidden [void] CompleteNoDhcpPrefix([PrefixWorkItem] $workItem, [string[]] $lines, [BatchRunSummary] $summary) {
        $this.GatewayDnsService.EnsurePrefixGatewayDns($workItem)
        $this.NetBoxClient.MarkPrefixOnboardingDone($workItem.Id)
        $lines += 'Gateway DNS updated.'
        $lines += 'Prefix status updated to onboarding_done_dns_dhcp.'
        $lines = $this.WriteExecutionLog($workItem, $lines)
        $this.JournalService.WritePrefixInfo($workItem, $lines)
        $summary.AddAudit('Information', "Completed prefix work item '$($workItem.GetIdentifier())'.")
        $summary.AddSuccess(('Completed no_dhcp prefix {0}' -f $workItem.GetIdentifier()))
    }

    # Orchestrates the full side-effecting provisioning path; this is intentionally an application-level workflow, not domain logic.
    hidden [void] CompleteDhcpBackedPrefix(
        [EnvironmentContext] $environment,
        [PrefixWorkItem] $workItem,
        [PrerequisiteEvaluation] $evaluation,
        [string[]] $lines,
        [BatchRunSummary] $summary
    ) {
        $scopeDefinition = [DhcpScopeDefinition]::FromPrefixWorkItem($workItem)

        if ($scopeDefinition.Range.GatewayAddress.Value -ne $workItem.DefaultGatewayAddress.Value) {
            throw [System.InvalidOperationException]::new(
                "Gateway mismatch for prefix '$($workItem.GetIdentifier())'. Expected '$($scopeDefinition.Range.GatewayAddress.Value)', NetBox provides '$($workItem.DefaultGatewayAddress.Value)'."
            )
        }

        $selectedServer = $this.DhcpServerSelectionService.SelectServer($environment, $evaluation.ObservedAdSite)
        $lines += 'Selected DHCP server: {0}' -f $selectedServer

        $this.DhcpServerAdapter.EnsureScope($selectedServer, $scopeDefinition)
        $lines += 'DHCP scope ensured.'

        $this.GatewayDnsService.EnsurePrefixGatewayDns($workItem)
        $lines += 'Gateway DNS updated.'

        $this.DhcpServerAdapter.EnsureScopeFailover($selectedServer, $scopeDefinition.Subnet)
        $lines += 'Failover linkage ensured.'

        $this.NetBoxClient.MarkPrefixOnboardingDone($workItem.Id)
        $lines += 'Prefix status updated to onboarding_done_dns_dhcp.'

        $lines = $this.WriteExecutionLog($workItem, $lines)
        $this.JournalService.WritePrefixInfo($workItem, $lines)
        $summary.AddAudit('Information', "Completed prefix work item '$($workItem.GetIdentifier())'.")
        $summary.AddSuccess(('Completed prefix onboarding for {0}' -f $workItem.GetIdentifier()))
    }

    hidden [void] HandleProcessingFailure(
        [PrefixWorkItem] $workItem,
        [string[]] $lines,
        [BatchRunSummary] $summary,
        [System.Exception] $exception
    ) {
        $message = "Failed to process prefix '$($workItem.GetIdentifier())'. $($exception.Message)"
        $lines += $message
        $lines = $this.WriteExecutionLog($workItem, $lines)

        try {
            $this.JournalService.WritePrefixError($workItem, $lines)
        }
        catch {
            $summary.AddAudit('Warning', "Failed to write NetBox error journal for prefix '$($workItem.GetIdentifier())'. $($_.Exception.Message)")
        }

        $summary.AddFailure(
            [OperationIssue]::new(
                'Prefix',
                $workItem.GetIdentifier(),
                $message,
                $exception.ToString(),
                $this.BuildFailureHandlingContext($workItem, $exception),
                $this.NetBoxClient.GetPrefixUrl($workItem.Id)
            )
        )
    }

    hidden [IssueHandlingContext] BuildFailureHandlingContext([PrefixWorkItem] $workItem, [System.Exception] $exception) {
        return [IssueHandlingContext]::CreateUnassigned()
    }

    hidden [string[]] WriteExecutionLog([PrefixWorkItem] $workItem, [string[]] $lines) {
        $logPath = $this.LogService.CreateLogPath('network', $workItem.GetIdentifier())
        $linesWithLogPath = @($lines + ('Log file: {0}' -f $logPath))
        $this.LogService.WriteLog($logPath, $linesWithLogPath)
        return $linesWithLogPath
    }
}

# Reuses one workflow shell for IP DNS onboarding and decommissioning.
class IpDnsLifecycleService {
    [NetBoxClient] $NetBoxClient
    [GatewayDnsService] $GatewayDnsService
    [WorkItemJournalService] $JournalService
    [WorkItemLogService] $LogService
    [string] $Mode
    [string] $ProcessName
    [string[]] $SourceStatuses
    [string] $TargetStatus

    IpDnsLifecycleService(
        [string] $mode,
        [NetBoxClient] $netBoxClient,
        [GatewayDnsService] $gatewayDnsService,
        [WorkItemJournalService] $journalService,
        [WorkItemLogService] $logService
    ) {
        $this.InitializeMode($mode)
        $this.NetBoxClient = $netBoxClient
        $this.GatewayDnsService = $gatewayDnsService
        $this.JournalService = $journalService
        $this.LogService = $logService
    }

    # Configures the service as a mode-based strategy object so onboarding and decommissioning can reuse one workflow shell.
    hidden [void] InitializeMode([string] $mode) {
        $normalizedMode = $mode
        if (-not [string]::IsNullOrWhiteSpace($normalizedMode)) {
            $normalizedMode = $normalizedMode.Trim().ToLowerInvariant()
        }

        switch ($normalizedMode) {
            'onboarding' {
                $this.Mode = $normalizedMode
                $this.ProcessName = 'IpDnsOnboarding'
                $this.SourceStatuses = @('onboarding_open_dns')
                $this.TargetStatus = 'onboarding_done_dns'
                break
            }
            'decommissioning' {
                $this.Mode = $normalizedMode
                $this.ProcessName = 'IpDnsDecommissioning'
                $this.SourceStatuses = @('decommissioning_open_dns')
                $this.TargetStatus = 'decommissioning_done_dns'
                break
            }
            default {
                throw [System.ArgumentOutOfRangeException]::new('mode', "Unsupported IP DNS lifecycle mode '$mode'.")
            }
        }
    }

    # Shared batch shell for both lifecycle variants; only the mode-specific strategy changes the business action.
    [BatchRunSummary] ProcessBatch([EnvironmentContext] $environment) {
        $workItems = $this.NetBoxClient.GetIpWorkItems($environment, $this.SourceStatuses)
        return $this.ProcessWorkItems($environment, $workItems)
    }

    # Splits the reusable lifecycle shell from the repository fetch so tests can cover orchestration with synthetic work items.
    [BatchRunSummary] ProcessWorkItems([EnvironmentContext] $environment, [IpAddressWorkItem[]] $workItems) {
        $summary = [BatchRunSummary]::new($this.ProcessName)
        $loadedWorkItems = @($workItems)
        $summary.AddAudit('Debug', "Loaded $($loadedWorkItems.Count) $($this.GetLifecycleDisplayName()) work item(s) for environment '$($environment.Name)'.")

        foreach ($workItem in $loadedWorkItems) {
            $this.ProcessWorkItem($workItem, $summary)
        }

        $summary.Complete()
        return $summary
    }

    # Template-method style execution: invariant steps stay fixed while mode-dependent behavior is delegated to helper methods.
    hidden [void] ProcessWorkItem([IpAddressWorkItem] $workItem, [BatchRunSummary] $summary) {
        $lines = @($this.GetProcessingLine($workItem))
        $summary.AddAudit('Debug', "Starting $($this.GetLifecycleDisplayName()) work item '$($workItem.GetIdentifier())'.")

        try {
            $this.ValidateWorkItem($workItem)
            $this.ExecuteDnsLifecycle($workItem)
            $lines += $this.GetDnsLifecycleResultLine()

            $this.NetBoxClient.UpdateIpStatus($workItem.Id, $this.TargetStatus)
            $lines += ('IP status updated to {0}.' -f $this.TargetStatus)

            $lines = $this.WriteExecutionLog($workItem, $lines)
            $this.JournalService.WriteIpInfo($workItem, $lines)
            $summary.AddAudit('Information', "Completed $($this.GetLifecycleDisplayName()) work item '$($workItem.GetIdentifier())'.")
            $summary.AddSuccess($this.GetSuccessSummaryMessage($workItem))
        }
        catch {
            $this.HandleProcessingFailure($workItem, $lines, $summary, $_.Exception)
        }
    }

    hidden [void] ValidateWorkItem([IpAddressWorkItem] $workItem) {
        if ($this.Mode -eq 'onboarding' -and [string]::IsNullOrWhiteSpace($workItem.DnsName)) {
            throw [System.InvalidOperationException]::new("DNS name is missing for IP '$($workItem.GetIdentifier())'.")
        }
    }

    # Strategy dispatch for the lifecycle action; new modes should extend this seam instead of duplicating the service.
    hidden [void] ExecuteDnsLifecycle([IpAddressWorkItem] $workItem) {
        switch ($this.Mode) {
            'onboarding' {
                $this.GatewayDnsService.EnsureIpDns($workItem)
                break
            }
            'decommissioning' {
                $this.GatewayDnsService.RemoveIpDns($workItem)
                break
            }
            default {
                throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.")
            }
        }
    }

    hidden [void] HandleProcessingFailure(
        [IpAddressWorkItem] $workItem,
        [string[]] $lines,
        [BatchRunSummary] $summary,
        [System.Exception] $exception
    ) {
        $message = $this.GetFailureMessage($workItem, $exception)
        $lines += $message
        $lines = $this.WriteExecutionLog($workItem, $lines)

        try {
            $this.JournalService.WriteIpError($workItem, $lines)
        }
        catch {
            $summary.AddAudit('Warning', "Failed to write NetBox error journal for IP '$($workItem.GetIdentifier())'. $($_.Exception.Message)")
        }

        $summary.AddFailure(
            [OperationIssue]::new(
                'IPAddress',
                $workItem.GetIdentifier(),
                $message,
                $exception.ToString(),
                $this.BuildFailureHandlingContext($workItem, $exception),
                $this.NetBoxClient.GetIpAddressUrl($workItem.Id)
            )
        )
    }

    hidden [IssueHandlingContext] BuildFailureHandlingContext([IpAddressWorkItem] $workItem, [System.Exception] $exception) {
        return [IssueHandlingContext]::CreateUnassigned()
    }

    hidden [string[]] WriteExecutionLog([IpAddressWorkItem] $workItem, [string[]] $lines) {
        $logPath = $this.LogService.CreateLogPath('ip', $workItem.GetIdentifier())
        $linesWithLogPath = @($lines + ('Log file: {0}' -f $logPath))
        $this.LogService.WriteLog($logPath, $linesWithLogPath)
        return $linesWithLogPath
    }

    hidden [string] GetLifecycleDisplayName() {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = 'IP onboarding'; break }
            'decommissioning' { $result = 'IP decommissioning'; break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    hidden [string] GetProcessingLine([IpAddressWorkItem] $workItem) {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = ('Processing IP onboarding {0}' -f $workItem.GetIdentifier()); break }
            'decommissioning' { $result = ('Processing IP decommissioning {0}' -f $workItem.GetIdentifier()); break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    hidden [string] GetDnsLifecycleResultLine() {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = 'DNS records ensured.'; break }
            'decommissioning' { $result = 'DNS records removed.'; break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    hidden [string] GetSuccessSummaryMessage([IpAddressWorkItem] $workItem) {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = ('Completed IP DNS onboarding for {0}' -f $workItem.GetIdentifier()); break }
            'decommissioning' { $result = ('Completed IP DNS decommissioning for {0}' -f $workItem.GetIdentifier()); break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }

    hidden [string] GetFailureMessage([IpAddressWorkItem] $workItem, [System.Exception] $exception) {
        $result = $null
        switch ($this.Mode) {
            'onboarding' { $result = "Failed to process IP '$($workItem.GetIdentifier())'. $($exception.Message)"; break }
            'decommissioning' { $result = "Failed to decommission IP '$($workItem.GetIdentifier())'. $($exception.Message)"; break }
            default { throw [System.InvalidOperationException]::new("Unsupported IP DNS lifecycle mode '$($this.Mode)'.") }
        }

        return $result
    }
}

# Coordinates the enabled application services for one automation run.
class AutomationCoordinator {
    [PrefixOnboardingService] $PrefixOnboardingService
    [IpDnsLifecycleService] $IpDnsOnboardingService
    [IpDnsLifecycleService] $IpDnsDecommissioningService
    [BatchNotificationService] $BatchNotificationService

    AutomationCoordinator(
        [PrefixOnboardingService] $prefixOnboardingService,
        [IpDnsLifecycleService] $ipDnsOnboardingService,
        [IpDnsLifecycleService] $ipDnsDecommissioningService,
        [BatchNotificationService] $batchNotificationService
    ) {
        $this.PrefixOnboardingService = $prefixOnboardingService
        $this.IpDnsOnboardingService = $ipDnsOnboardingService
        $this.IpDnsDecommissioningService = $ipDnsDecommissioningService
        $this.BatchNotificationService = $batchNotificationService
    }

    # Facade over the enabled use cases. The caller sees one run method while the coordinator sequences the internal workflows.
    [BatchRunSummary[]] Run(
        [EnvironmentContext] $environment,
        [string[]] $emailRecipients,
        [bool] $sendFailureMail,
        [bool] $skipPrefixOnboarding,
        [bool] $skipIpDnsOnboarding,
        [bool] $skipIpDnsDecommissioning
    ) {
        $summaries = @()

        if (-not $skipPrefixOnboarding) {
            $summaries += $this.PrefixOnboardingService.ProcessBatch($environment)
        }

        if (-not $skipIpDnsOnboarding) {
            $summaries += $this.IpDnsOnboardingService.ProcessBatch($environment)
        }

        if (-not $skipIpDnsDecommissioning) {
            $summaries += $this.IpDnsDecommissioningService.ProcessBatch($environment)
        }

        if ($sendFailureMail) {
            try {
                $this.BatchNotificationService.SendFailureSummary($emailRecipients, $summaries)
            }
            catch {
                $notificationSummary = [BatchRunSummary]::new('FailureNotification')
                $notificationSummary.AddFailure(
                    [OperationIssue]::new(
                        'Notification',
                        'FailureSummaryMail',
                        "Failed to send failure summary mail. $($_.Exception.Message)",
                        $_.Exception.ToString(),
                        [IssueHandlingContext]::CreateUnassigned()
                    )
                )
                $notificationSummary.Complete()
                $summaries += $notificationSummary
            }
        }

        return $summaries
    }
}

# Holds the fully constructed runtime graph for execution and cross-cutting services.
class AutomationRuntime {
    [EnvironmentContext] $Environment
    [string[]] $EmailRecipients
    [AutomationCoordinator] $Coordinator
    [WorkItemLogService] $LogService

    AutomationRuntime(
        [EnvironmentContext] $environment,
        [string[]] $emailRecipients,
        [AutomationCoordinator] $coordinator,
        [WorkItemLogService] $logService
    ) {
        $normalizedRecipients = @($emailRecipients | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })

        if ($null -eq $environment) {
            throw [System.ArgumentNullException]::new('environment')
        }

        if (-not $normalizedRecipients -or $normalizedRecipients.Count -eq 0) {
            throw [System.ArgumentException]::new('EmailRecipients are required.')
        }

        if ($null -eq $coordinator) {
            throw [System.ArgumentNullException]::new('coordinator')
        }

        if ($null -eq $logService) {
            throw [System.ArgumentNullException]::new('logService')
        }

        $this.Environment = $environment
        $this.EmailRecipients = $normalizedRecipients
        $this.Coordinator = $coordinator
        $this.LogService = $logService
    }

    # Thin runtime facade that binds resolved configuration to the coordinator without exposing object-graph construction to callers.
    [BatchRunSummary[]] Execute(
        [bool] $sendFailureMail,
        [bool] $skipPrefixOnboarding,
        [bool] $skipIpDnsOnboarding,
        [bool] $skipIpDnsDecommissioning
    ) {
        return $this.Coordinator.Run(
            $this.Environment,
            $this.EmailRecipients,
            $sendFailureMail,
            $skipPrefixOnboarding,
            $skipIpDnsOnboarding,
            $skipIpDnsDecommissioning
        )
    }
}

# Base factory seam for runtime creation so the public entry point can be tested without real infrastructure.
class AutomationRuntimeFactoryBase {
    [AutomationRuntime] CreateRuntime() {
        throw [System.NotImplementedException]::new('CreateRuntime() must be implemented by a concrete runtime factory.')
    }
}

# Builds the runtime object graph and acts as the composition root of the module.
class AutomationRuntimeFactory : AutomationRuntimeFactoryBase {
    [string] $RequestedEnvironment
    [string[]] $RequestedEmailRecipients
    [string] $ConfigurationPath
    [string] $CredentialDirectory

    AutomationRuntimeFactory(
        [string] $requestedEnvironment,
        [string[]] $requestedEmailRecipients,
        [string] $configurationPath,
        [string] $credentialDirectory
    ) {
        $this.RequestedEnvironment = $requestedEnvironment
        $this.RequestedEmailRecipients = @($requestedEmailRecipients | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        $this.ConfigurationPath = $configurationPath
        $this.CredentialDirectory = $credentialDirectory
    }

    # Composition root for the module. Dependency construction stays here so application services remain injectable and testable.
    [AutomationRuntime] CreateRuntime() {
        $configurationProvider = [EnvFileConfigurationProvider]::new($this.ConfigurationPath)
        $resolvedEnvironment = $this.ResolveEnvironment($configurationProvider)
        $resolvedRecipients = $this.ResolveEmailRecipients($configurationProvider)
        $environmentContext = [EnvironmentContext]::new($resolvedEnvironment)
        $credentialProvider = [SecureFileCredentialProvider]::new($this.CredentialDirectory)

        $netBoxCredential = $credentialProvider.GetApiCredential('DHCPScopeAutomationNetboxApiKey')
        $jiraCredential = $credentialProvider.GetApiCredential('DHCPScopeAutomationJiraApiKey')

        $activeDirectoryAdapter = [ActiveDirectoryAdapter]::new()
        $dnsServerAdapter = [DnsServerAdapter]::new()
        $dhcpServerAdapter = [DhcpServerAdapter]::new()
        $netBoxClient = [NetBoxClient]::new($netBoxCredential)
        $jiraClient = [JiraClient]::new($jiraCredential)
        $mailClient = [SmtpMailClient]::new($activeDirectoryAdapter)
        $mailFormatter = [OperationIssueMailFormatter]::new()
        $logService = [WorkItemLogService]::new('logs')

        $prerequisiteValidationService = [PrerequisiteValidationService]::new($activeDirectoryAdapter, $dnsServerAdapter, $jiraClient)
        $dhcpServerSelectionService = [DhcpServerSelectionService]::new($dhcpServerAdapter)
        $gatewayDnsService = [GatewayDnsService]::new($activeDirectoryAdapter, $dnsServerAdapter)
        $journalService = [WorkItemJournalService]::new($netBoxClient)
        $notificationService = [BatchNotificationService]::new($mailClient, $mailFormatter)

        $prefixOnboardingService = [PrefixOnboardingService]::new(
            $netBoxClient,
            $activeDirectoryAdapter,
            $jiraClient,
            $prerequisiteValidationService,
            $dhcpServerSelectionService,
            $dhcpServerAdapter,
            $gatewayDnsService,
            $journalService,
            $logService
        )

        $ipDnsOnboardingService = [IpDnsLifecycleService]::new('onboarding', $netBoxClient, $gatewayDnsService, $journalService, $logService)
        $ipDnsDecommissioningService = [IpDnsLifecycleService]::new('decommissioning', $netBoxClient, $gatewayDnsService, $journalService, $logService)

        $coordinator = [AutomationCoordinator]::new(
            $prefixOnboardingService,
            $ipDnsOnboardingService,
            $ipDnsDecommissioningService,
            $notificationService
        )

        return [AutomationRuntime]::new($environmentContext, $resolvedRecipients, $coordinator, $logService)
    }

    hidden [string] ResolveEnvironment([EnvFileConfigurationProvider] $configurationProvider) {
        if (-not [string]::IsNullOrWhiteSpace($this.RequestedEnvironment)) {
            return $this.RequestedEnvironment
        }

        return $configurationProvider.GetValue('Environment', 'Expected one of: dev, test, prod, gov, china.')
    }

    hidden [string[]] ResolveEmailRecipients([EnvFileConfigurationProvider] $configurationProvider) {
        if ($this.RequestedEmailRecipients -and $this.RequestedEmailRecipients.Count -gt 0) {
            return @($this.RequestedEmailRecipients)
        }

        return $configurationProvider.GetStringArray('EmailRecipients', 'Expected a comma separated recipient list.')
    }
}
