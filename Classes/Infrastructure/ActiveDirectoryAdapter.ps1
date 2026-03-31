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
        $domainController = [string] (Get-ADDomainController).Name
        Write-Verbose -Message ("Resolved Active Directory domain controller '{0}'." -f $domainController)
        return $domainController
    }

    <#
    .SYNOPSIS
    Returns the current AD DNS root.
    .OUTPUTS
    System.String
    #>
    [string] GetDomainDnsRoot() {
        $dnsRoot = [string] (Get-ADDomain).DNSRoot
        Write-Verbose -Message ("Resolved Active Directory DNS root '{0}'." -f $dnsRoot)
        return $dnsRoot
    }

    <#
    .SYNOPSIS
    Maps a forest DNS name to the short label expected by Jira.
    .OUTPUTS
    System.String
    #>
    [string] GetForestShortName([string] $domain) {
        Write-Verbose -Message ("Resolving forest short name for domain '{0}'." -f $domain)
        $forest = Get-ADForest -Server $domain
        $shortName = $null
        switch ($forest.Name.ToLowerInvariant()) {
            'mtu.corp' { $shortName = 'MTU' }
            'mtudev.corp' { $shortName = 'MTUDEV' }
            'ads.mtugov.de' { $shortName = 'MTUGOV' }
            'ads.mtuchina.app' { $shortName = 'MTUCHINA' }
            default { $shortName = [string] $forest.Name }
        }

        Write-Verbose -Message ("Resolved forest short name '{0}' for forest '{1}'." -f $shortName, $forest.Name)
        return $shortName
    }

    <#
    .SYNOPSIS
    Resolves the AD site for a subnet with fallback candidates.
    .OUTPUTS
    System.String
    #>
    [string] GetSubnetSite([IPv4Subnet] $subnet, [string] $domainController) {
        Write-Verbose -Message ("Resolving AD site for subnet '{0}' via domain controller '{1}'." -f $subnet.Cidr, $domainController)
        # AD may only contain broader subnet entries, so the lookup deliberately tries less specific fallback candidates.
        foreach ($candidate in $subnet.GetAdLookupCandidates()) {
            Write-Debug -Message ("Trying AD subnet candidate '{0}'." -f $candidate)
            try {
                $entry = Get-ADReplicationSubnet -Server $domainController -Filter ("Name -eq '{0}'" -f $candidate) -ErrorAction Stop
            }
            catch {
                Write-Debug -Message ("AD lookup failed for subnet candidate '{0}' on '{1}': {2}" -f $candidate, $domainController, $_.Exception.Message)
                continue
            }

            if ($null -ne $entry) {
                foreach ($item in @($entry)) {
                    if ($item.Site) {
                        $resolvedSite = (($item.Site -split ',')[0] -replace '^CN=')
                        Write-Verbose -Message ("Resolved AD site '{0}' for subnet '{1}' using candidate '{2}'." -f $resolvedSite, $subnet.Cidr, $candidate)
                        return $resolvedSite
                    }
                }
            }
        }

        Write-Verbose -Message ("No AD site mapping found for subnet '{0}' via domain controller '{1}'." -f $subnet.Cidr, $domainController)
        return $null
    }
}
