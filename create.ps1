#####################################################
# HelloID-Conn-Prov-Target-Canvas-Create
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    # User [user]
    # The 'name' is the full name of the person
    'user[name]' = "$($p.Name.GivenName) $($p.Name.FamilyName)"

    # The 'short_name' is the user's name as it will be displayed in the UI
    'user[short_name]'    = $p.DisplayName
    'user[sortable_name]' = ""

    # Timezones myst be IANA time zones like: CE, CEST, CEMT
    'user[time_zone]'         = 'CEST'
    'user[terms_of_use]'      = $true
    'user[skip_registration]' = $true

    # The 'locale' is the user's preferred language like: en, de, nl, nl_BE, en_US, etc..
    'user[locale]' = 'nl'

    # User [communication_channel]
    'communication_channel[type]'              = 'email'
    'communication_channel[address]'           = $p.Accounts.MicrosoftActiveDirectory.mail
    'communication_channel[skip_confirmation]' = $true

    # User [pseudnonym]
    # the 'unique_id' for self registration must be set to the emailAddress
    'pseudnonym[unique_i]'          = $p.ExternalId
    'pseudnonym[password]'          = 'Work'
    'pseudnonym[send_confirmation]' = $true
}

# Updated account mapping
$updateAccount = @{
    'user[name]'          = "$($p.Name.GivenName) $($p.Name.FamilyName)"
    'user[short_name]'    = $p.DisplayName
    'user[sortable_name]' = ""
    'user[email]'         = $p.Accounts.MicrosoftActiveDirectory.mail
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set to true if accounts in the target system must be updated
$updatePerson = $false

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    Write-Verbose 'Retrieving authorization token'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Content-Type", "application/x-www-form-urlencoded")
    $tokenBody = @{
        client_id     = $($config.ClientId)
        client_secret = $($config.ClientSecret)
        redirect_uri  = $($config.RedirectUri)
        code          = $($config.Code)
        grant_type    = 'authorization_code'
    }
    $tokenResponse = Invoke-RestMethod -Uri "$($config.BaseUrl)/login/oauth2/token" -Method 'POST' -Headers $headers -Body $tokenBody -verbose:$false

    Write-Verbose 'Setting authorization header'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "Bearer $($tokenResponse.access_token)")

    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]
    Write-Verbose 'Retrieving all accounts'
    $splatParams = @{
        Uri     = "$($config.ApiUrl)/api/v1/accounts/$($config.AccountId)/users"
        Method  = 'GET'
        Headers = $headers
    }
    $response = Invoke-RestMethod @splatParams Verbose:$false
    $lookupUser = $response | Group-Object -Property uid -AsHashTable -AsString
    $responseUser = $lookupUser[$account.address]
    if (-not($responseUser)){
        $action = 'Create-Correlate'
    } elseif ($updatePerson -eq $true) {
        $action = 'Update-Correlate'
    } else {
        $action = 'Correlate'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action Canvas account for: [$($p.DisplayName)], will be executed during enforcement"
            })
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose "Creating and correlating Canvas account"
                $splatParams = @{
                    Uri     = "$($config.ApiUrl)/api/v1/accounts/$($config.AccountId)/users"
                    Method  = 'POST'
                    Headers = $headers
                    Body    = $account | ConvertTo-Json
                }
                $response = Invoke-RestMethod @splatParams -Verbose:$false
                $accountReference = $response.id
                break
            }

            'Update-Correlate' {
                Write-Verbose "Updating and correlating Canvas account"
                $splatParams = @{
                    Uri     = "$($config.ApiUrl)/api/v1/accounts/$($config.AccountId)/users"
                    Method  = 'PUT'
                    Headers = $headers
                    Body    = $updateAccount | ConvertTo-Json
                }
                $response = Invoke-RestMethod @splatParams -Verbose:$false
                $accountReference = $response.id
                break
            }

            'Correlate' {
                Write-Verbose "Correlating Canvas account"
                $accountReference = $responseUser.id
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountReference]"
                IsError = $false
            })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not $action Canvas account. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not $action Canvas account. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
# End
} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
