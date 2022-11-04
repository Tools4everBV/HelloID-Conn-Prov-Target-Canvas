#####################################################
# HelloID-Conn-Prov-Target-Canvas-Update
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    user = [PSCustomObject]@{
        name          = $p.DisplayName
        sortable_name = "$($p.Name.FamilyName), $($p.Name.GivenName)"
        short_name    = "$($p.Name.GivenName) $($p.Name.FamilyName)"
        email         = "$($p.Contact.Business.email)"
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
    Write-Verbose 'Setting authorization header'
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($config.access_token)")
    $headers.Add('Accept', 'application/Json')
    $headers.Add('Content-Type', 'application/Json')

    # Verify if the account must be updated
    Write-Verbose "Retrieving current account [$aref]"
    $splatParams = @{
        Uri     = "$($config.BaseUrl)/api/v1/users/$aref"
        Method  = 'GET'
        Headers = $headers
    }
    try {
        $currentAccount = Invoke-RestMethod @splatParams -Verbose:$false
    } catch {
        if ($_.Exception.Message -notmatch '404' ) {
            throw $_
        }
    }

    Write-Verbose 'Validate if there are any changes in the account between HelloId and Canvas'
    $updateBody = @{ user = @{} }
    foreach ($prop in  $account.user.PSObject.Properties) {
        if ( $currentAccount.$($prop.name) -ne $prop.value) {
            $updateBody.user.Add($($prop.name), $prop.value)
        }
    }

    if ($updateBody.user.Count -gt 0 -and ($null -ne $currentAccount)) {
        $action = 'Update'
        $dryRunMessage = "Account property(s) required to update: [$($updateBody.user.keys -join ', ')]"
    } elseif ($updateBody.user.Count -eq 0) {
        $action = 'NoChanges'
        $dryRunMessage = 'No changes will be made to the account during enforcement'
    } elseif ($null -eq $currentAccount) {
        $action = 'NotFound'
        $dryRunMessage = "Canvas account for: [$($p.DisplayName)] not found. Possibily deleted"
    }
    Write-Verbose "$dryRunMessage"

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Update' {
                Write-Verbose "Updating Canvas account with accountReference: [$aRef]"
                $splatParams = @{
                    Uri     = "$($config.BaseUrl)/api/v1/users/$aref"
                    Method  = 'PUT'
                    Headers = $headers
                    Body    = $updateBody | ConvertTo-Json
                }
                $null = Invoke-RestMethod @splatParams -Verbose:$false
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Update account was successful'
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to Canvas account with accountReference: [$aRef]"

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'No changes will be made to the account during enforcement'
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $success = $false
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Canvas account for: [$($p.DisplayName)] not found. Possibily deleted"
                        IsError = $true
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
        $auditMessage = "Could not update Canvas account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Canvas account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Account   = $account
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
