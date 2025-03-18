##################################################
# HelloID-Conn-Prov-Target-Canvas-Delete
# PowerShell V2
##################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Verifying if a Canvas account exists'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($actionContext.configuration.access_token)")
    $headers.Add('Accept', 'application/Json')
    $headers.Add('Content-Type', 'application/Json')

    $splatParams = @{
        Uri     = "$($actionContext.configuration.BaseUrl)/api/v1/users/$($actionContext.References.Account)"
        Method  = 'GET'
        Headers = $headers
    }

    try {
        $correlatedAccount = Invoke-RestMethod @splatParams -Verbose:$false
    } catch {
        if ($_.Exception.Message -notmatch '404' ) {
            throw $_
        }
    } 

    if ($null -ne $correlatedAccount) {
        $action = 'DeleteAccount'
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'DeleteAccount' {
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Deleting Canvas account with accountReference: [$($actionContext.References.Account)]"
                 $splatParams = @{
                    Uri     = "$($actionContext.configuration.BaseUrl)/api/v1/accounts/$($actionContext.configuration.AccountId)/users/$($actionContext.References.Account)"
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

            } else {
                Write-Information "[DryRun] Delete Canvas account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Delete account was successful'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Canvas account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Canvas account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
                    IsError = $false
                })
            break
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CanvasError -ErrorObject $ex
        $auditMessage = "Could not delete Canvas account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not delete Canvas account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}