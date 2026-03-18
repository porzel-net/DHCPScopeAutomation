# Class Relationship Graphs

Dieses Dokument visualisiert die wichtigsten Beziehungen im Projekt
`DHCPScopeAutomation`, damit neue Entwickler schneller verstehen können,
welche Klassen welche Verantwortung tragen und wie die Use Cases aufgebaut sind.

## 1. Layer Overview

```mermaid
flowchart TB
    Public["Public Entry Point\nStart-DhcpScopeAutomation"] --> Composition["Composition Layer\nRuntime + Factory"]
    Composition --> Application["Application Layer\nUse Cases + Orchestration"]
    Application --> Domain["Domain Layer\nValue Objects + Result Models"]
    Application --> Infrastructure["Infrastructure Layer\nAD, DNS, DHCP, NetBox, Jira, Mail, Files"]
    Infrastructure --> Domain
```

### Bedeutung

- `Public` enthält den Startpunkt des Moduls.
- `Composition` baut den Objektgraphen zusammen.
- `Application` enthält die fachlichen Workflows.
- `Domain` enthält die fachlichen Datenstrukturen.
- `Infrastructure` kapselt alle externen Systeme und PowerShell-Cmdlets.

## 2. Runtime Composition

```mermaid
flowchart LR
    Start["Start-DhcpScopeAutomation"] --> FactoryBase["AutomationRuntimeFactoryBase"]
    FactoryBase --> Factory["AutomationRuntimeFactory"]
    Factory --> Runtime["AutomationRuntime"]
    Runtime --> Coordinator["AutomationCoordinator"]

    Coordinator --> Prefix["PrefixOnboardingService"]
    Coordinator --> IpOn["IpDnsLifecycleService\nmode=onboarding"]
    Coordinator --> IpOff["IpDnsLifecycleService\nmode=decommissioning"]
    Coordinator --> Notify["BatchNotificationService"]

    Notify --> MailFormatter["OperationIssueMailFormatter"]
    Notify --> MailClient["SmtpMailClient"]
```

### Bedeutung

- `AutomationRuntimeFactory` ist die Composition Root.
- `AutomationRuntime` hält die fertig aufgelöste Laufzeit.
- `AutomationCoordinator` ist die Fassade über alle aktivierten Use Cases.
- `IpDnsLifecycleService` wird zweimal mit unterschiedlichem Modus instanziiert.

## 3. Prefix Onboarding Dependencies

```mermaid
flowchart LR
    Prefix["PrefixOnboardingService"] --> NetBox["NetBoxClient"]
    Prefix --> AD["ActiveDirectoryAdapter"]
    Prefix --> Jira["JiraClient"]
    Prefix --> Validation["PrerequisiteValidationService"]
    Prefix --> DhcpSelect["DhcpServerSelectionService"]
    Prefix --> Dhcp["DhcpServerAdapter"]
    Prefix --> GatewayDns["GatewayDnsService"]
    Prefix --> Journal["WorkItemJournalService"]
    Prefix --> Log["WorkItemLogService"]

    Validation --> AD
    Validation --> DNS["DnsServerAdapter"]
    Validation --> Jira

    DhcpSelect --> Dhcp

    GatewayDns --> AD
    GatewayDns --> DNS

    Journal --> NetBox
```

### Bedeutung

- `PrefixOnboardingService` ist der größte Orchestrator.
- Vorbedingungen werden separat über `PrerequisiteValidationService` geprüft.
- DHCP-Serverauswahl ist bewusst aus dem Onboarding-Service extrahiert.
- DNS für Gateway-Namen läuft über die Fassade `GatewayDnsService`.

## 4. Prefix Onboarding Flow

```mermaid
flowchart TD
    A["ProcessBatch"] --> B["Load PrefixWorkItem[] from NetBox"]
    B --> C["ProcessWorkItem"]
    C --> D["Evaluate prerequisites"]
    D --> E{"Can continue?"}

    E -- No --> F{"New Jira ticket required?"}
    F -- Yes --> G["Create Jira ticket"]
    G --> H["Store ticket URL in NetBox"]
    H --> I["Write log + journal"]

    F -- No --> J["Raise failure"]

    E -- Yes --> K{"DHCP type = no_dhcp?"}
    K -- Yes --> L["Ensure gateway DNS"]
    L --> M["Mark prefix onboarding done"]
    M --> N["Write log + journal"]

    K -- No --> O["Build DhcpScopeDefinition"]
    O --> P["Select DHCP server"]
    P --> Q["Ensure DHCP scope"]
    Q --> R["Ensure gateway DNS"]
    R --> S["Ensure failover"]
    S --> T["Mark prefix onboarding done"]
    T --> U["Write log + journal"]

    J --> V["Create OperationIssue"]
    I --> W["Add success to BatchRunSummary"]
    N --> W
    U --> W
    V --> X["Add failure to BatchRunSummary"]
```

### Bedeutung

- Der Ablauf ist Template-Method-artig aufgebaut.
- Fachliche Verzweigungen sitzen in kleinen Methoden statt in einem Monolithen.
- Fehler werden immer in `OperationIssue` übersetzt.

## 5. IP DNS Lifecycle Flow

```mermaid
flowchart TD
    A["IpDnsLifecycleService"] --> B["InitializeMode"]
    B --> C["ProcessBatch"]
    C --> D["Load IpAddressWorkItem[] from NetBox"]
    D --> E["ProcessWorkItem"]
    E --> F["ValidateWorkItem"]
    F --> G["ExecuteDnsLifecycle"]
    G --> H{"Mode?"}
    H -- onboarding --> I["GatewayDnsService.EnsureIpDns"]
    H -- decommissioning --> J["GatewayDnsService.RemoveIpDns"]
    I --> K["Update NetBox IP status"]
    J --> K
    K --> L["Write log + journal"]
    L --> M["Add success summary"]
    E --> N["On exception: HandleProcessingFailure"]
    N --> O["Write error journal if possible"]
    O --> P["Create OperationIssue"]
```

### Bedeutung

- Dieselbe Workflow-Hülle wird für zwei Lebenszyklus-Richtungen wiederverwendet.
- Der Modus bestimmt nur die DNS-Aktion und die Status-/Textvarianten.
- Dadurch bleibt die Logik wiederverwendbar und gut testbar.

## 6. DNS Facade and Adapter Boundary

```mermaid
flowchart LR
    Prefix["PrefixOnboardingService"] --> Gateway["GatewayDnsService"]
    IpLife["IpDnsLifecycleService"] --> Gateway

    Gateway --> AD["ActiveDirectoryAdapter"]
    Gateway --> DNS["DnsServerAdapter"]

    Gateway --> Context["DnsExecutionContext"]

    DNS --> Records["A/PTR Records"]
    DNS --> Reverse["Reverse Zone Resolution"]
    DNS --> Delegation["Delegation Check"]
```

### Bedeutung

- `GatewayDnsService` ist bewusst die Fassade zwischen Use Cases und DNS-Details.
- `DnsExecutionContext` verhindert wiederholte AD-/Reverse-Zonen-Auflösung.
- Die Use Cases kennen keine DNS-Cmdlets direkt.

## 7. Domain Model Overview

```mermaid
classDiagram
    class EnvironmentContext {
        +Name
        +DnsZone
        +IsDevelopment()
        +IsTest()
        +IsProduction()
        +GetDelegationValidationDomain()
    }

    class IPv4Address {
        +Value
        +GetUInt32()
        +AddOffset(offset)
    }

    class IPv4Subnet {
        +Cidr
        +NetworkAddress
        +PrefixLength
        +GetSubnetMaskString()
        +GetBroadcastAddress()
        +GetReverseZoneName()
        +GetAdLookupCandidates()
        +Get24BlockBaseAddresses()
    }

    class DhcpRange {
        +StartAddress
        +EndAddress
        +GatewayAddress
        +BroadcastAddress
        +ReservedAfterGateway
    }

    class DhcpExclusionRange {
        +StartAddress
        +EndAddress
        +MustSucceed
    }

    class DhcpScopeDefinition {
        +Name
        +Subnet
        +SubnetMask
        +Range
        +DnsDomain
        +LeaseDurationDays
        +ConfigureDynamicDns
        +ExclusionRanges
    }

    class PrefixWorkItem {
        +Id
        +PrefixSubnet
        +DHCPType
        +Domain
        +DnsName
        +GetGatewayFqdn()
        +GetIdentifier()
    }

    class IpAddressWorkItem {
        +Id
        +IpAddress
        +Status
        +DnsName
        +Domain
        +PrefixSubnet
        +GetIdentifier()
        +GetFqdn()
    }

    class PrerequisiteEvaluation {
        +CanContinue
        +RequiresNewJiraTicket
        +RequiresExistingJiraWait
        +Reasons
        +AddReason(reason)
    }

    class IssueHandlingContext {
        +Department
        +Handler
        +CreateUnassigned()
    }

    class OperationIssue {
        +WorkItemType
        +WorkItemIdentifier
        +Message
        +Details
        +HandlingContext
        +ResourceUrl
    }

    class BatchRunSummary {
        +ProcessName
        +SuccessCount
        +FailureCount
        +Issues
        +AuditEntries
        +AddSuccess(message)
        +AddFailure(issue)
        +AddAudit(level, message)
        +Complete()
    }

    IPv4Subnet --> IPv4Address
    DhcpRange --> IPv4Address
    DhcpScopeDefinition --> DhcpRange
    DhcpScopeDefinition --> DhcpExclusionRange
    DhcpScopeDefinition --> IPv4Subnet
    PrefixWorkItem --> IPv4Subnet
    PrefixWorkItem --> IPv4Address
    IpAddressWorkItem --> IPv4Address
    IpAddressWorkItem --> IPv4Subnet
    OperationIssue --> IssueHandlingContext
    BatchRunSummary --> OperationIssue
```

### Bedeutung

- `Domain` enthält fast nur Value Objects und Ergebnisobjekte.
- Diese Typen transportieren Fachlogik und Validierung.
- Sie kennen keine externen Systeme wie NetBox, DHCP oder Jira.

## 8. External System Adapters

```mermaid
flowchart TB
    App["Application Layer"] --> NetBox["NetBoxClient\nREST"]
    App --> Jira["JiraClient\nREST"]
    App --> AD["ActiveDirectoryAdapter\nAD Cmdlets"]
    App --> DNS["DnsServerAdapter\nDNS Cmdlets"]
    App --> DHCP["DhcpServerAdapter\nDHCP Cmdlets"]
    App --> Mail["SmtpMailClient\nSMTP"]
    App --> Config["EnvFileConfigurationProvider\n.env file"]
    App --> Creds["SecureFileCredentialProvider\nsecure XML"]
    App --> Logs["WorkItemLogService\nrelative log files"]
    App --> Journal["WorkItemJournalService\nNetBox journals"]
```

### Bedeutung

- Alle externen Abhängigkeiten sind hinter dedizierten Adapterklassen versteckt.
- Dadurch bleibt die Application-Schicht mockbar und testbar.
- Für neue Systeme sollte dieselbe Struktur beibehalten werden.

## 9. What To Read First

Wenn du den Code verstehen willst, ist diese Reihenfolge sinnvoll:

1. [AutomationRuntimeFactory.ps1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Classes/Composition/AutomationRuntimeFactory.ps1)
2. [AutomationCoordinator.ps1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Classes/Application/AutomationCoordinator.ps1)
3. [PrefixOnboardingService.ps1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Classes/Application/PrefixOnboardingService.ps1)
4. [IpDnsLifecycleService.ps1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Classes/Application/IpDnsLifecycleService.ps1)
5. [GatewayDnsService.ps1](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Classes/Application/GatewayDnsService.ps1)
6. die Domain-Typen unter [Classes/Domain](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Classes/Domain)
7. die Adapter unter [Classes/Infrastructure](/Users/juliusporzel/Development/AiTests/DHCPScopeAutomation/Classes/Infrastructure)
