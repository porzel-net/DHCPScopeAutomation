# DHCPScopeAutomation Class And Function Reference

## Purpose
This reference describes every class and every top-level function in the rewrite.
It is intended as the primary developer-facing API guide for future maintenance.

## Conventions
- `hidden` methods are internal design seams. They are documented because they shape the internal architecture and tests.
- Examples are illustrative and focus on intent, not on real infrastructure access.
- Constructors are listed as part of each class because PowerShell classes expose behavior through the constructor contract as well.

## Domain

### `OperationAuditEntry`
Description:
Represents one structured audit/log entry emitted during a batch run.

Example:
`[OperationAuditEntry]::new('Information', 'Prefix completed.')`

Methods:
- `OperationAuditEntry(level, message)`: Validates level and message and timestamps the entry.
  Example: `[OperationAuditEntry]::new('Warning', 'Journal write failed.')`

### `IssueHandlingContext`
Description:
Captures future routing metadata for operational issues, such as owning department and handler.

Example:
`[IssueHandlingContext]::new('FIST', 'Alice')`

Methods:
- `IssueHandlingContext(department, handler)`: Creates a routing context and normalizes the values.
  Example: `[IssueHandlingContext]::new('NetOps', 'Bob')`
- `CreateUnassigned()`: Creates the default unassigned routing context.
  Example: `[IssueHandlingContext]::CreateUnassigned()`
- `NormalizeValue(value)`: Internal helper that trims or nulls empty routing values.
  Example: `[IssueHandlingContext]::new(' FIST ', ' Alice ')`
- `GetDepartmentOrDefault()`: Returns the configured department or `Unassigned`.
  Example: `[IssueHandlingContext]::new($null, $null).GetDepartmentOrDefault()`
- `GetHandlerOrDefault()`: Returns the configured handler or `Unassigned`.
  Example: `[IssueHandlingContext]::new($null, $null).GetHandlerOrDefault()`
- `HasAssignedDepartment()`: Indicates whether a real department is present.
  Example: `[IssueHandlingContext]::new('FIST', $null).HasAssignedDepartment()`
- `HasAssignedHandler()`: Indicates whether a real handler is present.
  Example: `[IssueHandlingContext]::new('FIST', 'Alice').HasAssignedHandler()`

### `OperationIssue`
Description:
Represents one failed work item together with details, handling context and optional deep link.

Example:
`[OperationIssue]::new('Prefix', '10.20.30.0/24', 'Failed', 'Details')`

Methods:
- `OperationIssue(workItemType, workItemIdentifier, message, details)`: Creates an issue with unassigned handling.
  Example: `[OperationIssue]::new('IPAddress', '10.20.30.10', 'Missing DNS', 'No dns_name in NetBox.')`
- `OperationIssue(workItemType, workItemIdentifier, message, details, issueHandlingContext)`: Creates an issue with explicit handling.
  Example: `[OperationIssue]::new('Prefix', '10.20.30.0/24', 'Blocked', 'AD site missing', [IssueHandlingContext]::new('FIST', 'Alice'))`
- `OperationIssue(workItemType, workItemIdentifier, message, details, issueHandlingContext, resourceUrl)`: Creates an issue with handling and deep link.
  Example: `[OperationIssue]::new('Prefix', '10.20.30.0/24', 'Blocked', 'AD site missing', [IssueHandlingContext]::new('FIST', 'Alice'), 'https://netbox.example.test/ipam/prefixes/7/')`
- `Initialize(...)`: Internal shared initialization for all constructor overloads.
  Example: Used implicitly by each `OperationIssue` constructor.
- `GetHandlingDepartment()`: Returns the effective handling department.
  Example: `$issue.GetHandlingDepartment()`
- `GetHandlingHandler()`: Returns the effective handling handler.
  Example: `$issue.GetHandlingHandler()`
- `HasResourceUrl()`: Indicates whether the issue has a deep link.
  Example: `$issue.HasResourceUrl()`

### `BatchRunSummary`
Description:
Aggregates successes, failures and audit entries for one batch process.

Example:
`[BatchRunSummary]::new('PrefixOnboarding')`

Methods:
- `BatchRunSummary(processName)`: Creates an empty summary for one process.
  Example: `[BatchRunSummary]::new('IpDnsOnboarding')`
- `AddSuccess(message)`: Adds a success entry and increments success count.
  Example: `$summary.AddSuccess('Prefix completed.')`
- `AddFailure(issue)`: Adds an `OperationIssue` and increments failure count.
  Example: `$summary.AddFailure($issue)`
- `AddAudit(level, message)`: Adds a structured audit log entry.
  Example: `$summary.AddAudit('Debug', 'Loaded 3 work items.')`
- `Complete()`: Marks the summary as finished.
  Example: `$summary.Complete()`
- `HasFailures()`: Indicates whether at least one failure is present.
  Example: `$summary.HasFailures()`

### `EnvironmentContext`
Description:
Encapsulates environment-specific behavior such as DNS zone and delegation rules.

Example:
`[EnvironmentContext]::new('prod')`

Methods:
- `EnvironmentContext(name)`: Normalizes an environment name and resolves its DNS zone.
  Example: `[EnvironmentContext]::new('test')`
- `IsDevelopment()`: Returns `true` for development-like environments.
  Example: `$environment.IsDevelopment()`
- `IsTest()`: Returns `true` for the test environment.
  Example: `$environment.IsTest()`
- `IsProduction()`: Returns `true` for production.
  Example: `$environment.IsProduction()`
- `GetDelegationValidationDomain()`: Returns the DNS domain suffix used for reverse-delegation validation.
  Example: `$environment.GetDelegationValidationDomain()`

### `IPv4Address`
Description:
Strongly typed IPv4 address value object with numeric conversion helpers.

Example:
`[IPv4Address]::new('10.20.30.10')`

Methods:
- `IPv4Address(value)`: Validates and stores an IPv4 address.
  Example: `[IPv4Address]::new('10.20.30.254')`
- `ConvertToUInt32(value)`: Converts an IPv4 string to its numeric representation.
  Example: `[IPv4Address]::ConvertToUInt32('10.20.30.10')`
- `ConvertFromUInt32(value)`: Converts a numeric IPv4 value back to dotted notation.
  Example: `[IPv4Address]::ConvertFromUInt32(16909060)`
- `GetUInt32()`: Returns the numeric representation of the current address.
  Example: `$ip.GetUInt32()`
- `AddOffset(offset)`: Returns a new address shifted by the given offset.
  Example: `$ip.AddOffset(5)`
- `ToString()`: Returns the dotted IPv4 string.
  Example: `$ip.ToString()`

### `IPv4Subnet`
Description:
IPv4 subnet value object that exposes network, reverse-zone and block calculations.

Example:
`[IPv4Subnet]::new('10.20.30.0/24')`

Methods:
- `IPv4Subnet(cidr)`: Parses and validates a CIDR subnet.
  Example: `[IPv4Subnet]::new('10.20.30.0/23')`
- `GetMask(prefixLength)`: Returns the numeric subnet mask for a prefix length.
  Example: `[IPv4Subnet]::GetMask(24)`
- `GetNetworkNumber(address, mask)`: Calculates the network number.
  Example: `[IPv4Subnet]::GetNetworkNumber(169090560, [IPv4Subnet]::GetMask(24))`
- `GetSubnetMaskString()`: Returns the dotted subnet mask.
  Example: `$subnet.GetSubnetMaskString()`
- `GetBroadcastAddress()`: Returns the broadcast address.
  Example: `$subnet.GetBroadcastAddress().Value`
- `GetAddressAtOffset(offset)`: Returns the address at a network-relative offset.
  Example: `$subnet.GetAddressAtOffset(1).Value`
- `GetReverseZoneName()`: Returns the reverse DNS zone name implied by the subnet.
  Example: `$subnet.GetReverseZoneName()`
- `GetAdLookupCandidates()`: Returns decreasingly broad subnet candidates for AD site lookup.
  Example: `$subnet.GetAdLookupCandidates()`
- `Get24BlockBaseAddresses()`: Returns every `/24` block base inside the subnet.
  Example: `$subnet.Get24BlockBaseAddresses()`
- `ToString()`: Returns the CIDR string.
  Example: `$subnet.ToString()`

### `DhcpExclusionRange`
Description:
Represents a DHCP exclusion range plus whether that exclusion must succeed.

Example:
`[DhcpExclusionRange]::new([IPv4Address]::new('10.20.30.1'), [IPv4Address]::new('10.20.30.1'), $true)`

Methods:
- `DhcpExclusionRange(startAddress, endAddress)`: Creates an exclusion with default success behavior.
  Example: `[DhcpExclusionRange]::new([IPv4Address]::new('10.20.30.1'), [IPv4Address]::new('10.20.30.1'))`
- `DhcpExclusionRange(startAddress, endAddress, mustSucceed)`: Creates an exclusion with explicit strictness.
  Example: `[DhcpExclusionRange]::new([IPv4Address]::new('10.20.30.249'), [IPv4Address]::new('10.20.30.255'), $false)`
- `Initialize(startAddress, endAddress, mustSucceed)`: Internal constructor helper for validation and assignment.
  Example: Used implicitly by the constructor overloads.

### `DhcpRange`
Description:
Represents the usable DHCP lease range together with gateway and broadcast data.

Example:
`[DhcpRange]::FromSubnet([IPv4Subnet]::new('10.20.30.0/24'), 'dhcp_dynamic')`

Methods:
- `DhcpRange(startAddress, endAddress, gatewayAddress, broadcastAddress, reservedAfterGateway)`: Creates a fully resolved range object.
  Example: `[DhcpRange]::new([IPv4Address]::new('10.20.30.1'), [IPv4Address]::new('10.20.30.248'), [IPv4Address]::new('10.20.30.254'), [IPv4Address]::new('10.20.30.255'), 5)`
- `FromSubnet(subnet, dhcpType)`: Derives the DHCP range from a subnet and DHCP type.
  Example: `[DhcpRange]::FromSubnet([IPv4Subnet]::new('10.20.30.0/24'), 'dhcp_static')`

### `PrefixWorkItem`
Description:
Represents one NetBox prefix that should be processed by the prefix onboarding use case.

Example:
`[PrefixWorkItem]::new(7, '10.20.30.0/24', 'Office', 'dhcp_dynamic', 'de.mtu.corp', 'MUC', 17, 101, '10.20.30.254', 'gw102030.de.mtu.corp', 'MUC', $null)`

Methods:
- `PrefixWorkItem(...)`: Validates and stores all business data required for a prefix workflow.
  Example: See example above.
- `GetGatewayFqdn()`: Returns the gateway DNS name as an FQDN.
  Example: `$workItem.GetGatewayFqdn()`
- `GetIdentifier()`: Returns the primary human-readable identifier of the work item.
  Example: `$workItem.GetIdentifier()`

### `IpAddressWorkItem`
Description:
Represents one NetBox IP address that should be processed by the IP DNS lifecycle.

Example:
`[IpAddressWorkItem]::new(20, '10.20.30.10', 'onboarding_open_dns', 'host102030', 'de.mtu.corp', '10.20.30.0/24')`

Methods:
- `IpAddressWorkItem(...)`: Validates and stores all business data required for an IP DNS workflow.
  Example: See example above.
- `GetIdentifier()`: Returns the IP address string used as the work item identifier.
  Example: `$workItem.GetIdentifier()`
- `GetFqdn()`: Returns the IP DNS name as an FQDN when available.
  Example: `$workItem.GetFqdn()`

### `DhcpScopeDefinition`
Description:
Represents the fully resolved DHCP scope configuration derived from a prefix work item.

Example:
`[DhcpScopeDefinition]::FromPrefixWorkItem($workItem)`

Methods:
- `DhcpScopeDefinition(name, subnet, subnetMask, range, dnsDomain, leaseDurationDays, configureDynamicDns, exclusionRanges)`: Creates a complete scope definition.
  Example: `$definition = [DhcpScopeDefinition]::FromPrefixWorkItem($workItem)`
- `FromPrefixWorkItem(workItem)`: Converts a prefix work item into a DHCP scope definition.
  Example: `[DhcpScopeDefinition]::FromPrefixWorkItem($workItem)`

### `PrerequisiteEvaluation`
Description:
Represents the validation result for one prefix before side effects begin.

Example:
`[PrerequisiteEvaluation]::new()`

Methods:
- `PrerequisiteEvaluation()`: Creates an empty evaluation object with no reasons.
  Example: `$evaluation = [PrerequisiteEvaluation]::new()`
- `AddReason(reason)`: Adds a human-readable blocking reason when one exists.
  Example: `$evaluation.AddReason('Network is not assigned to any AD site.')`

### `AutomationCredential`
Description:
Represents an appliance endpoint and API key used by infrastructure clients.

Example:
`[AutomationCredential]::new('NetBox', 'https://netbox.example.test', (ConvertTo-SecureString 'secret' -AsPlainText -Force))`

Methods:
- `AutomationCredential(name, appliance, apiKey)`: Creates a validated automation credential.
  Example: See example above.
- `GetPlainApiKey()`: Returns the secure API key as plain text for outbound requests.
  Example: `$credential.GetPlainApiKey()`

### `DnsExecutionContext`
Description:
Carries the resolved domain controller and reverse zone for DNS execution.

Example:
`[DnsExecutionContext]::new('dc01.example.test', '30.20.10.in-addr.arpa')`

Methods:
- `DnsExecutionContext(domainController, reverseZone)`: Creates a DNS execution context.
  Example: See example above.

## Infrastructure

### `EnvFileConfigurationProvider`
Description:
Loads simple key-value configuration from a relative `.env`-style file.

Example:
`[EnvFileConfigurationProvider]::new('.env')`

Methods:
- `EnvFileConfigurationProvider(filePath)`: Loads and parses the config file if it exists.
  Example: `[EnvFileConfigurationProvider]::new('.env')`
- `GetValue(keyName, description)`: Returns a required config value or throws with a descriptive message.
  Example: `$provider.GetValue('Environment', 'Expected one of: dev, test, prod.')`
- `GetStringArray(keyName, description)`: Returns a required comma-separated config value as an array.
  Example: `$provider.GetStringArray('EmailRecipients', 'Expected recipients.')`

### `SecureFileCredentialProvider`
Description:
Loads persisted credentials from relative `.xml` files and can bootstrap them interactively.

Example:
`[SecureFileCredentialProvider]::new('.secureCreds')`

Methods:
- `SecureFileCredentialProvider(credentialBasePath)`: Creates the provider and ensures the credential directory exists.
  Example: `[SecureFileCredentialProvider]::new('.secureCreds')`
- `GetApiCredential(credentialName)`: Loads or creates one named credential.
  Example: `$provider.GetApiCredential('DHCPScopeAutomationNetboxApiKey')`

### `NetBoxClient`
Description:
Wraps all NetBox REST interactions and converts raw payloads into work item objects.

Example:
`[NetBoxClient]::new($netBoxCredential)`

Methods:
- `NetBoxClient(credential)`: Creates a NetBox API client.
  Example: `[NetBoxClient]::new($credential)`
- `GetJsonHeaders()`: Builds the REST headers for NetBox requests.
  Example: Used internally by all REST calls.
- `BuildQueryString(filter)`: Converts a filter hashtable into a URL query string.
  Example: `$client.BuildQueryString(@{ status = 'onboarding_open_dns' })`
- `GetPaged(relativePath, filter)`: Reads a paginated NetBox endpoint to completion.
  Example: `$client.GetPaged('/api/ipam/prefixes/', @{ status = 'onboarding_open_dns_dhcp' })`
- `GetIpAddressById(ipAddressId)`: Loads a single NetBox IP address object by id.
  Example: `$client.GetIpAddressById(101)`
- `GetSiteById(siteId)`: Loads a single NetBox site object by id.
  Example: `$client.GetSiteById(17)`
- `GetOpenPrefixWorkItems(environment)`: Returns prefix work items ready for prefix onboarding.
  Example: `$client.GetOpenPrefixWorkItems($environment)`
- `GetMostSpecificPrefixForAddress(address)`: Returns the most specific prefix containing an IP.
  Example: `$client.GetMostSpecificPrefixForAddress('10.20.30.10')`
- `GetIpWorkItems(environment, statuses)`: Returns IP work items for the requested statuses and environment.
  Example: `$client.GetIpWorkItems($environment, @('onboarding_open_dns'))`
- `UpdatePrefixTicketUrl(prefixId, ticketUrl)`: Writes the Jira ticket URL back to a prefix custom field.
  Example: `$client.UpdatePrefixTicketUrl(7, 'https://jira.example.test/browse/TCO-7')`
- `MarkPrefixOnboardingDone(prefixId)`: Sets a prefix to `onboarding_done_dns_dhcp`.
  Example: `$client.MarkPrefixOnboardingDone(7)`
- `UpdateIpStatus(ipId, status)`: Sets the status of an IP address.
  Example: `$client.UpdateIpStatus(20, 'onboarding_done_dns')`
- `AddJournalEntry(targetType, targetId, message, kind)`: Writes a journal entry to a prefix or IP.
  Example: `$client.AddJournalEntry('Prefix', 7, 'Completed.', 'info')`
- `GetPrefixUrl(prefixId)`: Returns the deep link URL for a prefix.
  Example: `$client.GetPrefixUrl(7)`
- `GetIpAddressUrl(ipAddressId)`: Returns the deep link URL for an IP address.
  Example: `$client.GetIpAddressUrl(20)`

### `JiraClient`
Description:
Wraps Jira REST interactions for prerequisite tickets and status transitions.

Example:
`[JiraClient]::new($jiraCredential)`

Methods:
- `JiraClient(credential)`: Creates a Jira API client.
  Example: `[JiraClient]::new($credential)`
- `GetHeaders()`: Builds the REST headers for Jira requests.
  Example: Used internally by all Jira REST calls.
- `GetTicketKeyFromUrl(jiraUrl)`: Extracts the Jira issue key from a browse URL.
  Example: `$client.GetTicketKeyFromUrl('https://jira.example.test/browse/TCO-7')`
- `GetTicketStatus(ticketKey)`: Loads the current Jira status for a ticket.
  Example: `$client.GetTicketStatus('TCO-7')`
- `SetTicketStatus(ticketKey, targetStatus)`: Transitions a Jira ticket to a target status.
  Example: `$client.SetTicketStatus('TCO-7', 'Verify')`
- `EnsureTicketClosed(jiraUrl)`: Drives an existing Jira ticket to the closed state if needed.
  Example: `$client.EnsureTicketClosed('https://jira.example.test/browse/TCO-7')`
- `CreatePrerequisiteTicket(workItem, forestShortName, dnsZoneDelegated)`: Creates a Jira ticket describing missing prerequisites.
  Example: `$client.CreatePrerequisiteTicket($workItem, 'MTU', $false)`

### `ActiveDirectoryAdapter`
Description:
Reads required Active Directory metadata such as forest, domain and subnet site mapping.

Example:
`[ActiveDirectoryAdapter]::new()`

Methods:
- `GetDomainControllerName()`: Returns the current AD domain controller name.
  Example: `$adapter.GetDomainControllerName()`
- `GetDomainDnsRoot()`: Returns the current AD DNS root.
  Example: `$adapter.GetDomainDnsRoot()`
- `GetForestShortName(domain)`: Maps the forest to a short name used in Jira subjects.
  Example: `$adapter.GetForestShortName('de.mtu.corp')`
- `GetSubnetSite(subnet, domainController)`: Resolves the AD site name for a subnet.
  Example: `$adapter.GetSubnetSite([IPv4Subnet]::new('10.20.30.0/24'), 'dc01.example.test')`

### `DnsServerAdapter`
Description:
Wraps DNS zone discovery, reverse-delegation checks and DNS record management.

Example:
`[DnsServerAdapter]::new()`

Methods:
- `FindBestReverseZoneName(subnet, dnsComputerName)`: Finds the most specific matching reverse zone.
  Example: `$adapter.FindBestReverseZoneName([IPv4Subnet]::new('10.20.30.0/24'), 'dc01.example.test')`
- `TestReverseZoneDelegation(subnet, domain)`: Checks whether the reverse zone is delegated into the expected domain.
  Example: `$adapter.TestReverseZoneDelegation([IPv4Subnet]::new('10.20.30.0/24'), 'de.mtu.corp')`
- `GetRelativeDnsName(dnsName, dnsZone)`: Converts an FQDN to its relative record name when it belongs to the zone.
  Example: `$adapter.GetRelativeDnsName('host.de.mtu.corp', 'de.mtu.corp')`
- `GetPtrOwnerName(reverseZone, ipAddress)`: Derives the PTR owner name inside a reverse zone.
  Example: `$adapter.GetPtrOwnerName('30.20.10.in-addr.arpa', [IPv4Address]::new('10.20.30.10'))`
- `RemoveDnsRecordsForIp(dnsServer, dnsZone, reverseZone, ipAddress)`: Deletes A and PTR records related to an IP.
  Example: `$adapter.RemoveDnsRecordsForIp('dc01', 'de.mtu.corp', '30.20.10.in-addr.arpa', [IPv4Address]::new('10.20.30.10'))`
- `EnsureDnsRecordsForIp(dnsServer, dnsZone, dnsName, ipAddress, reverseZone, ptrDomainName)`: Ensures the desired A and PTR records exist.
  Example: `$adapter.EnsureDnsRecordsForIp('dc01', 'de.mtu.corp', 'host.de.mtu.corp', [IPv4Address]::new('10.20.30.10'), '30.20.10.in-addr.arpa', 'host.de.mtu.corp')`

### `DhcpServerAdapter`
Description:
Wraps DHCP server discovery and scope provisioning operations.

Example:
`[DhcpServerAdapter]::new()`

Methods:
- `GetSitePattern(site, isDevelopment)`: Maps a site code to the DHCP server naming pattern.
  Example: `$adapter.GetSitePattern('muc', $true)`
- `IsPrimaryServer(dhcpServer)`: Checks whether a DHCP server is the primary one.
  Example: `$adapter.IsPrimaryServer('m-dhcp02.de.mtu.corp')`
- `GetCurrentDomainSuffix()`: Returns the current AD domain suffix for server filtering.
  Example: `$adapter.GetCurrentDomainSuffix()`
- `GetPrimaryServerForSite(site, isDevelopment)`: Returns the preferred DHCP server for a site.
  Example: `$adapter.GetPrimaryServerForSite('muc', $false)`
- `EnsureScope(dhcpServer, definition)`: Creates or updates a DHCP scope from a scope definition.
  Example: `$adapter.EnsureScope('m-dhcp02.de.mtu.corp', $definition)`
- `EnsureScopeFailover(dhcpServer, subnet)`: Adds a scope to the first available failover relationship if one exists.
  Example: `$adapter.EnsureScopeFailover('m-dhcp02.de.mtu.corp', [IPv4Subnet]::new('10.20.30.0/24'))`
- `RemoveScope(dhcpServer, subnet)`: Reserved future seam for prefix decommissioning.
  Example: `$adapter.RemoveScope('m-dhcp02.de.mtu.corp', [IPv4Subnet]::new('10.20.30.0/24'))`

### `SmtpMailClient`
Description:
Sends HTML notification mails through the domain SMTP relay.

Example:
`[SmtpMailClient]::new($activeDirectoryAdapter)`

Methods:
- `SmtpMailClient(activeDirectoryAdapter)`: Creates a mail client using AD to resolve the SMTP relay domain.
  Example: `[SmtpMailClient]::new($activeDirectoryAdapter)`
- `SendHtmlMail(recipients, subject, htmlBody)`: Sends one HTML mail message.
  Example: `$mailClient.SendHtmlMail(@('ops@example.test'), 'DHCPScopeAutomation', '<p>Done</p>')`

### `WorkItemLogService`
Description:
Creates relative log paths and writes work-item specific log files.

Example:
`[WorkItemLogService]::new('logs')`

Methods:
- `WorkItemLogService(logBasePath)`: Creates the logging service and ensures the base path exists.
  Example: `[WorkItemLogService]::new('logs')`
- `SanitizeIdentifier(identifier)`: Converts a work item identifier into a file-safe fragment.
  Example: `$service.SanitizeIdentifier('10.20.30.0/24')`
- `CreateLogPath(category, identifier)`: Returns the relative log file path for a work item.
  Example: `$service.CreateLogPath('network', '10.20.30.0/24')`
- `WriteLog(relativePath, lines)`: Writes a log file under the base path.
  Example: `$service.WriteLog('network_10.20.30.0_24.log', @('Started'))`

### `WorkItemJournalService`
Description:
Normalizes journal content and writes it back to NetBox.

Example:
`[WorkItemJournalService]::new($netBoxClient)`

Methods:
- `WorkItemJournalService(netBoxClient)`: Creates the journal service.
  Example: `[WorkItemJournalService]::new($netBoxClient)`
- `JoinLines(lines)`: Converts line arrays into NetBox-compatible HTML line breaks.
  Example: `$service.JoinLines(@('Line1', 'Line2'))`
- `WriteEntry(targetType, targetId, lines, kind)`: Writes one journal entry to NetBox.
  Example: `$service.WriteEntry('Prefix', 7, @('Completed'), 'info')`
- `WritePrefixInfo(workItem, lines)`: Writes an informational prefix journal entry.
  Example: `$service.WritePrefixInfo($workItem, @('Completed'))`
- `WritePrefixError(workItem, lines)`: Writes an error prefix journal entry.
  Example: `$service.WritePrefixError($workItem, @('Failed'))`
- `WriteIpInfo(workItem, lines)`: Writes an informational IP journal entry.
  Example: `$service.WriteIpInfo($workItem, @('Completed'))`
- `WriteIpError(workItem, lines)`: Writes an error IP journal entry.
  Example: `$service.WriteIpError($workItem, @('Failed'))`

## Application

### `PrerequisiteValidationService`
Description:
Evaluates whether a prefix is ready for provisioning before side effects begin.

Example:
`[PrerequisiteValidationService]::new($activeDirectoryAdapter, $dnsServerAdapter, $jiraClient)`

Methods:
- `PrerequisiteValidationService(activeDirectoryAdapter, dnsServerAdapter, jiraClient)`: Creates the validation service.
  Example: `[PrerequisiteValidationService]::new($ad, $dns, $jira)`
- `Evaluate(workItem, environment)`: Returns a `PrerequisiteEvaluation` describing whether processing can continue.
  Example: `$service.Evaluate($prefixWorkItem, $environment)`

### `DhcpServerSelectionService`
Description:
Maps environment and AD site information to the correct DHCP server choice.

Example:
`[DhcpServerSelectionService]::new($dhcpServerAdapter)`

Methods:
- `DhcpServerSelectionService(dhcpServerAdapter)`: Creates the selection service.
  Example: `[DhcpServerSelectionService]::new($adapter)`
- `SelectServer(environment, adSite)`: Returns the server to use for the current environment and site.
  Example: `$service.SelectServer($environment, 'MUC')`

### `GatewayDnsService`
Description:
Provides a facade over DNS actions for gateway and host records.

Example:
`[GatewayDnsService]::new($activeDirectoryAdapter, $dnsServerAdapter)`

Methods:
- `GatewayDnsService(activeDirectoryAdapter, dnsServerAdapter)`: Creates the DNS facade.
  Example: `[GatewayDnsService]::new($ad, $dns)`
- `ResolveDnsExecutionContext(subnet)`: Resolves domain controller and reverse zone for a subnet.
  Example: `$service.ResolveDnsExecutionContext([IPv4Subnet]::new('10.20.30.0/24'))`
- `EnsurePrefixGatewayDns(workItem)`: Ensures the gateway DNS records for a prefix.
  Example: `$service.EnsurePrefixGatewayDns($prefixWorkItem)`
- `EnsureIpDns(workItem)`: Ensures the forward and reverse DNS records for an IP onboarding item.
  Example: `$service.EnsureIpDns($ipWorkItem)`
- `RemoveIpDns(workItem)`: Removes the forward and reverse DNS records for an IP decommissioning item.
  Example: `$service.RemoveIpDns($ipWorkItem)`

### `OperationIssueMailFormatter`
Description:
Formats grouped issues into an HTML failure mail body.

Example:
`[OperationIssueMailFormatter]::new()`

Methods:
- `EscapeHtml(value)`: Escapes text for safe HTML output.
  Example: `$formatter.EscapeHtml('<test>')`
- `GroupByDepartment(issues)`: Groups issues by effective handling department.
  Example: `$formatter.GroupByDepartment($issues)`
- `BuildIssueMarkup(issue)`: Formats one issue as HTML list item markup.
  Example: `$formatter.BuildIssueMarkup($issue)`
- `BuildDepartmentSection(department, issues)`: Formats one department block.
  Example: `$formatter.BuildDepartmentSection('FIST', $issues)`
- `BuildFailureSummaryBody(issues)`: Builds the full grouped failure mail body.
  Example: `$formatter.BuildFailureSummaryBody($issues)`

### `BatchNotificationService`
Description:
Collects failures from all summaries and sends the grouped failure mail.

Example:
`[BatchNotificationService]::new($mailClient, [OperationIssueMailFormatter]::new())`

Methods:
- `BatchNotificationService(mailClient, mailFormatter)`: Creates the notification service.
  Example: `[BatchNotificationService]::new($mailClient, $formatter)`
- `CollectIssues(summaries)`: Flattens issues from multiple batch summaries.
  Example: `$service.CollectIssues($summaries)`
- `SendFailureSummary(recipients, summaries)`: Sends the grouped failure summary if there are issues.
  Example: `$service.SendFailureSummary(@('ops@example.test'), $summaries)`

### `PrefixOnboardingService`
Description:
Implements the end-to-end prefix onboarding workflow.

Example:
`[PrefixOnboardingService]::new($netBox, $ad, $jira, $prerequisites, $selector, $dhcp, $dnsFacade, $journal, $log)`

Methods:
- `PrefixOnboardingService(...)`: Creates the prefix onboarding orchestrator.
  Example: See example above.
- `ProcessBatch(environment)`: Loads open prefix work items and processes them.
  Example: `$service.ProcessBatch($environment)`
- `ProcessWorkItems(environment, workItems)`: Processes a supplied set of prefix work items.
  Example: `$service.ProcessWorkItems($environment, @($workItem))`
- `ProcessWorkItem(environment, workItem, summary)`: Internal per-item workflow shell.
  Example: Called internally by `ProcessWorkItems`.
- `HandleBlockedPrerequisites(workItem, evaluation, lines, summary)`: Applies the blocked-prefix policy, including Jira creation.
  Example: Called internally when prerequisites fail.
- `CompleteNoDhcpPrefix(workItem, lines, summary)`: Completes the `no_dhcp` branch.
  Example: Called internally for `no_dhcp` prefixes.
- `CompleteDhcpBackedPrefix(environment, workItem, evaluation, lines, summary)`: Completes the DHCP-backed provisioning branch.
  Example: Called internally for DHCP-backed prefixes.
- `HandleProcessingFailure(workItem, lines, summary, exception)`: Converts a failure into journal and issue output.
  Example: Called internally when prefix processing throws.
- `BuildFailureHandlingContext(workItem, exception)`: Central seam for future department/handler routing.
  Example: Overridable failure-context hook.
- `WriteExecutionLog(workItem, lines)`: Writes the work-item log and returns the augmented line list.
  Example: Called internally before journaling.

### `IpDnsLifecycleService`
Description:
Implements one shared workflow shell for IP DNS onboarding and decommissioning.

Example:
`[IpDnsLifecycleService]::new('onboarding', $netBox, $dnsFacade, $journal, $log)`

Methods:
- `IpDnsLifecycleService(mode, netBoxClient, gatewayDnsService, journalService, logService)`: Creates the lifecycle service in one mode.
  Example: `[IpDnsLifecycleService]::new('decommissioning', $netBox, $dnsFacade, $journal, $log)`
- `InitializeMode(mode)`: Configures the mode-specific process names and statuses.
  Example: Called internally by the constructor.
- `ProcessBatch(environment)`: Loads matching IP work items and processes them.
  Example: `$service.ProcessBatch($environment)`
- `ProcessWorkItems(environment, workItems)`: Processes supplied IP work items.
  Example: `$service.ProcessWorkItems($environment, @($workItem))`
- `ProcessWorkItem(workItem, summary)`: Internal per-item workflow shell.
  Example: Called internally by `ProcessWorkItems`.
- `ValidateWorkItem(workItem)`: Applies mode-specific validation rules to one work item.
  Example: Called internally before DNS changes.
- `ExecuteDnsLifecycle(workItem)`: Dispatches to ensure or remove DNS based on mode.
  Example: Called internally after validation.
- `HandleProcessingFailure(workItem, lines, summary, exception)`: Converts an IP failure into journal and issue output.
  Example: Called internally when IP processing throws.
- `BuildFailureHandlingContext(workItem, exception)`: Central seam for future department/handler routing.
  Example: Overridable failure-context hook.
- `WriteExecutionLog(workItem, lines)`: Writes the IP work-item log and returns the augmented line list.
  Example: Called internally before journaling.
- `GetLifecycleDisplayName()`: Returns the human-readable mode name.
  Example: `$service.GetLifecycleDisplayName()`
- `GetProcessingLine(workItem)`: Returns the start log line for one work item.
  Example: `$service.GetProcessingLine($workItem)`
- `GetDnsLifecycleResultLine()`: Returns the success log line for the DNS action.
  Example: `$service.GetDnsLifecycleResultLine()`
- `GetSuccessSummaryMessage(workItem)`: Returns the success summary message for one work item.
  Example: `$service.GetSuccessSummaryMessage($workItem)`
- `GetFailureMessage(workItem, exception)`: Returns the failure message for one work item.
  Example: `$service.GetFailureMessage($workItem, $exception)`

### `AutomationCoordinator`
Description:
Acts as the facade over the enabled application services for one run.

Example:
`[AutomationCoordinator]::new($prefixService, $ipOnboardingService, $ipDecommissioningService, $notificationService)`

Methods:
- `AutomationCoordinator(prefixOnboardingService, ipDnsOnboardingService, ipDnsDecommissioningService, batchNotificationService)`: Creates the run coordinator.
  Example: See example above.
- `Run(environment, emailRecipients, sendFailureMail, skipPrefixOnboarding, skipIpDnsOnboarding, skipIpDnsDecommissioning)`: Executes the enabled workflows and optionally sends the failure summary mail.
  Example: `$coordinator.Run($environment, @('ops@example.test'), $true, $false, $false, $false)`

## Composition

### `AutomationRuntime`
Description:
Holds the fully assembled runtime dependencies for one execution.

Example:
`[AutomationRuntime]::new($environment, @('ops@example.test'), $coordinator, $logService)`

Methods:
- `AutomationRuntime(environment, emailRecipients, coordinator, logService)`: Creates a validated runtime container.
  Example: See example above.
- `Execute(sendFailureMail, skipPrefixOnboarding, skipIpDnsOnboarding, skipIpDnsDecommissioning)`: Runs the coordinator with the resolved runtime state.
  Example: `$runtime.Execute($true, $false, $false, $false)`

### `AutomationRuntimeFactoryBase`
Description:
Defines the extension seam for creating a runtime, mainly used by tests and advanced hosts.

Example:
`[AutomationRuntimeFactoryBase]::new()`

Methods:
- `CreateRuntime()`: Abstract creation method that derived factories must implement.
  Example: `$factory.CreateRuntime()`

### `AutomationRuntimeFactory`
Description:
Composition root that builds the runtime from relative config files, credentials and concrete adapters.

Example:
`[AutomationRuntimeFactory]::new($null, $null, '.env', '.secureCreds')`

Methods:
- `AutomationRuntimeFactory(requestedEnvironment, requestedEmailRecipients, configurationPath, credentialDirectory)`: Captures requested runtime overrides and file paths.
  Example: `[AutomationRuntimeFactory]::new('prod', @('ops@example.test'), '.env', '.secureCreds')`
- `CreateRuntime()`: Builds the full concrete runtime graph.
  Example: `$factory.CreateRuntime()`
- `ResolveEnvironment(configurationProvider)`: Resolves the environment from input or config.
  Example: `$factory.ResolveEnvironment($configurationProvider)`
- `ResolveEmailRecipients(configurationProvider)`: Resolves recipient addresses from input or config.
  Example: `$factory.ResolveEmailRecipients($configurationProvider)`

## Top-Level Functions

### `Import-AutomationDependencies`
Description:
Imports the Windows modules required by AD, DHCP and DNS adapters.

Example:
`Import-AutomationDependencies`

### `Write-AutomationLogEntry`
Description:
Routes one audit entry to the matching PowerShell stream.

Example:
`Write-AutomationLogEntry -Entry ([OperationAuditEntry]::new('Information', 'Completed.'))`

### `Write-AutomationRunLog`
Description:
Writes one run-wide summary log file for the current execution.

Example:
`Write-AutomationRunLog -Runtime $runtime -Summaries $summaries`

### `Convert-BatchRunSummaryToPublicObject`
Description:
Converts the internal class-based summary model into public `PSCustomObject` results.

Example:
`Convert-BatchRunSummaryToPublicObject -Summary $summary`

### `Start-DhcpScopeAutomation`
Description:
Public entry point that imports dependencies, creates the runtime, executes enabled workflows, writes logs and returns public summaries.

Example:
`Start-DhcpScopeAutomation -Environment prod`
