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
    # The 'name' is the full name of the person
    # The 'short_name' is the user's name as it will be displayed in the UI
    # Timezones myst be IANA time zones like: CE, CEST, CEMT
    # The 'locale' is the user's preferred language like: en, de, nl, nl_BE, en_US, etc..
    user                  = @{
        name              = $p.DisplayName
        short_name        = "$($p.Name.GivenName) $($p.Name.FamilyName)"
        sortable_name     = "$($p.Name.FamilyName), $($p.Name.GivenName)"
        time_zone         = 'CEST'
        terms_of_use      = $true
        skip_registration = $true
        locale            = 'nl'
    }
    communication_channel = @{
        type              = 'email'
        address           = "$($p.Contact.Business.email)"
        skip_confirmation = $true
    }
    # the 'unique_id' for self registration must be set to the emailAddress
    pseudonym             = @{
        unique_id         = "$($p.Contact.Business.email)"
        password          = 'Welkom123xxxxxxx'
        send_confirmation = $true
        sis_user_id       = ''
        integration_id    = ''
    }
}

$accountUpdateBody = [PSCustomObject]@{
    user = [PSCustomObject]@{
        name          = $account.user.name
        short_name    = $account.user.short_name
        sortable_name = $account.user.sortable_name
        email         = $account.communication_channel.address
        # title         = '' Only possible in Update webrequest
    }
}


# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set to true if accounts in the target system must be updated
$updatePerson = $true

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = ''
            FriendlyMessage  = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message + $ErrorObject.ErrorDetails.Message

            if ($null -ne $ErrorObject.ErrorDetails.Message ) {
                $jsonErrorObject = $ErrorObject.ErrorDetails.Message | ConvertFrom-Json
            }

            $httpErrorObj.FriendlyMessage = switch ($jsonErrorObject) {
                { -not [string]::IsNullOrWhiteSpace($_.errors.message) } { $_.errors.message }
                { -not [string]::IsNullOrWhiteSpace($_.message) } { $_.message }
                { $null -ne $_.errors.pseudonym.password } { "Incorrect Password [$($_.errors.pseudonym.password.message -join ', ')]" }
                { $null -ne $_.errors.pseudonym.unique_id } { "Incorrect unique_id [$($_.errors.pseudonym.unique_id.message -join ', '))]" }
                default { $ErrorObject.ErrorDetails.Message }
            }


        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -eq $ErrorObject.Exception.Response) {
                $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message
                $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Message
            } else {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message + $streamReaderResponse
                $jsonErrorObject = $streamReaderResponse | ConvertFrom-Json
                $httpErrorObj.FriendlyMessage = switch ($jsonErrorObject) {
                    { -not [string]::IsNullOrWhiteSpace($_.errors.message) } { $_.errors.message }
                    { -not [string]::IsNullOrWhiteSpace($_.message) } { $_.message }
                    { $null -ne $_.errors.pseudonym.password } { "Incorrect Password [$($_.errors.pseudonym.password.message -join ', ')]" }
                    { $null -ne $_.errors.pseudonym.unique_id } { "Incorrect unique_id [$($_.errors.pseudonym.unique_id.message -join ', '))]" }
                    default { $streamReaderResponse }
                }
            }
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    Write-Verbose 'Setting authorization header'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($config.access_token)")
    $headers.Add('Accept', 'application/Json')
    $headers.Add('Content-Type', 'application/Json')

    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]
    Write-Verbose "Retrieving accounts with [search_term=$($account.pseudonym.unique_id)]"
    $splatParams = @{
        Uri     = "$($config.BaseUrl)/api/v1/accounts/$($config.AccountId)/users?search_term=$($account.pseudonym.unique_id)"
        Method  = 'GET'
        Headers = $headers
    }
    $response = Invoke-RestMethod @splatParams -Verbose:$false
    $responseUser = $response | Where-Object { $_.login_id -eq $account.pseudonym.unique_id }

    if (-not($responseUser)) {
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
                Write-Verbose 'Creating and correlating Canvas account'
                $splatParams = @{
                    Uri     = "$($config.BaseUrl)/api/v1/accounts/$($config.AccountId)/users"
                    Method  = 'POST'
                    Headers = $headers
                    Body    = $account | ConvertTo-Json
                }
                $response = Invoke-RestMethod @splatParams -Verbose:$false
                $accountReference = $response.id
                break
            }

            'Update-Correlate' {
                Write-Verbose 'Updating and correlating Canvas account'
                $splatParams = @{
                    Uri     = "$($config.BaseUrl)/api/v1/users/$($responseUser.id)"
                    Method  = 'PUT'
                    Headers = $headers
                    Body    = $accountUpdateBody  | ConvertTo-Json
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
        $auditMessage = "Could not $action Canvas account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not $action Canvas account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        # Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
