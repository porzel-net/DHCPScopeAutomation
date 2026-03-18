<#
.SYNOPSIS
Starts the DHCP scope automation workflow for a selected environment.

.DESCRIPTION
Builds the runtime object graph, executes the enabled onboarding and DNS lifecycle
use cases, writes structured logs, and returns public summary objects for callers.

.PARAMETER Environment
Logical environment name. If omitted, the value is resolved from the relative `.env` file.

.PARAMETER EmailRecipients
Recipient list for failure notifications. If omitted, the list is resolved from `.env`.

.PARAMETER ConfigurationPath
Relative path to the environment configuration file.

.PARAMETER CredentialDirectory
Relative path to the directory containing persisted secure credential files.

.PARAMETER SkipPrefixOnboarding
Skips prefix onboarding processing for NetBox prefixes in `onboarding_open_dns_dhcp`.

.PARAMETER SkipIpDnsOnboarding
Skips IP DNS onboarding processing for IPs in `onboarding_open_dns`.

.PARAMETER SkipIpDnsDecommissioning
Skips IP DNS decommissioning processing for IPs in `decommissioning_open_dns`.

.PARAMETER SkipFailureMail
Suppresses the aggregated failure notification mail.

.PARAMETER SkipDependencyImport
Skips importing Windows infrastructure modules when the caller already prepared the session.

.PARAMETER RuntimeFactory
Optional runtime factory seam for tests or advanced hosts that need to inject a prebuilt runtime.

.OUTPUTS
PSCustomObject[]

.EXAMPLE
Start-DhcpScopeAutomation -Environment prod

.EXAMPLE
Start-DhcpScopeAutomation -Environment test -SkipFailureMail -SkipDependencyImport
#>
function Start-DhcpScopeAutomation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string] $Environment,

        [Parameter(Mandatory = $false)]
        [string[]] $EmailRecipients,

        [Parameter(Mandatory = $false)]
        [string] $ConfigurationPath = '.env',

        [Parameter(Mandatory = $false)]
        [string] $CredentialDirectory = '.secureCreds',

        [Parameter(Mandatory = $false)]
        [switch] $SkipPrefixOnboarding,

        [Parameter(Mandatory = $false)]
        [switch] $SkipIpDnsOnboarding,

        [Parameter(Mandatory = $false)]
        [switch] $SkipIpDnsDecommissioning,

        [Parameter(Mandatory = $false)]
        [switch] $SkipFailureMail,

        [Parameter(Mandatory = $false)]
        [switch] $SkipDependencyImport,

        [Parameter(Mandatory = $false)]
        [AutomationRuntimeFactoryBase] $RuntimeFactory
    )

    if (-not $SkipDependencyImport.IsPresent) {
        Import-AutomationDependencies
    }

    $runtimeFactory = $RuntimeFactory
    if ($null -eq $runtimeFactory) {
        $runtimeFactory = [AutomationRuntimeFactory]::new(
            $Environment,
            $EmailRecipients,
            $ConfigurationPath,
            $CredentialDirectory
        )
    }

    $runtime = $runtimeFactory.CreateRuntime()
    $summaries = $runtime.Execute(
        -not $SkipFailureMail.IsPresent,
        $SkipPrefixOnboarding.IsPresent,
        $SkipIpDnsOnboarding.IsPresent,
        $SkipIpDnsDecommissioning.IsPresent
    )

    $runLogPath = Write-AutomationRunLog -Runtime $runtime -Summaries $summaries
    Write-Information -MessageData ('Run log written to {0}' -f $runLogPath)

    foreach ($summary in @($summaries)) {
        foreach ($entry in @($summary.AuditEntries)) {
            Write-AutomationLogEntry -Entry $entry
        }
    }

    $publicSummaries = @()
    foreach ($summary in @($summaries)) {
        $publicSummaries += Convert-BatchRunSummaryToPublicObject -Summary $summary
    }

    return $publicSummaries
}
