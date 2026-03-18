# Isolates Active Directory lookups behind a testable adapter boundary.
class ActiveDirectoryAdapter {
    [string] GetDomainControllerName() {
        return [string] (Get-ADDomainController).Name
    }

    [string] GetDomainDnsRoot() {
        return [string] (Get-ADDomain).DNSRoot
    }

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

    [string] GetSubnetSite([IPv4Subnet] $subnet, [string] $domainController) {
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
