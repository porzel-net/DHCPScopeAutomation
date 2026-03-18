# Encapsulates environment-specific behavior such as DNS zones and delegation rules.
class EnvironmentContext {
    [string] $Name
    [string] $DnsZone

    EnvironmentContext([string] $name) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [System.ArgumentException]::new('Environment name is required.')
        }

        $normalizedName = $name.Trim().ToLowerInvariant()
        switch ($normalizedName) {
            'dev'   { $this.DnsZone = 'de.mtudev.corp' }
            'test'  { $this.DnsZone = 'test.mtu.corp' }
            'prod'  { $this.DnsZone = 'de.mtu.corp' }
            'gov'   { $this.DnsZone = 'ads.mtugov.de' }
            'china' { $this.DnsZone = 'ads.mtuchina.app' }
            default { throw [System.ArgumentOutOfRangeException]::new('name', "Unsupported environment '$name'.") }
        }

        $this.Name = $normalizedName
    }

    [bool] IsDevelopment() {
        return $this.Name -eq 'dev'
    }

    [bool] IsTest() {
        return $this.Name -eq 'test'
    }

    [bool] IsProduction() {
        return $this.Name -eq 'prod'
    }

    [string] GetDelegationValidationDomain() {
        if ($this.DnsZone -eq 'test.mtu.corp') {
            return 'de.mtu.corp'
        }

        return $this.DnsZone
    }
}
