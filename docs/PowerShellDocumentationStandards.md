# PowerShell Documentation Standards

## Ziel

Die Codebasis dokumentiert nur die fachlichen Grenzen, den beabsichtigten Einsatz und
nicht offensichtliche Entscheidungen. Kommentare duplizieren keine Implementierungsdetails.

## Funktionen

- Jede öffentliche Funktion bekommt `comment-based help`.
- Private Funktionen bekommen ebenfalls `comment-based help`, wenn sie eigene Eingaben,
  Ausgaben oder Seiteneffekte kapseln.
- Help-Blöcke enthalten mindestens `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`,
  `.OUTPUTS` und ein kurzes `.EXAMPLE`, wenn das für den Aufrufer sinnvoll ist.
- Die Beschreibung erklärt Zweck und Einsatzkontext, nicht Zeile für Zeile die Logik.

## Klassen

- Jede Klasse erhält einen knappen Kopfkommentar direkt über der Deklaration.
- Der Kommentar beschreibt die fachliche Verantwortung oder die Systemgrenze der Klasse.
- Komplexere Methoden werden kommentiert, wenn sie ein Entwurfsmuster oder eine feste
  Architekturrolle tragen, die für spätere Erweiterungen relevant ist.

## Komplexe Methoden

- Beschreibe bei komplexeren Methoden die zugrunde liegende Rolle im Design, zum Beispiel
  `Facade`, `Composition Root`, `Template Method`, `Strategy Dispatch` oder
  `Application-Service Orchestration`.
- Der Methodenkommentar erklärt, welche Teile invariant bleiben und an welcher Stelle
  Erweiterungen oder neue Modi eingehängt werden sollen.
- Kommentare markieren bevorzugt Erweiterungsnähte und Verantwortungsgrenzen zwischen
  Domain, Application und Infrastructure.
- Wenn eine Methode nur deshalb schwer verständlich ist, weil sie zu groß oder zu gemischt
  ist, wird zuerst refactort und erst danach kommentiert.

## Clean-Code-Kommentare

- Kommentare erklären bevorzugt `why`, `intent` und Randbedingungen.
- Kommentare erklären nicht triviale Domänenregeln, Invarianten und Integrationsannahmen.
- Kommentare wiederholen keine selbsterklärenden Namen oder offensichtlichen Kontrollfluss.
- Wenn ein Kommentar länger wird als die dazugehörige Logik, muss die Struktur des Codes
  vor dem Kommentar hinterfragt werden.

## Referenzen

- Microsoft `about_Comment_Based_Help`
- Microsoft `about_Classes`
- PSScriptAnalyzer `ProvideCommentHelp`
- Google Style Guide `Comments`
