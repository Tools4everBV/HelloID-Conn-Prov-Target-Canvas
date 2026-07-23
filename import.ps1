#################################################
# HelloID-Conn-Prov-Target-Canvas-Import
# PowerShell V2
#################################################

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
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
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
           
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Information 'Starting Canvas account entitlement import'
    
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($Actioncontext.Configuration.access_token)")
    $headers.Add('Accept', 'application/Json')
    $headers.Add('Content-Type', 'application/Json')

    $pageSize = 500
   
    $splatImportAccountParams = @{
        Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/accounts/$($Actioncontext.configuration.AccountId)/users?sort=id&per_page=$pageSize"
        Method  = 'GET'
        Headers = $headers
    }
    $importedAccounts = (Invoke-RestMethod @splatImportAccountParams -FollowRelLink) | ForEach-Object { $_ } | Select-Object id -Unique

    foreach ($importedAccount in $importedAccounts) {

        $splatUserAccountParams = @{
            Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/users/$($importedAccount.id)"
            Method  = 'GET'
            Headers = $headers
        }

        try {
            $userAccount = Invoke-RestMethod @splatUserAccountParams
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq '404') {
                $userAccount = $null
            }
        }

        if ($null -ne $userAccount) {
            if ('id' -notin $actionContext.ImportFields) {
                if ('id' -notin $importFields) { $importFields += 'id' }                  
            }

            if ('login_id' -notin $userAccount.PSObject.Properties.Name ) {
                $userAccount | Add-Member -Type NoteProperty -Name 'login_id' -Value $userAccount.id                    
            }

            $data = $userAccount | Select-Object -Property $actionContext.ImportFields

            # Make sure the displayName has a value
            $displayName = "$($userAccount.name)".trim()
            if ([string]::IsNullOrEmpty($displayName)) {
                $displayName = $userAccount.id
            }

            # Make sure the userName has a value
            $username = "$($userAccount.login_id)"
            if ([string]::IsNullOrWhiteSpace($userAccount.login_id)) {
                $username = "$($userAccount.id)"
            }

            Write-Output @{
                AccountReference = $($userAccount.id)
                DisplayName      = $displayName
                UserName         = $username
                Enabled          = $false #account status can't be determined
                Data             = $data
            }
        }
    }    
    
    Write-Verbose "Retrieved $($importedAccounts.Count) users from Canvas."
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CanvasError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Canvas account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Canvas account entitlements. Error: $($ex.Exception.Message)"
    }
}