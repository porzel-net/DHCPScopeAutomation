<#
.SYNOPSIS
Retrieves the value of a specified key from a .env file.

.DESCRIPTION
This function reads a .env file and returns the value associated with a given key.
If the key is not found, it throws an error including a description of the expected value.
It also allows specifying the expected data type (string, int, bool) for conversion.

.PARAMETER KeyName
The name of the environment variable to retrieve.

.PARAMETER Description
A description of the expected value, used in the error message if the key is missing.

.PARAMETER EnvFilePath
Optional path to the .env file. Defaults to ".env" in the current directory.

.PARAMETER DataType
Optional expected data type of the value. Supports "string", "int", and "bool". Defaults to "string".

.EXAMPLE
$apiKey = Get-EnvValue -KeyName "API_KEY" -Description "The API key used to authenticate requests to the external service"

.EXAMPLE
$retryCount = Get-EnvValue -KeyName "RETRY_COUNT" -Description "Number of retry attempts" -DataType "int"

.EXAMPLE
$isEnabled = Get-EnvValue -KeyName "FEATURE_ENABLED" -Description "Feature toggle" -DataType "bool"

.NOTES
Lines starting with '#' or empty lines are ignored. Key-value pairs must be in the format KEY=VALUE.
#>
function Get-EnvValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$KeyName,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [string]$EnvFilePath = (Join-Path $pwd "\.env"),

        [ValidateSet("string", "int", "bool")]
        [string]$DataType = "string"
    )

    Write-Verbose "Reading environment file from '$EnvFilePath'."
    if (-not (Test-Path -Path $EnvFilePath)) {
        throw "The environment file '$EnvFilePath' does not exist. Please ensure the file is present and accessible."
    }

    $envData = @{}
    Write-Debug "Parsing .env file content..."
    Get-Content -Path $EnvFilePath | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_) -or $_.Trim().StartsWith("#")) {
            return
        }

        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) {
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            $envData[$key] = $value
            Write-Debug "Found key '$key' with value '$value'."
        }
    }

    if (-not $envData.ContainsKey($KeyName)) {
        throw "Environment variable '$KeyName' is not defined. Description: $Description"
    }

    $rawValue = $envData[$KeyName]
    Write-Information "Retrieved value for '$KeyName': $rawValue"

    switch ($DataType) {
        "int" {
            [int]$parsedValue = 0
            Write-Verbose "Converting value to integer..."
            if (-not [int]::TryParse($rawValue, [ref]$parsedValue)) {
                throw "Value for '$KeyName' is not a valid integer. Found: '$rawValue'"
            }
            return $parsedValue
        }
        "bool" {
            Write-Verbose "Converting value to boolean..."
            switch ($rawValue.ToLower()) {
                "true"  { return $true }
                "false" { return $false }
                default { throw "Value for '$KeyName' is not a valid boolean. Expected 'true' or 'false', found: '$rawValue'" }
            }
        }
        default {
            Write-Verbose "Returning value as string."
            return $rawValue
        }
    }
}


<#
.SYNOPSIS
Sends an email notification.

.DESCRIPTION
This function sends an email from reports@mtu.de to the specified recipient using the domain's SMTP server. It allows specifying the subject and body content. Errors during send are caught and reported to the console.

.PARAMETER To
Recipient email address.

.PARAMETER Subject
Subject line of the email.

.PARAMETER Body
Body text of the email.

.PARAMETER BodyAsHtml
Wheter the body should be send as html or not.

.EXAMPLE
Send-Mail -To 'user@example.com' -Subject 'Config Alert' -Body 'The expected configuration differs.'
#>
function Send-Mail {
    param (
        [Parameter(Mandatory=$true)]
        [string]$To,
        [Parameter(Mandatory=$true)]
        [string]$Subject,
        [Parameter(Mandatory=$true)]
        [string]$Body,
        [Parameter(Mandatory=$false)]
        [Switch]$BodyAsHtml
    )

    $From = "reports@mtu.de"

    $smtpServer = "smtpmail.$((Get-ADDomain).DNSRoot)"

    try {
        Send-MailMessage -From $From -To $To -Subject $Subject -BodyAsHtml -Body $Body -SmtpServer $SmtpServer -ErrorAction Stop

        Write-Host "Notification email sent to $To via $SmtpServer." -ForegroundColor Green
    } catch {
        Write-Host "Error: Failed to send email: $_" -ForegroundColor Red
    }
}
