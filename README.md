# DHCPScopeAutomation

`DHCPScopeAutomation` is a Windows PowerShell 5.1 module that automates DHCP scope provisioning and DNS lifecycle work based on data from NetBox and Jira.

It is a clean-code rewrite of a legacy scope automation script. The rewrite keeps the original operational intent, but reorganizes the code into small classes with clear responsibilities, explicit orchestration, stronger validation, structured error handling, test seams, and high automated test coverage.

## What The Project Does

This project automates network-related provisioning workflows that were previously implemented in one large legacy script.

At a high level it does the following:

- Reads open work items from NetBox.
- Validates whether a prefix is ready for automated provisioning.
- Creates or closes Jira prerequisite tickets when manual work is still required.
- Provisions DHCP scopes on the selected DHCP server when a prefix is DHCP-backed.
- Ensures gateway DNS records for provisioned prefixes.
- Ensures forward and reverse DNS records for IP address onboarding.
- Removes forward and reverse DNS records for IP address decommissioning.
- Writes journal entries back to NetBox.
- Writes structured log files for the run and for individual work items.
- Aggregates failures into a grouped notification mail.

The current rewrite supports these use cases:

- `Prefix onboarding`
  - Reads NetBox prefixes in status `onboarding_open_dns_dhcp`
  - Validates AD site, reverse zone and delegation prerequisites
  - Creates a Jira prerequisite ticket when automation cannot proceed yet
  - Provisions DHCP scopes for `dhcp_dynamic` and `dhcp_static`
  - Handles `no_dhcp` prefixes without creating a DHCP scope
  - Updates NetBox to `onboarding_done_dns_dhcp`

- `IP DNS onboarding`
  - Reads NetBox IP addresses in status `onboarding_open_dns`
  - Ensures A and PTR records
  - Updates NetBox to `onboarding_done_dns`

- `IP DNS decommissioning`
  - Reads NetBox IP addresses in status `decommissioning_open_dns`
  - Removes A and PTR records
  - Updates NetBox to `decommissioning_done_dns`

The architecture is also intentionally prepared for a future use case:

- `Prefix decommissioning`
  - Not implemented yet
  - The code already keeps an explicit seam for removing DHCP scopes and extending the lifecycle later

## How The Project Is Organized

The module is split into focused class files instead of one monolithic script.

### Top-Level Layout

- [DHCPScopeAutomation.psd1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/DHCPScopeAutomation.psd1)
  - Module manifest
- [DHCPScopeAutomation.psm1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/DHCPScopeAutomation.psm1)
  - Module entry point
- [Classes](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Classes)
  - Split PowerShell class files
- [Private](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Private)
  - Internal helper functions
- [Public](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Public)
  - Public commands exported by the module
- [Tests](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Tests)
  - Pester tests
- [Scripts](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Scripts)
  - Validation and compatibility scripts
- [docs](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/docs)
  - Reverse engineering, implementation notes and API reference

### Architectural Layers

#### `Classes/Domain`

Pure domain and value objects.

Examples:
- `IPv4Address`
- `IPv4Subnet`
- `DhcpRange`
- `DhcpScopeDefinition`
- `PrefixWorkItem`
- `IpAddressWorkItem`
- `BatchRunSummary`
- `OperationIssue`

These classes model the business concepts and normalize data before infrastructure code is called.

#### `Classes/Infrastructure`

Adapters around external systems and low-level concerns.

Examples:
- `NetBoxClient`
- `JiraClient`
- `ActiveDirectoryAdapter`
- `DnsServerAdapter`
- `DhcpServerAdapter`
- `SmtpMailClient`
- `WorkItemLogService`
- `WorkItemJournalService`

These classes are where the project touches external APIs, Windows modules, file system logging, or message delivery.

#### `Classes/Application`

Use-case orchestration and façade-style services.

Examples:
- `PrefixOnboardingService`
- `IpDnsLifecycleService`
- `GatewayDnsService`
- `PrerequisiteValidationService`
- `AutomationCoordinator`

These classes coordinate domain objects and infrastructure adapters into business workflows.

#### `Classes/Composition`

Runtime wiring and composition root.

Examples:
- `AutomationRuntime`
- `AutomationRuntimeFactory`
- `AutomationRuntimeFactoryBase`

These classes assemble the object graph from config, credentials and concrete adapters.

### Class Loading

The module now loads only the split class files in dependency order through:

- [ImportClasses.ps1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Classes/ImportClasses.ps1)

There is no longer a generated `AllClasses.ps1`.

## Public Entry Point

The module currently exports one command:

- `Start-DhcpScopeAutomation`

Source:
- [Start-DhcpScopeAutomation.ps1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Public/Start-DhcpScopeAutomation.ps1)

This command:

1. Imports required Windows modules unless explicitly skipped.
2. Resolves environment and recipients from arguments or `.env`.
3. Loads credentials from `.secureCreds`.
4. Builds the runtime object graph.
5. Runs the enabled workflows.
6. Writes run and work-item logs.
7. Returns public summary objects.

## Requirements

Runtime target:

- Windows PowerShell `5.1`

Windows modules expected in a real infrastructure run:

- `ActiveDirectory`
- `DhcpServer`
- `DnsServer`

External systems expected by the real workflow:

- NetBox
- Jira
- Active Directory
- Microsoft DNS
- Microsoft DHCP
- SMTP relay

## Configuration

The default runtime configuration is read from a relative `.env` file.

Example:

```ini
Environment=dev
EmailRecipients=no-reply@example.com
```

Sample:
- [Samples/.env.example](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Samples/.env.example)

Expected keys:

- `Environment`
  - one of `dev`, `test`, `prod`, `gov`, `china`
- `EmailRecipients`
  - comma-separated recipient list

## Credentials

By default the module reads persisted credentials from:

- `.secureCreds`

Expected credential files are loaded through `SecureFileCredentialProvider`.

Typical files:

- `DHCPScopeAutomationNetboxApiKey.xml`
- `DHCPScopeAutomationJiraApiKey.xml`

These are expected to contain:

- `Appliance`
- `ApiKey`

The `ApiKey` is stored as a secure string using PowerShell XML serialization.

## How To Start The Project

### 1. Open Windows PowerShell 5.1

Use `powershell.exe`, not `pwsh`, when validating the target runtime.

### 2. Go To The Project Directory

```powershell
Set-Location 'C:\path\to\DHCPScopeAutomation'
```

### 3. Prepare `.env`

Create a `.env` file in the project root:

```ini
Environment=prod
EmailRecipients=ops@example.test,net@example.test
```

### 4. Prepare `.secureCreds`

Create the `.secureCreds` directory and place the required credential XML files there.

### 5. Import The Module

```powershell
Import-Module .\DHCPScopeAutomation.psd1 -Force
```

### 6. Start The Automation

```powershell
Start-DhcpScopeAutomation
```

This will use:

- `.env`
- `.secureCreds`
- imported Windows infrastructure modules

### Explicit Start Examples

Run against an explicit environment:

```powershell
Start-DhcpScopeAutomation -Environment prod
```

Run without sending failure mail:

```powershell
Start-DhcpScopeAutomation -Environment test -SkipFailureMail
```

Run when the current session already imported the Windows modules:

```powershell
Start-DhcpScopeAutomation -SkipDependencyImport
```

Run only part of the workflow:

```powershell
Start-DhcpScopeAutomation -SkipIpDnsOnboarding -SkipIpDnsDecommissioning
```

## Returned Result

`Start-DhcpScopeAutomation` returns an array of public summary objects.

Each summary contains:

- `ProcessName`
- `StartedUtc`
- `FinishedUtc`
- `SuccessCount`
- `FailureCount`
- `Issues`
- `AuditEntries`

This makes the command usable both interactively and from schedulers or wrappers.

## Logging And Error Handling

The rewrite does not rely on `Write-Host`-driven scripting. Instead it uses:

- structured audit entries
- typed failure objects
- grouped notification formatting
- per-work-item log files
- one run summary log
- degraded warning behavior for secondary failures such as journal write errors

Failures are represented as `OperationIssue` objects and are designed to support future routing metadata such as:

- owning department
- assigned handler

This routing model is already prepared in the code, even though the actual department assignment rules are not yet implemented.

## Testing

The project has automated Pester tests and is designed to test as much behavior as possible without touching real infrastructure.

Test entry point:

- [Run-Tests.ps1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Tests/Run-Tests.ps1)

Run tests:

```powershell
.\Tests\Run-Tests.ps1
```

The tests cover:

- domain objects
- orchestration services
- blackbox public command behavior
- infrastructure adapters through isolated command overrides
- logging and conversion helpers

## PowerShell 5.1 Compatibility Check

Compatibility script:

- [Test-PowerShell51Compatibility.ps1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Scripts/Test-PowerShell51Compatibility.ps1)

Run it with:

```powershell
.\Scripts\Test-PowerShell51Compatibility.ps1
```

This performs a compatibility-oriented analyzer pass for PowerShell 5.1 syntax, commands and types.

## Documentation

Further project documentation:

- [ClassAndFunctionReference.md](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/docs/ClassAndFunctionReference.md)
  - detailed class and function reference
- [ReverseEngineering-DHCPScopeAutomationOld.md](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/docs/ReverseEngineering-DHCPScopeAutomationOld.md)
  - reverse engineering of the legacy automation
- [ImplementationPlan-PowerShell5-Rewrite.md](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/docs/ImplementationPlan-PowerShell5-Rewrite.md)
  - rewrite structure and sequencing
- [PowerShellDocumentationStandards.md](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/docs/PowerShellDocumentationStandards.md)
  - project documentation conventions
- [TestStrategy-PowerShell5.md](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/docs/TestStrategy-PowerShell5.md)
  - testing strategy and coverage direction

## Current Status

Current implemented lifecycle:

- prefix onboarding
- IP DNS onboarding
- IP DNS decommissioning

Prepared but not implemented:

- prefix decommissioning

The codebase is intentionally structured so future lifecycle extensions can be added as new use cases instead of expanding one giant script.
