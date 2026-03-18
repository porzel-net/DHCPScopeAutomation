# Wraps SMTP delivery for operational notifications.
class SmtpMailClient {
    [ActiveDirectoryAdapter] $ActiveDirectoryAdapter

    SmtpMailClient([ActiveDirectoryAdapter] $activeDirectoryAdapter) {
        if ($null -eq $activeDirectoryAdapter) {
            throw [System.ArgumentNullException]::new('activeDirectoryAdapter')
        }

        $this.ActiveDirectoryAdapter = $activeDirectoryAdapter
    }

    [void] SendHtmlMail([string[]] $recipients, [string] $subject, [string] $htmlBody) {
        if (-not $recipients) {
            return
        }

        $smtpServer = ('smtpmail.{0}' -f $this.ActiveDirectoryAdapter.GetDomainDnsRoot())
        Send-MailMessage -From 'reports@mtu.de' -To $recipients -Subject $subject -Body $htmlBody -BodyAsHtml -SmtpServer $smtpServer -ErrorAction Stop
    }
}
