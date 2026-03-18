# Reverse Engineering: `DHCPScopeAutomationOld`

## Ziel dieses Dokuments

Dieses Dokument beschreibt das beobachtbare Verhalten des Legacy-Systems in `DHCPScopeAutomationOld` so detailliert, dass daraus eine Neuimplementierung in PowerShell 5.x abgeleitet werden kann.

Der Fokus liegt auf:

- fachlichem Ablauf
- Integrationen und Seiteneffekten
- Daten- und Statusmodell
- impliziten Geschäftsregeln
- Fehler- und Logging-Verhalten
- Legacy-Besonderheiten, die vor einem Rewrite fachlich geklärt werden sollten

Das Dokument beschreibt bewusst nicht nur "was der Code tut", sondern auch "welches Soll-Verhalten das System aus Sicht der Umgebung erwartet".

## Quellbestandteile des Altsystems

Das Legacy-System besteht aus fünf Dateien:

- `DHCPScopeAutomationOld/Main.ps1`
- `DHCPScopeAutomationOld/Utils.psm1`
- `DHCPScopeAutomationOld/NetboxToolkit.psm1`
- `DHCPScopeAutomationOld/JiraToolkit.psm1`
- `DHCPScopeAutomationOld/SecureCredential.psm1`

## Fachlicher Gesamtzweck

Das System automatisiert nicht nur die Erzeugung von DHCP-Scopes, sondern den gesamten technischen Onboarding- und Teil-Decommissioning-Prozess rund um:

- NetBox-Präfixe, die auf `onboarding_open_dns_dhcp` stehen
- NetBox-IP-Adressen, die auf `onboarding_open_dns` oder `decommissioning_open_dns` stehen

Es verarbeitet also zwei unterschiedliche Arbeitslisten:

1. Präfix-Onboarding mit DHCP/DNS/AD/Jira-Abhängigkeiten
2. Einzel-IP-DNS-Onboarding bzw. DNS-Decommissioning

Das Skript ist damit eher ein Infrastruktur-Orchestrator als nur ein "DHCP Scope Provisioning Script".

## Externe Abhängigkeiten

### Verwendete PowerShell-Module / Windows-Rollen

Das Skript importiert bzw. nutzt:

- `ActiveDirectory`
- `DhcpServer`
- DNS-Server-Cmdlets wie `Get-DnsServerZone`, `Get-DnsServerResourceRecord`, `Add-DnsServerResourceRecordA`, `Add-DnsServerResourceRecordPtr`, `Remove-DnsServerResourceRecord`

Damit setzt die Laufzeit mindestens voraus:

- Windows mit PowerShell 5.x
- Active-Directory-Modul
- DHCP-Server-Modul
- DNS-Server-Cmdlets
- Netzwerkzugriff auf Domain Controller, DHCP-Server, DNS-Server, NetBox, Jira und SMTP
- Berechtigungen für AD/DNS/DHCP/Jira/NetBox

### Externe Systeme

Das Legacy-System integriert mit:

- NetBox REST API
- Jira REST API
- Active Directory
- Microsoft DHCP Server
- Microsoft DNS Server
- SMTP-Server der AD-Domäne
- Registry-Zugriff auf DHCP-Server (`HKLM:\SOFTWARE\ACW\DHCP`)
- PowerShell Remoting auf DHCP-Server zur Ermittlung des Primärservers

## Startparameter und Konfiguration

### Parameter

`Main.ps1` akzeptiert:

- `EmailRecipients`
- `Environment`

Wenn Parameter fehlen, werden sie aus einer `.env`-Datei gelesen.

### `.env`-Datei

Die Funktion `Get-EnvValue` liest aus:

- Standardpfad: `.\.env` relativ zum aktuellen Working Directory

Erwartete Schlüssel:

- `EmailRecipients`
- `Environment`

### Unterstützte Umgebungen

Zulässige Werte:

- `dev`
- `test`
- `prod`
- `gov`
- `china`

Jeder andere Wert führt zu einem sofortigen Abbruch.

### Environment-zu-DNS-Zone-Mapping

Das System verwendet je Environment genau eine Ziel-DNS-Zone:

- `dev` -> `de.mtudev.corp`
- `test` -> `test.mtu.corp`
- `prod` -> `de.mtu.corp`
- `gov` -> `ads.mtugov.de`
- `china` -> `ads.mtuchina.app`

Diese Zuordnung steuert:

- welche NetBox-Präfixe verarbeitet werden
- welche IPs verarbeitet werden
- gegen welche DNS-Domain validiert bzw. geschrieben wird

## Credential-Handling

### Persistenzmodell

API-Zugangsdaten werden über `SecureCredential.psm1` verwaltet.

Speicherort:

- `.\.secureCreds\<CredentialName>.xml`

Verwendete Credential-Namen:

- `DHCPScopeAutomationNetboxApiKey`
- `DHCPScopeAutomationJiraApiKey`

Die Credentials enthalten:

- `Appliance` = Base URL
- `ApiKey`

Falls die XML-Datei fehlt oder nicht geladen werden kann, fragt das Skript Werte interaktiv per `Read-Host` ab und speichert sie per `Export-Clixml`.

### Abgeleitete Anforderungen

Die Neuentwicklung benötigt ein abstrahiertes Credential-Provider-Konzept für:

- sicheres Laden
- optionales Initialisieren
- testbares Austauschen durch Mocks
- keine Secret-Ausgabe in Logs

## Logging- und Audit-Modell

### Transcript-Dateien

Das Legacy-System schreibt Transcripts:

- zu Prozessbeginn: `.\logs\StartingProcess_<timestamp>.log`
- pro Netzwerk: `.\logs\network_<prefix>_<timestamp>.log`
- pro IP: `.\logs\ip_<ip>_<timestamp>.log`

Zwischen den Elementen wird `Stop-Transcript` / `Start-Transcript` gewechselt.

### NetBox-Journaling

Nach jeder erfolgreichen oder fehlgeschlagenen Verarbeitung wird der Transcript-Inhalt in NetBox als Journal-Eintrag gespeichert:

- TargetType `Prefix` für Präfixe
- TargetType `IPAddress` für Einzel-IPs
- `kind = info` bei Erfolg
- `kind = danger` bei Fehler

Die Zeilenumbrüche werden nach HTML `<br>` transformiert.

### Fehlerzusammenfassung per E-Mail

Alle Einzelfehler werden gesammelt. Am Ende sendet das Skript eine HTML-Mail an alle konfigurierten Empfänger, aber nur dann, wenn mindestens ein Fehler aufgetreten ist.

## Domänenmodell des Legacy-Systems

### NetBox Prefix als Primär-Work-Item

Ein NetBox-Präfix wird verarbeitet, wenn:

- `status = onboarding_open_dns_dhcp`
- `custom_fields.domain = <Environment-Zone>`

Die Verarbeitung erwartet mindestens folgende Daten:

- `id`
- `prefix`
- `description`
- `custom_fields.dhcp_type`
- `custom_fields.domain`
- `custom_fields.ad_sites_and_services_ticket_url` optional
- `scope.id`
- `scope.name`
- `custom_fields.default_gateway.id`

Zusätzlich werden per Folgeabfragen angereichert:

- Default-Gateway-IP-Adresse über `Get-IpAddressInformation`
- Gateway-DNS-Name über `Get-IpAddressInformation`
- Site-Mandant über `Get-NetboxSiteInformation` aus `custom_fields.valuemation_site_mandant`

### NetBox IP Address als sekundäres Work-Item

Eine IP-Adresse wird verarbeitet, wenn:

- `status = onboarding_open_dns`
- oder `status = decommissioning_open_dns`

Die IP wird anschließend mit ihrem enthaltenen Präfix angereichert, um Domain und Prefix zu ermitteln.

## Statusmodell

### Prefix-Status

Eingang:

- `onboarding_open_dns_dhcp`

Ausgang:

- `onboarding_done_dns_dhcp`

### IP-Status

Eingang:

- `onboarding_open_dns`
- `decommissioning_open_dns`

Ausgang:

- `onboarding_done_dns`
- `decommissioning_done_dns`

### Jira-bezogene Zustände

Für bestehende AD-/DNS-Vorbereitungstickets wird geprüft:

- wenn Status `Verify` -> Transition nach `Close`
- sonst muss der Ticketstatus bereits `Geschlossen` sein
- jeder andere Zustand blockiert das Präfix-Onboarding

## Hauptprozess: End-to-End-Ablauf

Der Hauptprozess ist `Invoke-Process`.

Er läuft in zwei Phasen:

1. Prefix-Onboarding
2. IP-DNS-Verarbeitung

---

## Phase 1: Prefix-Onboarding

### 1. Abruf offener Präfixe aus NetBox

Es werden alle Präfixe mit folgendem Filter geladen:

- `status = onboarding_open_dns_dhcp`
- `cf_domain = <Environment-Zone>`

### 2. Iteration über jedes Präfix

Für jedes Präfix wird separat verarbeitet und separat geloggt.

Ein Fehler bei einem Präfix beendet nicht den Gesamtprozess, sondern nur das aktuelle Element.

### 3. Pflichtfeldprüfung

Das Skript prüft alle Properties des angereicherten Prefix-Objekts auf Leerwert oder Null.

Ausnahme:

- `ADSitesAndServicesTicketUrl` darf fehlen

Fachlich impliziert das:

- ohne Description, DHCP-Type, Site, Domain, Default-Gateway, DnsName, Site-Mandant usw. wird nicht weitergearbeitet

### 4. Ermittlung des Forest-Kurznamens

Aus `network.Domain` wird via AD-Forest-Auflösung ein Kurzname abgeleitet:

- `mtu.corp` -> `MTU`
- `mtudev.corp` -> `MTUDEV`
- `ads.mtugov.de` -> `MTUGOV`
- `ads.mtuchina.app` -> `MTUCHINA`
- sonst Original-Forest-Name

Dieser Wert wird für das Jira-Ticket benötigt.

### 5. Prüfung der AD-Site-Zuordnung des Subnetzes

`Test-ADSubnetSite` sucht in AD-Replikationssubnetzen nach:

- zuerst exakt dem Präfix
- danach Fallbacks auf Top-Level-Netze:
  - `/24`
  - `/16`
  - `/8`

Die Suche erfolgt nur für Ebenen, die kleiner oder gleich dem ursprünglichen Präfix sind.

Beispiel:

- für `10.24.5.0/27` werden nacheinander geprüft:
  - `10.24.5.0/27`
  - `10.24.5.0/24`
  - `10.24.0.0/16`
  - `10.0.0.0/8`

Wird ein AD-Subnetz gefunden, liefert die Funktion den Site-Namen zurück.

### 6. Prüfung der Reverse-DNS-Delegation

Die DNS-Delegation wird nicht gegen die Reverse-Zone selbst, sondern über `NS`-Records geprüft:

- aus dem Präfix wird eine Reverse-Zone auf Oktettgrenzen abgeleitet
- anschließend wird von dieser Zone aus schrittweise in `/8`-Schritten nach oben gegangen
- sobald NS-Records gefunden werden, wird geprüft, ob `NameHost` auf die erwartete Domain endet

Besonderheit:

- für `test.mtu.corp` wird bei dieser Prüfung stattdessen `de.mtu.corp` verwendet

Das ist ein impliziter Legacy-Sonderfall.

### 7. Entscheidung: Vorbedingungen erfüllt oder Jira-Ticket nötig

Es gibt drei fachliche Vorbedingungen, die erfüllt sein müssen, bevor DHCP/DNS fertig provisioniert werden:

- AD-Site-Zuordnung vorhanden
- Reverse-Zone vorhanden
- DNS-Delegation vorhanden

Wenn eine dieser Vorbedingungen fehlt:

- und bereits ein Jira-Link in NetBox hinterlegt ist:
  - das Präfix wird nicht weiter verarbeitet
  - es wird ein Fehler protokolliert
- und kein Jira-Link vorhanden ist:
  - es wird ein Jira-Ticket erzeugt
  - der Ticket-Link wird in NetBox in `ad_sites_and_services_ticket_url` gespeichert
  - die weitere Verarbeitung dieses Präfixes wird abgebrochen

### 8. Prüfung der AD-Site gegen erwarteten Mandanten

Wenn eine AD-Site gefunden wurde, muss sie exakt zu `network.ValuemationSiteMandant` passen.

Bei Abweichung:

- Fehler
- kein DHCP/DNS-Onboarding

### 9. Behandlung bestehender Jira-Tickets

Wenn ein Jira-Link existiert und die Vorbedingungen jetzt erfüllt sind:

- Ticket-Key aus URL extrahieren
- Ticketstatus abfragen
- bei `Verify` automatisch nach `Close` transitionieren
- bei anderem Status muss bereits `Geschlossen` vorliegen
- sonst Fehler und Abbruch des Präfixes

### 10. Verzweigung nach DHCP-Typ

Akzeptierte fachliche DHCP-Typen:

- `no_dhcp`
- `dhcp_static`
- `dhcp_dynamic`

#### 10.1 `no_dhcp`

Wenn `DHCPType = no_dhcp`:

- kein DHCP-Scope wird angelegt
- aber Gateway-DNS wird trotzdem gesetzt
- Prefix-Status wird auf `onboarding_done_dns_dhcp` gesetzt

Das zeigt: "kein DHCP" bedeutet im Legacy-System nicht "nichts tun", sondern "nur DNS für Gateway pflegen".

#### 10.2 `dhcp_static` und `dhcp_dynamic`

Wenn `DHCPType = dhcp_static` oder `dhcp_dynamic`:

- es wird ein Ziel-DHCP-Server bestimmt
- danach wird `New-DHCPScope` ausgeführt
- anschließend wird das Prefix in NetBox auf `onboarding_done_dns_dhcp` gesetzt

## DHCP-Server-Auswahl

### Grundprinzip

`Get-PrimaryDHCPServer` nutzt:

- `Get-DhcpServerInDC`
- Filter auf DNS-Namen anhand eines Standortmusters
- Remote-Registry-Prüfung von `HKLM:\SOFTWARE\ACW\DHCP\Primary`

Wenn ein Server `Primary = true` liefert, wird dieser verwendet.

Wenn keiner primär markiert ist:

- erster gefundener Server als Fallback

Wenn gar keiner gefunden wird:

- Fehler

### Site-Code-Mapping

Unterstützte Site-Codes:

- `eme` -> `e*`
- `rze` -> `r*`
- `haj` -> `h*`
- `muc` -> `m*`
- `mal` -> `m*`
- `beg` -> `o*`
- `yvr` -> `v*`
- `lud` -> `l*`

In `dev` wird ein `dev`-Präfix vorangestellt.

### Environment-Sonderfall für `dev` und `test`

In `dev` und `test` wird die echte AD-Site ignoriert.

Stattdessen wird immer ein MUC-DHCP-Server verwendet:

- `Get-PrimaryDHCPServer -Site "muc"`
- in `dev` zusätzlich mit `-dev $true`

Das ist eine klare Legacy-Fachregel und nicht nur ein technischer Zufall.

## DHCP-Scope-Erzeugung im Detail

### Eingangsdaten

`New-DHCPScope` erwartet:

- `Network.NetworkName` im CIDR-Format
- `Network.DHCPType`
- `Network.Description`
- `Network.Domain`
- `Network.Site`
- `Network.DefaultGatewayIpAddress`
- `Network.DnsName`

### Existenzprüfung

Vor Anlegen wird geprüft:

- existiert bereits ein DHCPv4-Scope mit `ScopeId = <Subnetzadresse>`

Wenn ja:

- kein Scope wird neu angelegt
- DNS für das Gateway wird trotzdem gesetzt
- Failover wird trotzdem versucht

### Berechnung des Scope-Namens

Namensschema:

- `STATIC <prefix> <site> <description>`
- `DYNAMIC <prefix> <site> <description>`
- `NODHCP <prefix> <site> <description>`

Die Präfixe kommen aus einem Mapping:

- `dhcp_static` -> `STATIC`
- `dhcp_dynamic` -> `DYNAMIC`
- `no_dhcp` -> `NODHCP`

### Berechnung von Netzmaske, Range, Gateway, Broadcast

Aus dem CIDR-Präfix werden berechnet:

- Dotted-Decimal-Netmask
- DHCP-Startadresse
- DHCP-Endadresse
- Gateway
- Broadcast

#### Legacy-Regeln für die Range

Grundregeln:

- `start = network + 1`
- `broadcast = letztes IP des Präfixes`
- `gateway = broadcast - 1`

Zusatzregel:

- bei Präfixlängen von `/22` bis `/25` werden zusätzlich 5 Adressen vor dem Gateway reserviert

Dann gilt:

- `end = gateway - reservedAfterGateway - 1`

Implizite Wirkung:

- Gateway ist immer die vorletzte Adresse
- obere Adressen vor dem Gateway werden reserviert

### Validierung des Gateways gegen NetBox

Vor dem Anlegen prüft das Skript:

- stimmt das berechnete Gateway exakt mit `Network.DefaultGatewayIpAddress` aus NetBox überein

Wenn nicht:

- Fehler
- kein Scope wird angelegt

Das ist eine harte fachliche Regel.

### Scope-Anlage

Bei neuem Scope werden gesetzt:

- Scope-Name
- StartRange
- EndRange
- SubnetMask
- `State = Active`
- `LeaseDuration = 3 Tage`

### DHCP-Optionen

Nach Scope-Anlage werden gesetzt:

- Option 003 Router = Gateway
- Option 015 DNS Domain = `Network.Domain`
- Option 028 Broadcast = Broadcast-Adresse

### Dynamic-DNS-Einstellungen

Nur bei `dhcp_dynamic`:

- `DynamicUpdates = OnClientRequest`
- `DeleteDnsRRonLeaseExpiry = true`
- `UpdateDnsRRForOlderClients = true`
- `DisableDnsPtrRRUpdate = false`

### Besonderheit bei `dhcp_static`

Bei `dhcp_static` wird:

- `dhcpRange.End = dhcpRange.Start`
- anschließend eine Exclusion Range über genau diese Adresse gesetzt

Beobachtetes Ergebnis:

- der Scope hat faktisch keinen frei vergebbaren Adressbereich

Das wirkt wie ein Reservierungs-/Marker-Scope. Ob das fachlich gewollt ist, muss vor dem Rewrite bestätigt werden.

### Failover-Konfiguration

Nach Scope-Anlage oder bei bereits vorhandenem Scope wird versucht:

- erste vorhandene DHCP-Failover-Beziehung auf dem Zielserver zu lesen
- den Scope dieser Beziehung hinzuzufügen

Wenn keine Failover-Beziehung existiert oder etwas fehlschlägt:

- nur Log-Ausgabe
- kein harter Abbruch

### Zusätzliche /24-basierte Exclusion-Regeln

Nur bei `dhcp_dynamic`:

- wenn Präfix kleiner als `/24` ist:
  - für jedes enthaltene `/24` werden `.0`, `.1` und `.249-.255` ausgeschlossen
- wenn Präfix genau `/24` ist:
  - ebenfalls `.0`, `.1` und `.249-.255` ausschließen

Fachlich ergibt sich daraus:

- pro `/24` sollen Randadressen reserviert bleiben
- diese Regel ist unabhängig von der Hauptbereichsberechnung und wird nachträglich umgesetzt

## DNS-Verhalten für Präfixe und Einzel-IPs

### Grundprinzip

DNS wird nicht nur additiv gepflegt. Vor dem Setzen neuer Einträge werden bestehende Einträge für die betreffende IP gelöscht.

Das System arbeitet daher nach dem Muster:

1. bestehende A/PTR-Einträge zur IP entfernen
2. gewünschte A/PTR-Einträge neu anlegen

### Reverse-Zone-Auflösung

`Get-ReverseZoneInfo`:

- leitet aus dem Subnetz eine Reverse-Zone auf Oktettbasis ab
- liest alle Reverse-Zonen vom DNS-Server
- sucht zuerst nach exaktem Match
- sonst nach dem "besten" übergeordneten Match

Damit unterstützt das Legacy-System auch Präfixe, die innerhalb größerer Reverse-Zonen liegen.

### Setzen von A-Records

`Set-DnsARecord`:

- normalisiert Namen relativ zur Zone
- prüft, ob bereits ein A-Record für diesen Namen existiert
- falls ja: keine Änderung
- falls nein: `Add-DnsServerResourceRecordA`

Wichtig:

- Existenzprüfung erfolgt nur auf Namen, nicht auf gewünschte Ziel-IP
- bereits vorhandene abweichende A-Records blockieren eine Neuerzeugung
- vorherige Bereinigung per IP soll diesen Fall in der Regel entschärfen

### Entfernen von A-Records

`Remove-AllCorrespondingDnsARecord`:

- durchsucht die gesamte Forward-Zone nach A-Records mit der Ziel-IP
- entfernt alle Treffer

Damit wird nicht nach DNS-Name, sondern bewusst nach IP bereinigt.

### Setzen von PTR-Records

`Set-DnsPtrRecord`:

- akzeptiert entweder relativen PTR-Owner oder volle IPv4
- berechnet bei voller IPv4 den relativen Owner anhand der Reverse-Zonentiefe
- prüft auf vorhandene PTRs für denselben Owner
- falls vorhanden: keine Änderung
- falls nicht vorhanden: PTR anlegen

### Entfernen von PTR-Records

`Remove-AllCorrespondingDnsPtrRecord`:

- ruft `Remove-DnsPtrRecord` mit der Ziel-IP auf
- Owner wird aus Reverse-Zone + IP abgeleitet
- vorhandene PTRs für diesen Owner werden entfernt

### Gateway-DNS beim Präfix-Onboarding

Sowohl bei `no_dhcp` als auch bei echten DHCP-Scopes wird DNS für das Default Gateway gepflegt:

- A-Record in `Network.Domain`
- PTR-Record in gefundener Reverse-Zone

PTR-Zielname:

- wenn `Network.DnsName` bereits mit `Network.Domain` endet -> direkt verwenden
- sonst `Network.DnsName + "." + Network.Domain`

## Phase 2: Einzel-IP-DNS-Verarbeitung

Nach Abschluss der Präfixverarbeitung startet eine zweite Phase.

### 1. Abruf offener IPs

Es werden alle NetBox-IP-Adressen geladen mit:

- `status = onboarding_open_dns`
- oder `status = decommissioning_open_dns`

### 2. Anreicherung mit Präfix und Domain

Für jede IP:

- containing Prefix in NetBox suchen
- daraus `Prefix` und `Domain` ableiten
- nur IPs der Ziel-Domain des aktuellen Environments weiterverarbeiten

### 3. Verarbeitung `onboarding_open_dns`

Voraussetzungen:

- `DnsName` muss vorhanden sein
- passende Reverse-Zone muss existieren

Aktionen:

- bestehende DNS-Einträge für die IP entfernen
- neuen A-Record und PTR-Record setzen
- Status in NetBox auf `onboarding_done_dns`

### 4. Verarbeitung `decommissioning_open_dns`

Aktionen:

- zugehörige A- und PTR-Records anhand der IP entfernen
- Status in NetBox auf `decommissioning_done_dns`

### 5. Journaling und Fehlerbehandlung

Analog zur Präfixphase:

- Erfolg -> Journal `info`
- Fehler -> Journal `danger`
- Fehler werden zusätzlich für Sammelmail aggregiert

## NetBox-Integrationen im Detail

### Prefix-Lesen

`Get-NetworkInfo` liest aus `/api/ipam/prefixes/`.

Zusätzliche Folgeabfragen pro Präfix:

- `/api/ipam/ip-addresses/{defaultGatewayId}/`
- `/api/dcim/sites/{siteId}/`

Der neue Entwurf sollte diese N+1-Struktur berücksichtigen oder gezielt verbessern.

### Prefix-Updates

Es gibt zwei relevante Update-Typen:

- `ad_sites_and_services_ticket_url` setzen
- `status = onboarding_done_dns_dhcp` setzen

### IP-Lesen und IP-Updates

IPs werden aus `/api/ipam/ip-addresses/` gelesen, inklusive Pagination.

Relevante IP-Updates:

- `status = onboarding_done_dns`
- `status = decommissioning_done_dns`

### Journal-Einträge

NetBox-Journale werden geschrieben nach:

- `/api/extras/journal-entries/`

Target-Mapping:

- `Prefix` -> `ipam.prefix`
- `IPAddress` -> `ipam.ipaddress`

## Jira-Integrationen im Detail

### Ticket-Erzeugung

Wenn AD-Site, Reverse-Zone oder DNS-Delegation fehlen, wird ein Jira-Ticket erzeugt.

Ticketinhalt:

- Projekt: `TCO`
- IssueType: `Story`
- Summary: `DNS-Zonen pflegen - Reverse Lookup Zone anlegen / Sites und Services pflegen`
- Labels:
  - `FIPI-Abnahme-nicht-benötigt`
  - `FIPI-Freigabe-nicht-benötigt`
  - `Tier0-Operations`
- Assignee: `YAT5495`

Der Beschreibungstext enthält:

- Subnetz-ID
- Präfixlänge
- Forest-Kurzname
- Site
- Windows/Linux = `unbekannt`
- Delegation vorhanden/nicht vorhanden
- Confluence-Link

Nach dem Erzeugen wird sofort versucht:

- die Jira-Transition `Commit` auszuführen

### Ticket-Schließung

Wenn Vorbedingungen später erfüllt sind und ein Ticket-Link existiert:

- Status lesen
- bei `Verify` -> Transition zu `Close`
- sonst muss Ticket bereits `Geschlossen` sein

## E-Mail-Verhalten

Sobald es mindestens einen Fehler gab:

- HTML-Mail mit allen Fehlern senden
- pro Fehler wird ein HTML-Link auf das betroffene NetBox-Objekt erzeugt

Mail-Merkmale:

- Absender: `reports@mtu.de`
- SMTP-Server: `smtpmail.<AD-DNSRoot>`
- Betreff: `DHCP Scope Automation Script`

## Nicht-funktionale Anforderungen, die aus dem Altverhalten ableitbar sind

Die Neuentwicklung sollte mindestens diese Eigenschaften gezielt entscheiden, nicht zufällig verlieren:

- Batch-Verarbeitung mehrerer Work-Items in einem Lauf
- Fehlerisolation pro Work-Item statt Globalabbruch
- detailliertes Audit pro Work-Item
- technische Journale in NetBox
- Umgebungsspezifische Filterung
- idempotenznahe Verarbeitung
- Vorbedingungsprüfung vor Infrastrukturänderung
- automatische Ticket-Erzeugung bei fehlenden Vorbedingungen
- automatische Ticket-Schließung bei erfüllten Vorbedingungen

## Beobachtete Legacy-Besonderheiten und Klärpunkte vor dem Rewrite

Diese Punkte sind wichtig, weil sie im Altcode sichtbar sind, aber fachlich nicht automatisch 1:1 übernommen werden sollten.

### 1. Das System ist fachlich größer als "DHCP Scope Automation"

Es provisioniert nicht nur DHCP-Scopes, sondern auch:

- Gateway-DNS für Präfixe
- DNS-Onboarding einzelner IPs
- DNS-Decommissioning einzelner IPs
- Jira-Tickets für manuelle Vorarbeiten

Der neue Projektzuschnitt sollte das als getrennte Use Cases modellieren.

### 2. `no_dhcp` bedeutet trotzdem DNS-Pflege

Das ist eine wichtige Fachregel.

### 3. `dhcp_static` wirkt wie ein Scope ohne nutzbare Lease-Range

Das muss fachlich bestätigt werden.

### 4. `dev` und `test` ignorieren die echte AD-Site bei der DHCP-Server-Auswahl

Das ist wahrscheinlich bewusst, sollte aber explizit als Policy modelliert werden.

### 5. Reverse-Zonenlogik arbeitet oktettbasiert

Nicht oktettgrenze Präfixe werden auf die passende übergeordnete Reverse-Zone gemappt.

### 6. DNS-Bereinigung erfolgt IP-basiert

Das verhindert Namensreste, kann aber aggressiv sein, wenn mehrere Namen bewusst auf eine IP zeigen sollen.

### 7. Pflichtfeldprüfung basiert auf allen Properties des angereicherten Prefix-Objekts

Das ist technisch fragil. Im Rewrite sollte ein explizites Validierungsmodell verwendet werden.

### 8. Journal-Einträge enthalten komplette Transcripts als HTML

Das kann sehr groß werden. Im Rewrite sollte entschieden werden:

- vollständiges Protokoll
- oder verdichteter, strukturierter Journal-Event

### 9. Fehlende Vorbedingungen führen nicht zu Retries, sondern zu Jira + Skip

Das ist eine echte Prozessentscheidung.

### 10. Einige sichtbare Codefehler oder Inkonsistenzen sollten nicht als Soll-Verhalten missverstanden werden

Beispiele aus dem Legacy-Code:

- Jira-Credentials werden nach dem Laden versehentlich mit NetBox-Expect-Methoden validiert
- Log-Verzeichnis wird nicht explizit angelegt
- mehrere Legacy-Pfade sind technisch stark gekoppelt

Solche Punkte sind Implementierungsartefakte, keine fachlichen Anforderungen.

## Abgeleitete fachliche Anforderungen für die Neuentwicklung

Aus dem Altverhalten ergibt sich mindestens folgender fachlicher Sollumfang:

1. Das System muss NetBox-Präfixe für DHCP/DNS-Onboarding verarbeiten können.
2. Das System muss NetBox-IP-Adressen für DNS-Onboarding und DNS-Decommissioning verarbeiten können.
3. Die Verarbeitung muss environment-spezifisch gefiltert werden.
4. Vor jeder Infrastrukturänderung müssen AD-Site, Reverse-Zone und DNS-Delegation validiert werden.
5. Fehlende Vorbedingungen müssen einen manuellen Workflow über Jira auslösen können.
6. Nach erfüllten Vorbedingungen muss die technische Provisionierung fortgesetzt werden können.
7. DHCP-Scopes müssen anhand definierter Netzregeln berechnet werden.
8. Gateway-DNS muss aus NetBox-Informationen gepflegt werden.
9. DNS-Einträge einzelner IPs müssen auf Basis von NetBox-Status gepflegt oder entfernt werden.
10. Erfolgs- und Fehlerverläufe müssen pro Work-Item auditierbar sein.
11. Fehler in einem Work-Item dürfen den Rest des Batches nicht verhindern.
12. Abschlusszustände müssen zurück nach NetBox geschrieben werden.

## Zukünftige Erweiterung: Netzwerk-Decommissioning

Zusätzlich zum beobachteten Legacy-Verhalten sollte die Neuentwicklung architektonisch bereits auf einen zukünftigen Rückbau kompletter Netzwerke vorbereitet werden.

Wichtig:

- dieser Use Case ist im Legacy-System für komplette Präfixe aktuell noch nicht implementiert
- er soll jetzt noch nicht umgesetzt werden
- er muss aber im neuen Design als eigener, später aktivierbarer Fachfall vorgesehen werden

### Gemeinte fachliche Richtung

Zukünftig soll nicht nur DNS für einzelne IP-Adressen dekommissioniert werden können, sondern auch ganze Netzwerke bzw. Präfixe.

Das betrifft voraussichtlich mindestens:

- Rückbau eines DHCP-Scopes
- Entfernen oder Bereinigen scopebezogener DHCP-Optionen
- Entfernen aus DHCP-Failover-Beziehungen
- Entfernen oder Bereinigen von Gateway-DNS-Einträgen
- Rückmeldung des Decommissioning-Status nach NetBox
- Auditierung, Journaling und Fehlerbehandlung analog zum Onboarding

### Architekturfolgen für den Rewrite

Der neue Entwurf sollte deshalb nicht nur auf "Provisionierung" zugeschnitten werden, sondern auf symmetrische Use Cases:

- Prefix Onboarding
- Prefix Decommissioning
- IP DNS Onboarding
- IP DNS Decommissioning

Die Domänenlogik für das Netz selbst sollte so geschnitten werden, dass dieselben Infrastrukturadapter in beide Richtungen benutzt werden können:

- `IDhcpScopeService` für Create, Update, Delete, Failover-Detach
- `IDnsRecordService` für Ensure und Remove
- `INetboxRepository` für Lesen, Statuswechsel und Journaling
- optional später ein eigener `PrefixDecommissioningOrchestrator`

### Empfohlene fachliche Vorabfragen für den späteren Rückbau

Diese Punkte sollten vor einer Implementierung des Netzwerk-Decommissionings entschieden werden:

- welcher NetBox-Status ein Prefix-Decommissioning startet
- welcher Zielstatus nach erfolgreichem Rückbau gesetzt wird
- ob ein vorhandener Scope vollständig gelöscht oder nur deaktiviert werden soll
- ob bestehende Leases zuvor geprüft oder abgewartet werden müssen
- ob Gateway-DNS immer gelöscht oder nur bei eindeutiger Eigentümerschaft entfernt werden soll
- ob Reverse-Zonen, AD-Site-Zuordnungen und Jira-Tickets beim Rückbau ebenfalls berücksichtigt werden müssen
- wie mit teilabgebauten Zuständen umzugehen ist

### Harte Anforderung für die Zielarchitektur

Der Rewrite darf den Prefix-Lebenszyklus deshalb nicht als Einbahnstraße modellieren.

Präfixe müssen im Zielsystem so modelliert werden, dass sowohl Aufbau als auch späterer Rückbau sauber, testbar und mit denselben Infrastrukturgrenzen abbildbar sind.

## Ableitung für den Rewrite-Zuschnitt

Für einen sauberen Neuaufbau sollte die Altlogik mindestens in diese Domänen getrennt werden:

- Orchestrierung / Batch Runner
- Konfiguration und Environment-Policy
- Credential Provider
- NetBox Repository / Client
- Jira Client
- AD Resolver
- DNS Service
- DHCP Service
- Provisioning-Regeln für Prefix-Onboarding
- Decommissioning-Regeln für Prefix-Rückbau
- Provisioning-Regeln für IP-DNS-Onboarding
- Provisioning-Regeln für IP-DNS-Decommissioning
- Logging / Journal / Notification

Damit lassen sich die vom User gewünschten Ziele sauber umsetzen:

- objektorientiertes Design
- Dependency Injection
- Mockbarkeit
- klar testbare Services
- saubere Fehlerbehandlung
- austauschbare Infrastrukturadapter

## Kurzfazit

`DHCPScopeAutomationOld` ist kein einzelnes "Scope anlegen"-Skript, sondern ein monolithischer Infrastruktur-Workflow, der NetBox, AD, DNS, DHCP, Jira und E-Mail miteinander koppelt.

Die wesentlichen fachlichen Kernfälle sind:

- Präfix-Onboarding mit DHCP und Gateway-DNS
- Präfix-Onboarding ohne DHCP, aber mit Gateway-DNS
- Einzel-IP-DNS-Onboarding
- Einzel-IP-DNS-Decommissioning
- Jira-gesteuertes Warten auf manuelle Vorarbeiten in AD/DNS

Für den Rewrite ist entscheidend, diese Fachfälle zunächst als getrennte, explizite Use Cases zu modellieren und erst danach die technische Architektur darum zu bauen.
