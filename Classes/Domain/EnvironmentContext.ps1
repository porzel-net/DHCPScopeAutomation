# Encapsulates environment-specific behavior such as DNS zones and delegation rules.
<#
.SYNOPSIS
Encapsulates environment-specific behavior for the automation.

.DESCRIPTION
Normalizes the requested environment and exposes derived values such as DNS zone,
delegation validation domain, and convenience checks for dev, test, and prod.

.NOTES
Methods:
- EnvironmentContext(name)
- IsDevelopment()
- IsTest()
- IsProduction()
- GetDelegationValidationDomain()

.EXAMPLE
[EnvironmentContext]::new('prod')
#>
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

    <#
    .SYNOPSIS
    Returns whether the runtime targets the development environment.
    .OUTPUTS
    System.Boolean
    #>
    [bool] IsDevelopment() {
        return $this.Name -eq 'dev'
    }

    <#
    .SYNOPSIS
    Returns whether the runtime targets the test environment.
    .OUTPUTS
    System.Boolean
    #>
    [bool] IsTest() {
        return $this.Name -eq 'test'
    }

    <#
    .SYNOPSIS
    Returns whether the runtime targets the production environment.
    .OUTPUTS
    System.Boolean
    #>
    [bool] IsProduction() {
        return $this.Name -eq 'prod'
    }

    <#
    .SYNOPSIS
    Returns the delegation-validation domain for the environment.

    .DESCRIPTION
    Test resolves delegation against the production delegation domain while the
    other environments validate against their own DNS zone.
    .OUTPUTS
    System.String
    #>
    [string] GetDelegationValidationDomain() {
        if ($this.DnsZone -eq 'test.mtu.corp') {
            return 'de.mtu.corp'
        }

        return $this.DnsZone
    }
}
