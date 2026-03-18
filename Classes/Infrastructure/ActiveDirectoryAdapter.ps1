# Isolates Active Directory lookups behind a testable adapter boundary.
<#
.SYNOPSIS
Reads Active Directory metadata required by the automation.

.DESCRIPTION
Provides domain controller, DNS root, forest naming, and subnet-to-site lookups
behind one adapter so application services stay independent from AD cmdlets.

.NOTES
Methods:
- GetDomainControllerName()
- GetDomainDnsRoot()
- GetForestShortName(domain)
- GetSubnetSite(subnet, domainController)

.EXAMPLE
$adapter = [ActiveDirectoryAdapter]::new()
$adapter.GetDomainControllerName()
#>
class ActiveDirectoryAdapter {
    <#
    .SYNOPSIS
    Returns the current domain controller host name.
    .OUTPUTS
    System.String
    #>
    [string] GetDomainControllerName() {
        return [string] (Get-ADDomainController).Name
    }

    <#
    .SYNOPSIS
    Returns the current AD DNS root.
    .OUTPUTS
    System.String
    #>
    [string] GetDomainDnsRoot() {
        return [string] (Get-ADDomain).DNSRoot
    }

    <#
    .SYNOPSIS
    Maps a forest DNS name to the short label expected by Jira.
    .OUTPUTS
    System.String
    #>
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

    <#
    .SYNOPSIS
    Resolves the AD site for a subnet with fallback candidates.
    .OUTPUTS
    System.String
    #>
    [string] GetSubnetSite([IPv4Subnet] $subnet, [string] $domainController) {
        # AD may only contain broader subnet entries, so the lookup deliberately tries less specific fallback candidates.
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
