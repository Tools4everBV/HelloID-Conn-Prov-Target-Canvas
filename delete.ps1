#####################################################
# HelloID-Conn-Prov-Target-Canvas-Delete
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

try {
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Delete Canvas account from: [$($p.DisplayName)] will be executed during enforcement"
            })
    }
    Write-Verbose 'Setting authorization header'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($config.access_token)")
    $headers.Add('Accept', 'application/Json')
    $headers.Add('Content-Type', 'application/Json')

    Write-Verbose "Retrieving current account [$aref]"
    $splatParams = @{
        Uri     = "$($config.BaseUrl)/api/v1/users/$aref"
        Method  = 'GET'
        Headers = $headers
    }
    try {
        $null = Invoke-RestMethod @splatParams -Verbose:$false
        $action = 'Found'
    } catch {
        if ($_.Exception.Message -notmatch '404' ) {
            throw $_
        }
        $action = 'NotFound'
    }

    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Found' {
                Write-Verbose "Deleting Canvas account with accountReference: [$aRef]"
                $splatParams = @{
                    Uri     = "$($config.BaseUrl)/api/v1/accounts/$($config.AccountId)/users/$aRef"
                    Method  = 'DELETE'
                    Headers = $headers
                }
                try {
                    $null = Invoke-RestMethod @splatParams -Verbose:$false
                } catch {
                    if ($_.Exception.Message -notmatch '404' ) {
                        throw $_
                    }
                }

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Delete account was successful'
                        IsError = $false
                    })

                break
            }

            'NotFound' {
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Canvas account for: [$($p.DisplayName)] not found. Possibily already deleted. Skipping action"
                        IsError = $false
                    })
                break
            }
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $auditMessage = "Could not delete Canvas account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not delete Canvas account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
