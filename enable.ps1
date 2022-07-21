#####################################################
# HelloID-Conn-Prov-Target-Canvas-Enable
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

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

try {
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Enable Canvas account for: [$($p.DisplayName)] will be executed during enforcement"
            })
    }

    if (-not($dryRun -eq $true)) {
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
        $tokenResponse = Invoke-RestMethod -Uri "$($config.BaseUrl)/login/oauth2/token" -Method 'POST' -Headers $headers -Body $tokenBody -Verbose:$false

        Write-Verbose 'Setting authorization header'
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add("Authorization", "Bearer $($tokenResponse.access_token)")

        Write-Verbose "Enabling Canvas account with accountReference: [$aRef]"
        $splatParams = @{
            Uri     = "$($config.ApiUrl)/api/v1/accounts/$($config.AccountId)/users/$aRef"
            Method  = 'PUT'
            Headers = $headers
            Body    = @{
                'user[event]' = 'unsuspend'
            } | ConvertTo-Json
        }
        $null = Invoke-RestMethod @splatParams -Verbose:$false

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = 'Enable account was successful'
                IsError = $false
            })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not enable Canvas account. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not enable Canvas account. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
