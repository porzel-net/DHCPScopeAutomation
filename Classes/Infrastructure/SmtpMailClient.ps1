# Wraps SMTP delivery for operational notifications.
<#
.SYNOPSIS
Sends notification mail through the domain SMTP relay.

.DESCRIPTION
Uses the Active Directory DNS root to derive the SMTP relay and sends HTML mail
messages for aggregated failure notifications.

.NOTES
Methods:
- SmtpMailClient(activeDirectoryAdapter)
- SendHtmlMail(recipients, subject, htmlBody)

.EXAMPLE
$mailClient = [SmtpMailClient]::new($activeDirectoryAdapter)
$mailClient.SendHtmlMail(@('ops@example.test'), 'DHCPScopeAutomation', '<p>Failure</p>')
#>
class SmtpMailClient {
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter

    SmtpMailClient([ActiveDirectoryAdapter] $activeDirectoryAdapter) {
        if ($null -eq $activeDirectoryAdapter) {
            throw [System.ArgumentNullException]::new('activeDirectoryAdapter')
        }

        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
    }

    <#
    .SYNOPSIS
    Sends one HTML mail through the derived SMTP relay.
    .OUTPUTS
    System.Void
    #>
    [void] SendHtmlMail([string[]] $recipients, [string] $subject, [string] $htmlBody) {
        if (-not $recipients) {
            return
        }

        $smtpServer = ('smtpmail.{0}' -f $this.ActiveDirectoryAdapter.GetDomainDnsRoot())
        Send-MailMessage -From 'reports@mtu.de' -To $recipients -Subject $subject -Body $htmlBody -BodyAsHtml -SmtpServer $smtpServer -ErrorAction Stop
    }
}
