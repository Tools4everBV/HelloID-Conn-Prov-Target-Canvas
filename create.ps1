#################################################
# HelloID-Conn-Prov-Target-Canvas-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Account mapping
$account = [PSCustomObject]@{
    # The 'name' is the full name of the person
    # The 'short_name' is the user's name as it will be displayed in the UI
    # Timezones must be IANA time zones like: CE, CEST, CEMT
    # The 'locale' is the user's preferred language like: en, de, nl, nl_BE, en_US, etc..
    user                  = @{
        name              = "$($actionContext.Data.name)"
        short_name        = "$($actionContext.Data.short_name)"
        sortable_name     = "$($actionContext.Data.sortable_name)"
        time_zone         = "$($actionContext.Data.time_zone)"
        terms_of_use      = $true
        skip_registration = $true
        locale            = "$($actionContext.Data.locale)"
    }
    communication_channel = @{
        type              = 'email'
        address           = "$($actionContext.Data.email)"
        skip_confirmation = $true
    }
    # the 'unique_id' for self registration must be set to the emailAddress
    pseudonym             = @{
        unique_id         = "$($actionContext.Data.email)"
        password          = "$($Actioncontext.Data.password)"
        send_confirmation = $true
        sis_user_id       = ''
        integration_id    = ''
    }
}

#region functions
function Resolve-CanvasError {
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
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)

            $httpErrorObj.FriendlyMessage = switch ($errorDetailsObject) {
                { -not [string]::IsNullOrWhiteSpace($_.errors.message) } { $_.errors.message }
                { -not [string]::IsNullOrWhiteSpace($_.message) } { $_.message }
                { $null -ne $_.errors.pseudonym.password } { "Incorrect Password [$($_.errors.pseudonym.password.message -join ', ')]" }
                { $null -ne $_.errors.pseudonym.unique_id } { "Incorrect unique_id [$($_.errors.pseudonym.unique_id.message -join ', '))]" }
                default { $httpErrorObj.ErrorDetails }
            }           
           
        } catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($Actioncontext.configuration.access_token)")
    $headers.Add('Accept', 'application/Json')
    $headers.Add('Content-Type', 'application/Json')


    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [PersonFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]

       
        $splatParams = @{
            Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/accounts/$($Actioncontext.configuration.AccountId)/users?search_term=$correlationValue"
            Method  = 'GET'
            Headers = $headers
        }
        $response = Invoke-RestMethod @splatParams -Verbose:$false
        $correlatedAccount = $response | Where-Object { $_.login_id -eq $correlationValue }                   
    }

    if ($null -ne $correlatedAccount) {
        $action = 'CorrelateAccount'
    } else {
        $action = 'CreateAccount'
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            $splatCreateParams = @{
                Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/accounts/$($Actioncontext.configuration.AccountId)/users"
                Method  = 'POST'
                Headers = $headers
                Body    = $account | ConvertTo-Json
            }

            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Canvas account'               
                $createdAccount = Invoke-RestMethod @splatCreateParams
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.Id
            } else {
                Write-Information '[DryRun] Create and correlate Canvas account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Canvas account'
            $outputContext.Data = $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.Id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CanvasError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Canvas account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate Canvas account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}