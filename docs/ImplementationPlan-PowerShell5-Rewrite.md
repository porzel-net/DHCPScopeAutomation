# Implementierungsplan: DHCPScopeAutomation Rewrite für PowerShell 5.x

## Ziel

Dieses Dokument beschreibt den empfohlenen Implementierungsplan für den vollständigen Neuaufbau von `DHCPScopeAutomation` auf Basis von:

- [ReverseEngineering-DHCPScopeAutomationOld.md](./ReverseEngineering-DHCPScopeAutomationOld.md)
- [POWERSHELL_5_CLEAN_CODE.md](../POWERSHELL_5_CLEAN_CODE.md)

Ziel ist kein technischer 1:1-Port des Legacy-Skripts, sondern ein sauber geschnittenes, objektorientiertes, testbares PowerShell-5.x-System mit klaren Infrastrukturgrenzen.

## Leitprinzipien aus der Clean-Code-Vorgabe

Der neue Aufbau sollte die Vorgaben aus `POWERSHELL_5_CLEAN_CODE.md` direkt in die Architektur übersetzen:

- Domain, Application und Infrastructure strikt trennen
- Klassen für Domänenobjekte und kohäsive Services verwenden
- externe I/O an den Rand schieben
- keine Host-Ausgaben als Datenfluss verwenden
- keine fachlichen Regeln in REST-, DHCP-, DNS- oder AD-Adapter mischen
- öffentliche Funktionen klein halten und als Entry Points verwenden
- strukturierte Objekte statt Format-Strings zurückgeben
- Fehler nicht verschlucken, sondern kontextreich propagieren
- Tests primär gegen Domänen- und Application-Logik schreiben
- spätere Erweiterungen wie Prefix-Decommissioning architektonisch vorbereiten

## Empfohlene Zielstruktur

Die Projektstruktur sollte sich an der Clean-Code-Datei orientieren:

- `Classes/Domain/`
- `Classes/Application/`
- `Classes/Infrastructure/`
- `Public/`
- `Private/`
- `Tests/`
- `docs/`

Zusätzlich sinnvoll:

- `Config/`
- `Samples/`

## Architekturübersicht

Das System sollte in drei Ebenen aufgebaut werden.

### 1. Domain Layer

Hier lebt die fachliche Sprache. Keine REST-Aufrufe, kein DHCP-Cmdlet, kein Dateisystem.

Empfohlene Typen:

- `EnvironmentName`
- `DnsZonePolicy`
- `PrefixWorkItem`
- `IpAddressWorkItem`
- `DhcpScopeDefinition`
- `DhcpRange`
- `IPv4Subnet`
- `IPv4Address`
- `DnsRecordDefinition`
- `JiraTicketReference`
- `ProvisioningPrerequisites`
- `ProvisioningDecision`
- `ProcessingResult`

Ziele im Domain Layer:

- Eingaben validieren
- ungültige Zustände verhindern
- Berechnungslogik kapseln
- Entscheidungen modellieren statt inline `if`-Ketten zu verstreuen

### 2. Application Layer

Hier liegt die Orchestrierung der Use Cases.

Empfohlene Services:

- `PrefixOnboardingService`
- `IpDnsOnboardingService`
- `IpDnsDecommissioningService`
- später `PrefixDecommissioningService`
- `PrerequisiteValidationService`
- `DhcpServerSelectionService`
- `NotificationService`
- `JournalService`
- `BatchProcessingService`

Aufgabe:

- Fachabläufe koordinieren
- Entscheidungen aus dem Domain Layer anwenden
- Infrastrukturadapter aufrufen
- Fehler kontextreich behandeln

### 3. Infrastructure Layer

Hier liegen alle Systemgrenzen.

Empfohlene Adapter:

- `NetBoxClient`
- `JiraClient`
- `ActiveDirectoryAdapter`
- `DnsServerAdapter`
- `DhcpServerAdapter`
- `CredentialProvider`
- `EnvironmentConfigProvider`
- `TranscriptLogger`
- `MailClient`
- optional `Clock`

Aufgabe:

- PowerShell-Cmdlets kapseln
- REST-Aufrufe kapseln
- DTOs in Domain-nahe Objekte übersetzen
- Infrastrukturfehler mit brauchbarem Kontext liefern

## Zentrale Designentscheidung: Use Cases statt Monolith

Das Altsystem vermischt mehrere Fachfälle in einem großen Ablauf. Der Rewrite sollte stattdessen mit expliziten Use Cases arbeiten.

Empfohlene Use Cases:

1. `Process-PrefixOnboardingBatch`
2. `Process-IpDnsOnboardingBatch`
3. `Process-IpDnsDecommissioningBatch`
4. später `Process-PrefixDecommissioningBatch`

Wichtig:

- diese Use Cases teilen sich Infrastrukturadapter
- sie teilen sich Teile der Domänenlogik
- sie bleiben aber fachlich getrennt

Das verhindert, dass der neue Code wieder in einem einzigen Skript mit globalem Zustand endet.

## Implementierungsreihenfolge

Die beste Reihenfolge ist nicht entlang externer Systeme, sondern entlang fachlicher Stabilität.

### Phase 1: Technisches Fundament

Zuerst die Basiselemente schaffen, die alle späteren Use Cases benötigen.

Umfang:

- Modulstruktur anlegen
- Composition Root definieren
- Konfigurationsmodell aufbauen
- Credential-Zugriff abstrahieren
- Logging- und Result-Modell definieren
- Basistests und Test-Setup anlegen

Konkrete Ergebnisse:

- ein Root-Modul, das Klassen lädt und öffentliche Commands exportiert
- eine saubere `Initialize-...` oder `New-ApplicationContext`-Funktion
- ein einheitliches Result-Objekt für Erfolg, Warnung, Fehler, Audit-Daten

Warum zuerst:

- ohne stabiles Fundament droht später wieder Kopplung zwischen Use Case und Adapter

### Phase 2: Domain-Value-Objects und Berechnungslogik

Danach die reine Fachlogik ohne Infrastruktur.

Priorität:

- `IPv4Address`
- `IPv4Subnet`
- `DhcpRange`
- `DhcpScopeDefinition`
- DNS-Reverse-Zonen-Berechnung
- DHCP-Range-Regeln
- /24-Exclusion-Regeln
- Gateway-Validierungslogik
- Environment-zu-Domain-Policy

Warum früh:

- diese Regeln sind zentral
- sie sind gut testbar
- sie reduzieren Risiko, bevor externe Systeme ins Spiel kommen

Tests:

- Konstruktorvalidierung
- CIDR-Parsing
- Reverse-Zonen-Berechnung
- Range-Berechnung für `/16`, `/22`, `/24`, `/25`, `/27`
- `dhcp_static`, `dhcp_dynamic`, `no_dhcp`

### Phase 3: Infrastrukturadapter einzeln kapseln

Jetzt die externen Systeme sauber hinter Klassen kapseln.

Reihenfolge:

1. `EnvironmentConfigProvider`
2. `CredentialProvider`
3. `NetBoxClient`
4. `ActiveDirectoryAdapter`
5. `DnsServerAdapter`
6. `DhcpServerAdapter`
7. `JiraClient`
8. `MailClient`

Regeln:

- jeder Adapter bekommt eine klar definierte Verantwortung
- keine Fachentscheidungen in Adaptern
- Adapter liefern strukturierte Objekte, nicht Host-Text
- Exceptions nur mit zusätzlichem Kontext wrappen

Wichtig:

- NetBox und Jira sollten in eigene Request-/Response-Mapping-Methoden getrennt werden
- DHCP-, DNS- und AD-Cmdlets dürfen nicht direkt aus den Application Services aufgerufen werden

### Phase 4: Prerequisite-Validierung als eigener Service

Die größte fachliche Kopplung im Altcode liegt in den Vorbedingungen.

Deshalb einen separaten `PrerequisiteValidationService` bauen.

Er prüft mindestens:

- AD-Site vorhanden
- AD-Site entspricht erwartetem Mandanten
- Reverse-Zone vorhanden
- DNS-Delegation vorhanden
- Jira-Ticket bereits vorhanden oder neu notwendig

Ausgabe sollte kein Bool sein, sondern ein Entscheidungsobjekt, z. B.:

- `CanContinue`
- `RequiresJiraTicket`
- `ExistingTicketRequiresWait`
- `Reasons`
- `ObservedState`

Warum separat:

- das ist ein eigenständiger Fachbaustein
- er wird später auch beim Decommissioning wieder relevant

### Phase 5: Prefix-Onboarding implementieren

Erst jetzt den wichtigsten End-to-End-Use-Case bauen.

Teilaufgaben:

1. offene Präfixe aus NetBox laden
2. in `PrefixWorkItem` mappen
3. Pflichtdaten validieren
4. Vorbedingungen prüfen
5. Jira-Pfade behandeln
6. DHCP-Server auswählen
7. Scope-Definition berechnen
8. DHCP-Scope sicher anlegen oder idempotent erkennen
9. Gateway-DNS pflegen
10. Failover anbinden
11. NetBox-Status aktualisieren
12. Journal-Eintrag schreiben

Wichtig:

- der Use Case darf nicht selbst REST-Payloads bauen
- der Use Case darf nicht selbst CIDR-Rechnung durchführen
- der Use Case darf nicht selbst Cmdlets aufrufen

### Phase 6: IP-DNS-Onboarding implementieren

Danach den kleineren, gut abgrenzbaren Use Case.

Teilaufgaben:

1. offene IPs aus NetBox laden
2. mit Prefix/Domain anreichern
3. auf Ziel-Domain filtern
4. DNS-Vorbedingungen prüfen
5. bestehende A/PTR-Einträge zur IP bereinigen
6. neue DNS-Einträge setzen
7. NetBox-Status aktualisieren
8. Journal schreiben

### Phase 7: IP-DNS-Decommissioning implementieren

Direkt danach den symmetrischen Rückbau für einzelne IPs.

Teilaufgaben:

1. offene IPs im Decommissioning lesen
2. Prefix/Domain anreichern
3. A/PTR-Einträge entfernen
4. Status in NetBox setzen
5. Journal schreiben

Diese Phase ist wichtig, weil sie schon den Rückbau-Gedanken in die Architektur zwingt.

### Phase 8: Notification und Batch Runner vervollständigen

Am Ende die Batch-Verarbeitung rund machen.

Umfang:

- Sammeln aller Fehlerobjekte
- HTML- oder strukturierte Mail-Benachrichtigung
- konsistentes Logging pro Work Item
- optionale Zusammenfassung pro Lauf

Empfehlung:

- nicht mit `Start-Transcript` als primärem Logmodell arbeiten
- stattdessen strukturierte Log-Events sammeln
- Transcripts nur optional oder als Adapter verwenden

## Was zuerst noch nicht gebaut werden sollte

Diese Punkte sollten bewusst nicht im ersten Implementierungsschnitt landen:

- Prefix-Decommissioning
- Parallelisierung
- Retry-Framework
- Persistente Queue
- generische Workflow-Engine
- komplexe Plugin-Architektur

Begründung:

- der erste Schnitt soll stabil, lesbar und testbar werden
- Generalisierung erst, wenn die ersten Use Cases sauber stehen

## Vorschlag für konkrete Klassen

### Domain

- `IPv4Subnet`
- `IPv4Address`
- `DhcpRange`
- `DhcpScopeDefinition`
- `PrefixWorkItem`
- `IpAddressWorkItem`
- `EnvironmentContext`
- `ProvisioningPrerequisites`
- `ProvisioningDecision`
- `OperationIssue`
- `OperationAuditEntry`
- `BatchRunSummary`

### Application

- `PrefixOnboardingService`
- `IpDnsOnboardingService`
- `IpDnsDecommissioningService`
- `DhcpServerSelectionService`
- `PrerequisiteValidationService`
- `GatewayDnsService`
- `WorkItemJournalService`
- `BatchNotificationService`

### Infrastructure

- `NetBoxPrefixRepository`
- `NetBoxIpAddressRepository`
- `NetBoxJournalRepository`
- `JiraIssueClient`
- `ActiveDirectorySiteResolver`
- `ActiveDirectoryForestResolver`
- `DnsZoneResolver`
- `DnsRecordRepository`
- `DhcpScopeRepository`
- `CredentialFileProvider`
- `EnvFileConfigurationProvider`
- `SmtpMailClient`

## Dependency-Injection-Ansatz für PowerShell 5.x

PowerShell 5.x hat kein eingebautes DI-Framework. Das ist kein Problem.

Empfohlener Ansatz:

- Constructor Injection für Klassen
- Composition Root in einem öffentlichen Entry Point
- Adapter explizit instanziieren und weiterreichen
- in Tests Fakes oder Mocks derselben Klassenverträge einsetzen

Pragmatisch in PowerShell 5.x:

- Klassen mit klaren Konstruktorparametern
- keine globale Script-Scope-Service-Locator-Struktur
- keine versteckte Singleton-Logik

Beispielhafte Abhängigkeitsrichtung:

- `PrefixOnboardingService` bekommt:
  - `NetBoxPrefixRepository`
  - `PrerequisiteValidationService`
  - `DhcpServerSelectionService`
  - `DhcpScopeRepository`
  - `GatewayDnsService`
  - `WorkItemJournalService`

## Mocking-Strategie

Die Clean-Code-Vorgabe verlangt testbare Grenzen. Deshalb sollten Mocks gezielt an den Infrastrukturgrenzen sitzen.

Mockbar sein müssen mindestens:

- NetBox
- Jira
- AD
- DNS
- DHCP
- Mail
- Credential-Zugriff
- Config-Zugriff

Teststrategie:

- Domain-Tests ohne Mocks
- Application-Tests mit Fake-Adaptern oder Pester-Mocks
- Adapter-Tests nur auf Mapping und Fehlerweitergabe

## Fehlerkonzept

Der Rewrite sollte ein explizites Fehlerkonzept haben.

Empfehlung:

- Domain-Fehler: `ArgumentException`, `InvalidOperationException`
- Infrastruktur-Fehler: adapter-spezifisch mit Kontext wrappen
- Use-Case-Fehler: in strukturierte `OperationIssue`-Objekte übersetzen
- Batch-Verarbeitung: pro Work Item Fehler isolieren, aber Gesamtlauf fortsetzen

Wichtig:

- kein `Write-Host` als Fehlersteuerung
- keine Magic Strings
- keine leeren `catch`-Blöcke

## Logging- und Journaling-Konzept

Das Legacy-System benutzt Transcripts. Für den Rewrite ist ein strukturierteres Modell besser.

Empfohlene Ebenen:

- Lauf-Log
- Work-Item-Log
- Journal-Events für NetBox
- optionale Konsole über `Write-Verbose` und `Write-Information`

Empfehlung:

- ein `OperationAuditEntry`-Modell verwenden
- pro Use Case Audit-Daten sammeln
- erst am Rand entscheiden, ob diese Daten
  - in Datei geschrieben
  - an NetBox gesendet
  - in Mail zusammengefasst
  - auf Konsole ausgegeben werden

## Vorbereitung auf Prefix-Decommissioning

Obwohl es noch nicht implementiert wird, muss die Architektur es vorbereiten.

Deshalb sollten diese Entscheidungen jetzt schon eingeplant werden:

- Prefix-Lifecycle nicht nur als Onboarding modellieren
- Scope-Repository mit Delete-/Disable-Fähigkeiten entwerfen
- DNS-Service sowohl `Ensure` als auch `Remove` unterstützen lassen
- Statusübergänge nicht hart im Onboarding-Service verstecken
- Use-Case-spezifische Policies für Onboarding und Decommissioning getrennt halten

Nicht jetzt implementieren, aber jetzt sauber anschneiden:

- `PrefixDecommissioningService`
- Decommissioning-Statusmodell
- Decommissioning-spezifische Validierungsregeln

## Öffentliche Commands

Die öffentlichen Entry Points sollten dünn bleiben.

Empfohlene Commands:

- `Start-DhcpScopeAutomation`
- später optional `Start-PrefixOnboarding`
- später optional `Start-IpDnsMaintenance`

Aufgaben dieser Commands:

- Parameter validieren
- Application Context aufbauen
- Batch-Use-Cases starten
- Ergebnisobjekte zurückgeben

Nicht Aufgabe dieser Commands:

- Fachlogik
- Range-Berechnung
- REST-Payload-Bau
- direkte Cmdlet-Orchestrierung

## Testplan

Mindesterwartung für den ersten brauchbaren Rewrite:

### Domain-Tests

- `IPv4Subnet` validiert Eingaben korrekt
- `DhcpRange` berechnet Start, Ende, Gateway, Broadcast korrekt
- Exclusion-Regeln werden korrekt erzeugt
- Reverse-Zonen-Berechnung funktioniert
- Gateway-Mismatch wird erkannt

### Application-Tests

- Prefix-Onboarding stoppt bei fehlender AD-Site
- Prefix-Onboarding erzeugt Jira bei fehlender Vorbedingung
- Prefix-Onboarding setzt NetBox-Status nach Erfolg
- IP-DNS-Onboarding setzt DNS und aktualisiert Status
- IP-DNS-Decommissioning entfernt DNS und aktualisiert Status
- Batch-Lauf fährt nach Einzelfehlern fort

### Infrastructure-Tests

- NetBox-Mapping zu Domain-Objekten funktioniert
- Jira-Payloads werden korrekt erzeugt
- Adapter wrappen Fehler mit Kontext

## Konkreter Vorschlag für die ersten Arbeitspakete

Empfohlene Reihenfolge der tatsächlichen Implementierung:

1. Projektstruktur und Root-Modul anlegen
2. Domain-Value-Objects für IPv4/Subnet/DHCP-Range bauen
3. Basale Config- und Credential-Provider bauen
4. NetBox-Repository für Prefixe und IPs bauen
5. AD- und DNS-Read-Adapter bauen
6. `PrerequisiteValidationService` bauen
7. DHCP-Adapter und `DhcpServerSelectionService` bauen
8. `PrefixOnboardingService` implementieren
9. `IpDnsOnboardingService` implementieren
10. `IpDnsDecommissioningService` implementieren
11. Journaling- und Notification-Service ergänzen
12. öffentlichen Entry Point und End-to-End-Tests ergänzen

## Entscheidung zu Dateigröße und Schnitt

Damit das Projekt clean bleibt, sollten diese Regeln gelten:

- eine Klasse pro Datei, außer bei sehr eng verwandten Value Objects
- keine Script-Datei mit hunderten Zeilen Orchestrierungslogik
- keine Utility-Sammeldatei für fachfremde Helfer
- Helpers nur dann, wenn sie wirklich rein technisch und lokal sind

## Fazit

Der beste Weg ist ein inkrementeller Neuaufbau von innen nach außen:

1. zuerst stabile Domain-Regeln
2. dann Infrastrukturadapter
3. dann klar getrennte Use Cases
4. dann Batch-Runner, Journaling und Mail

So bleibt der Rewrite kompatibel mit PowerShell 5.x, erfüllt die Clean-Code-Vorgaben und ist gleichzeitig offen für den späteren Rückbau kompletter Netzwerke.
