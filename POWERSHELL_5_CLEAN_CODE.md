# PowerShell 5.x Clean Code Guide

## Purpose

This document is written for agents and contributors working on Windows PowerShell 5.x code.
Its goal is to enforce readable, object-oriented, testable, and maintainable code.

## Scope

- Target runtime: Windows PowerShell 5.x
- Preferred style: object-oriented PowerShell with small, explicit seams
- Primary design goal: separate domain logic, orchestration, and external I/O

## Agent Rules

- MUST prefer classes for domain models and cohesive services.
- MUST keep functions small and focused on one reason to change.
- MUST return objects instead of formatted strings whenever possible.
- MUST keep external side effects at the edges of the system.
- MUST use approved PowerShell verbs for public functions and cmdlets.
- MUST use typed parameters, typed properties, and typed return values where practical.
- MUST make invalid state hard to construct.
- MUST write code that can be tested without live infrastructure whenever possible.
- SHOULD prefer composition over inheritance.
- SHOULD keep classes narrow and explicit.
- SHOULD keep one file focused on one responsibility or one closely related type group.
- NEVER mix business rules, host output, API calls, and data transformation in a single function or method.
- NEVER use `Write-Host` for operational flow or data transport.
- NEVER hide errors with empty `catch` blocks.
- NEVER use aliases in production code.
- NEVER use `Invoke-Expression`.

## Architecture

Use three layers:

1. Domain layer
   Classes that model the problem space and enforce invariants.
2. Application layer
   Services that coordinate workflows by calling domain objects and adapters.
3. Infrastructure layer
   Code that talks to DHCP, NetBox, Jira, files, environment variables, or credentials.

Rules:

- Domain classes MUST not perform direct file, network, or console I/O.
- Infrastructure code SHOULD be wrapped behind explicit classes or thin functions.
- Application services MAY orchestrate multiple collaborators, but SHOULD not contain low-level parsing or transport logic.
- If a method needs credentials, remote calls, or filesystem access, that concern likely belongs outside the domain model.

## Object-Oriented Defaults

Use classes when at least one of these is true:

- The data has invariants.
- Multiple operations belong to the same concept.
- State transitions must be controlled.
- The same entity appears across several workflow steps.

Prefer these roles:

- Entity: identity-bearing domain object, for example `DhcpScope`.
- Value object: immutable concept with validation, for example `IPv4Range`.
- Service: stateless coordinator with explicit dependencies.
- Adapter: wrapper around external systems.

Prefer composition:

- A `DhcpScopeProvisioner` SHOULD depend on `DhcpRepository`, `NetBoxClient`, and `JiraClient`.
- A service SHOULD not inherit from transport-specific classes just to reuse implementation.

Avoid deep inheritance hierarchies:

- In PowerShell 5.x, classes are useful, but the ergonomics are limited compared with C#.
- Prefer one clear base class at most, and only if it removes real duplication without hiding behavior.

## Class Design

- MUST keep constructors simple and validation-focused.
- MUST initialize required properties during construction.
- MUST expose behavior through methods, not by letting callers mutate internals freely.
- SHOULD keep mutable state minimal.
- SHOULD use hidden members only when they reduce accidental misuse.
- SHOULD override `ToString()` only for concise diagnostics, never as the primary data contract.
- SHOULD avoid static mutable state unless there is a clear process-wide cache requirement.

Recommended pattern:

```powershell
class DhcpScope {
    [string] $Name
    [string] $Subnet
    [string] $Mask

    DhcpScope([string] $name, [string] $subnet, [string] $mask) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [System.ArgumentException]::new('Name is required.')
        }

        if ([string]::IsNullOrWhiteSpace($subnet)) {
            throw [System.ArgumentException]::new('Subnet is required.')
        }

        if ([string]::IsNullOrWhiteSpace($mask)) {
            throw [System.ArgumentException]::new('Mask is required.')
        }

        $this.Name = $name
        $this.Subnet = $subnet
        $this.Mask = $mask
    }

    [string] GetScopeId() {
        return '{0}/{1}' -f $this.Subnet, $this.Mask
    }
}
```

## Function Design

Functions remain important in an object-oriented codebase.
Use them as seams around classes, modules, and automation entrypoints.

- MUST use `Verb-Noun` naming with approved verbs.
- MUST use `[CmdletBinding()]` for non-trivial public functions.
- MUST define explicit parameters instead of relying on `$args`.
- MUST validate inputs near the boundary.
- MUST return objects, arrays, or typed values.
- SHOULD keep parameter sets clear and small.
- SHOULD use splatting for long internal command invocations.
- SHOULD make public functions orchestration-focused and keep transformation logic in classes or private helpers.

Good responsibilities for functions:

- script entrypoint
- module public API
- thin wrappers around adapters
- composition root for constructing service objects

Bad responsibilities for one function:

- reading config
- validating domain state
- building REST payloads
- calling remote systems
- formatting user-facing text

If one function does all five, split it.

## Naming

- MUST use approved verbs for public functions.
- MUST use nouns that reflect the business concept, not implementation detail.
- MUST prefer explicit names like `Get-DhcpScopeDefinition` over generic names like `Do-Stuff`.
- MUST name classes as singular nouns.
- SHOULD suffix infrastructure wrappers consistently, for example `Client`, `Repository`, `Provider`, `Mapper`, or `Service`.
- SHOULD keep boolean members readable, for example `IsActive`, `HasReservation`, `CanProvision`.

## Input Validation And Invariants

- MUST validate required constructor arguments.
- MUST validate public function parameters with attributes where useful.
- MUST reject invalid objects early instead of carrying partial state through the workflow.
- SHOULD normalize input once at the boundary.
- SHOULD encode invariants in constructors or factory methods.

Examples:

- subnet must be a valid IPv4 subnet
- scope name must not be empty
- lease duration must be greater than zero
- external IDs must be present before synchronization

## Error Handling

- MUST throw terminating errors for invalid state and unrecoverable failures.
- MUST include context in exception messages.
- MUST catch exceptions only when adding context, translating error types, or handling recovery.
- SHOULD prefer specific .NET exception types for argument and state failures.
- SHOULD let low-level adapters surface detailed failures, then wrap them once at the application boundary if needed.
- NEVER swallow an exception silently.
- NEVER return magic strings like `"ERROR"` instead of throwing or returning a structured result.

Preferred pattern:

```powershell
try {
    $scope = $repository.GetByName($Name)
}
catch {
    throw [System.InvalidOperationException]::new(
        "Failed to load DHCP scope '$Name'. $($_.Exception.Message)",
        $_.Exception
    )
}
```

## Output And Side Effects

- MUST return structured objects for machine consumption.
- MUST keep `Write-Verbose`, `Write-Debug`, and `Write-Information` separate from data output.
- SHOULD reserve `Write-Host` for deliberate interactive UX only.
- SHOULD make methods pure when possible.
- SHOULD isolate side effects into dedicated adapters and entrypoints.

## Formatting And Readability

- MUST use consistent indentation and brace style within a file.
- MUST avoid aliases such as `?`, `%`, `ls`, `cat`, or `select` in production code.
- MUST keep methods short enough that their purpose is obvious without scrolling through multiple concerns.
- MUST remove dead code near the touched area.
- SHOULD extract private helpers when a method mixes validation, mapping, and execution.
- SHOULD prefer early returns over deeply nested conditionals.
- SHOULD keep lines and expressions readable rather than overly condensed.

## PowerShell 5.x Specific Guidance

- MUST design with Windows PowerShell 5.x compatibility in mind.
- MUST avoid relying on PowerShell 7-only syntax or APIs.
- SHOULD be conservative with class features and prefer straightforward constructs.
- SHOULD use modules and classes together: modules expose commands, classes model the domain.
- SHOULD remember that classes are useful for types and invariants, while advanced functions remain the right boundary for automation-oriented entrypoints.

## Testing

- MUST add or update tests when behavior changes.
- MUST test changed behavior, not just happy-path execution.
- SHOULD test domain classes without network or filesystem dependencies.
- SHOULD mock infrastructure boundaries.
- SHOULD verify both success paths and failure paths.

Minimum expectations:

- constructor validation test
- service orchestration test
- adapter error propagation test
- public function contract test

## Static Analysis

- MUST keep the code compatible with PSScriptAnalyzer guidance.
- SHOULD run PSScriptAnalyzer on touched scripts and modules.
- SHOULD treat analyzer findings as design feedback, not just formatting noise.
- SHOULD pay special attention to verb naming, parameter usage, dangerous constructs, and maintainability warnings.

## Forbidden Patterns

- giant script files with global mutable state
- functions that return formatted tables or host text instead of objects
- mixing REST calls and business rules in the same method
- using hashtables as anonymous domain objects everywhere
- untyped public parameters for clearly typed concepts
- copy-pasted validation across multiple functions
- stateful singletons via script scope unless there is a documented reason
- broad `catch {}` blocks without rethrow or translation

## Preferred Project Shape

- `Classes/`
  Domain models and value objects
- `Services/`
  Application orchestration services
- `Adapters/`
  External system integrations
- `Public/`
  exported module functions
- `Private/`
  internal helper functions
- `Tests/`
  behavior-focused tests

If the current repository does not yet use this structure, move toward it incrementally.
Do not perform broad refactors without a clear behavioral reason.

## Agent Checklist

Before closing a change, an agent SHOULD confirm:

- Is the business concept represented as a class where state and behavior belong together?
- Are external dependencies isolated from domain logic?
- Does each function or method have one clear responsibility?
- Are public names PowerShell-native and based on approved verbs?
- Are inputs validated at the boundary?
- Are errors explicit and contextual?
- Does the code return objects rather than formatted text?
- Was changed behavior tested or was a concrete blocker reported?
- Were local duplications or dead branches near the touched area removed if safe?

## Decision Heuristics

- If logic is mostly state plus invariant enforcement, create a class.
- If logic is mostly orchestration of commands and dependencies, create a service.
- If logic talks to external systems, use an adapter.
- If logic is only plumbing into the module surface, use an advanced function.
- If inheritance feels tempting, try composition first.

## Sources

The guidance above aligns primarily with:

- Microsoft Learn: `about_Classes`
  [https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes?view=powershell-5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes?view=powershell-5.1)
- Microsoft Learn: approved verbs for PowerShell commands
  [https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands?view=powershell-7.5](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands?view=powershell-7.5)
- Microsoft Learn: advanced parameters and splatting guidance
  [https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters?view=powershell-7.5](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters?view=powershell-7.5)
  [https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting?view=powershell-5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting?view=powershell-5.1)
- PSScriptAnalyzer overview
  [https://github.com/PowerShell/PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
- Community style reference
  [https://github.com/PoshCode/PowerShellPracticeAndStyle](https://github.com/PoshCode/PowerShellPracticeAndStyle)
