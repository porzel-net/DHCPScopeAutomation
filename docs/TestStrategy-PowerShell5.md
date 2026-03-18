# Test Strategy for DHCPScopeAutomation

## Zielbild

Die Teststrategie soll drei Dinge gleichzeitig erreichen:

- fachliche Sicherheit bei typischen und untypischen Eingaben
- hohe Änderbarkeit des Codes ohne fragile Tests
- klare Trennung zwischen schnellen Whitebox-Tests und realistischen Blackbox-Tests

## Aktueller Stand

Der aktuelle Test-Schnitt deckt vor allem folgende Bereiche gut ab:

- Domain-Logik und Value Objects
- Konfigurations- und Credential-Laden aus relativen Pfaden
- Mail-Formatierung, Logging und private Utility-Funktionen
- zentrale Services wie `PrerequisiteValidationService`, `DhcpServerSelectionService`,
  `GatewayDnsService`, `BatchNotificationService`, `AutomationRuntimeFactory`

Die größten Coverage-Lücken liegen aktuell hier:

- kompletter Entry Point `Start-DhcpScopeAutomation`
- Batch-Orchestrierung in `PrefixOnboardingService` und `IpDnsLifecycleService`
- echte Adapterpfade in `NetBoxClient`, `JiraClient`, `ActiveDirectoryAdapter`,
  `DnsServerAdapter`, `DhcpServerAdapter`
- negative Pfade und Guard-Clauses vieler Konstruktoren und Validierungen

## Testpyramide

### 1. Whitebox Unit Tests

Ziel:

- einzelne Klassen und Methoden isoliert prüfen
- viele Negativfälle abdecken
- sehr schnell laufen

Geeignete Kandidaten:

- alle Value Objects und Work-Item-Konstruktoren
- `DhcpScopeDefinition.FromPrefixWorkItem()`
- `PrerequisiteEvaluation`
- `OperationIssueMailFormatter`
- `EnvFileConfigurationProvider`
- `SecureFileCredentialProvider`
- `AutomationRuntimeFactory.ResolveEnvironment()` und `ResolveEmailRecipients()`

Erweiterung:

- jede Guard Clause bekommt mindestens einen Negativtest
- jede fachliche Verzweigung bekommt mindestens einen Positiv- und einen Negativtest

### 2. Whitebox Service Tests mit Fakes

Ziel:

- Fachabläufe testen, ohne Systemänderungen auszulösen
- Batch- und Fehlerverhalten verlässlich abdecken

Dafür sollten gezielt Fake-Implementierungen verwendet werden für:

- NetBox
- Jira
- DHCP
- DNS
- AD
- Mail
- Journal
- Log-Service

Wichtige Kandidaten:

- `PrefixOnboardingService.ProcessBatch()`
- `IpDnsLifecycleService.ProcessBatch()`
- `AutomationCoordinator.Run()`
- `AutomationRuntime.Execute()`

Wichtig:

- Fakes sollten Aufruflisten mitschreiben
- Fehlerpfade müssen gezielt ausgelöst werden können
- Tests müssen Success-, Blocked- und Failure-Pfade getrennt abdecken

### 3. Blackbox Modul-Tests

Ziel:

- das Modul nur über öffentliche Schnittstellen prüfen
- keine Kenntnis interner Klassen für die Assertion voraussetzen

Hauptkandidat:

- `Start-DhcpScopeAutomation`

Dafür braucht der Code noch bessere Test-Seams:

- `Start-DhcpScopeAutomation` sollte eine Factory oder einen Runtime-Builder injiziert
  bekommen können
- alternativ ein optionaler Parameter wie `-RuntimeFactory` oder `-ServiceProvider`
- die Funktion darf nicht hart nur mit `AutomationRuntimeFactory` arbeiten

Dann werden Blackbox-Tests möglich wie:

- `Start-DhcpScopeAutomation -SkipDependencyImport`
- Rückgabeformat prüfen
- gesetzte Skip-Switches prüfen
- Failure-Mail deaktiviert vs. aktiviert
- Run-Log-Erzeugung prüfen

## Negativtests und Fehlereingaben

Diese Klasse von Tests fehlt aktuell noch deutlich:

- ungültige CIDR-Werte
- ungültige IPv4-Adressen
- leere oder fehlende Pflichtfelder in `PrefixWorkItem` und `IpAddressWorkItem`
- unsupported `DHCPType`
- fehlende `.env`-Keys
- defekte Credential-XML-Dateien
- ungültige Jira-URLs
- leere Empfängerlisten
- ungültige Log-Level
- ungültige `mode`-Werte für `IpDnsLifecycleService`

Regel:

- jeder geworfene fachlich relevante Fehler braucht mindestens einen Test
- jeder `throw` im Domain- und Application-Layer sollte bewusst abgedeckt werden

## Blackbox-Szenarien

Folgende End-to-End-nahen Szenarien sollten ohne echte Infrastruktur als Blackbox laufen:

- nur Prefix-Onboarding aktiv
- nur IP-DNS-Onboarding aktiv
- nur IP-DNS-Decommissioning aktiv
- alle drei aktiviert
- keine Failures
- einzelne Failures
- mehrere Failures mit Gruppierung nach Abteilung
- Run-Log wurde geschrieben
- Rückgabeobjekte haben stabiles Public-Schema

## Whitebox-Szenarien

Diese Whitebox-Pfade sollten zusätzlich gezielt geprüft werden:

- `PrerequisiteValidationService`:
  - keine AD-Site
  - falsche AD-Site
  - keine Reverse-Zone
  - keine Delegation
  - alles erfüllt mit bestehendem Jira-Ticket

- `PrefixOnboardingService`:
  - `no_dhcp`
  - `dhcp_dynamic`
  - `dhcp_static`
  - Jira-Erstellung
  - Fehler beim Journal
  - Fehler bei Gateway-DNS
  - Fehler bei DHCP

- `IpDnsLifecycleService`:
  - Onboarding
  - Decommissioning
  - fehlender DNS-Name
  - Fehler bei DNS-Aktion
  - Fehler bei Journal

- `AutomationCoordinator`:
  - Skip-Schalter korrekt
  - Failure-Mail nur bei Aktivierung
  - Failure-Mail-Fehler erzeugt eigenes Summary

## Coverage-Strategie

Coverage soll nicht nur numerisch, sondern fachlich interpretiert werden.

### Kurzfristiges Ziel

- mindestens 60% Command Coverage
- alle Guard Clauses im Domain-Layer abgedeckt
- alle öffentlichen und orchestrierenden Methoden mindestens einmal ausgeführt

### Mittelfristiges Ziel

- mindestens 75% Command Coverage
- jeder Use Case mit Success-, Blocked- und Failure-Pfad
- `Start-DhcpScopeAutomation` als Blackbox abgedeckt

### Wichtig

Hohe Coverage ist kein Selbstzweck. Priorität haben:

- kritische Fachregeln
- Fehlerbehandlung
- Statuswechsel
- Seiteneffekt-Orchestrierung

## Was im Code verbessert werden sollte, um besser testbar zu sein

### 1. Composition Root entkoppeln

`Start-DhcpScopeAutomation` und `AutomationRuntimeFactory` sind aktuell noch zu fest verdrahtet.
Für Blackbox-Tests braucht es eine injizierbare Runtime-Fabrik.

### 2. Interfaces oder explizite Ports einführen

PowerShell 5 hat keine Interfaces wie in C# in derselben Ergonomie, aber es hilft bereits,
klare Port-Klassen oder Basistypen mit austauschbaren Implementierungen zu etablieren:

- `INetBoxPort`
- `IJiraPort`
- `IDnsPort`
- `IDhcpPort`
- `IActiveDirectoryPort`
- `IMailPort`

Wenn echte Interfaces nicht genutzt werden, dann wenigstens schmale abstrakte Basisklassen
oder gezielte Adapter-Seams.

### 3. Batch-Services weiter zerlegen

`PrefixOnboardingService` und `IpDnsLifecycleService` sollten noch klarer trennen:

- Work-Item laden
- Work-Item ausführen
- Fehler in `OperationIssue` übersetzen
- Journal schreiben
- Log schreiben

Je kleiner die Schritte, desto einfacher die gezielte Whitebox-Abdeckung.

### 4. Öffentliche Rückgabeobjekte stabilisieren

Für Blackbox-Tests ist wichtig, dass `Start-DhcpScopeAutomation` ein bewusst stabiles
Rückgabeformat liefert, das unabhängig von internen Klassenassertions geprüft werden kann.

## Konkreter nächster Test-Backlog

1. Negativtests für alle Value Objects und Work-Item-Konstruktoren ergänzen.
2. Fakes für `PrefixOnboardingService.ProcessBatch()` und `IpDnsLifecycleService.ProcessBatch()` ausbauen.
3. `AutomationCoordinator.Run()` mit Fake-Use-Cases testen.
4. `Start-DhcpScopeAutomation` für Blackbox-Tests über injizierbare Factory refactoren.
5. Danach echte Blackbox-Tests auf Public-Schnittstelle ergänzen.
6. Coverage erneut messen und gezielt auf die noch roten Methoden gehen.

## Testarten im Projekt

- Whitebox:
  Prüft interne Regeln, Verzweigungen, Fehlerpfade und konkrete Kollaboration.

- Blackbox:
  Prüft nur öffentliche Inputs und Outputs ohne Wissen über interne Typen.

- Contract Tests:
  Prüfen stabile Public-Schemas und Rückgabeformate.

- Negative Tests:
  Prüfen Guard Clauses, Exceptions und unerwartete Eingangsdaten.

- Safe Integration Tests:
  Nutzen Fakes oder temporäre Dateien, aber keine echte Systemänderung.
