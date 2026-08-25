####################################################################
# HelloID-Conn-Prov-Target-Canvas-ImportPermissions-Group
# PowerShell V2
####################################################################

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
    Write-Information 'Starting Canvas permission entitlement import'
    
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($Actioncontext.Configuration.access_token)")
    $headers.Add('Accept', 'application/Json')
    $headers.Add('Content-Type', 'application/Json')

    $pageSize = 100

    $splatRetrievePermissionsParams = @{
        Uri                     = "$($Actioncontext.configuration.BaseUrl)/api/v1/accounts/$($Actioncontext.configuration.AccountId)/groups?sort=id&per_page=$pageSize"
        Method                  = 'GET'
        Headers                 = $headers
        ResponseHeadersVariable = 'responseHeaders'
    }
    $retrievedPermissions = (Invoke-RestMethod @splatRetrievePermissionsParams -FollowRelLink) | ForEach-Object { $_ }    

    foreach ($importedPermission in $retrievedPermissions) {
        $permission = @{
            PermissionReference = @{
                Reference = $importedPermission.id
            }
            Description         = "$($importedPermission.name)"
            AccountReferences   = $null            
        }

        $splatRetrieveMembershipsParams = @{
            Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/groups/$($importedPermission.id)/users?per_page=$pageSize"
            Method  = 'GET'
            Headers = $headers
        }
        
        $retrievedMembers = @((Invoke-RestMethod @splatRetrieveMembershipsParams -FollowRelLink) | ForEach-Object { $_.id })
        
        if ($retrievedMembers.Count -gt 0) {
            # The code below splits a list of permission members into batches of 100
            # Each batch is assigned to $permission.AccountReferences and the permission object will be returned to HelloID for each batch
            # Ensure batching is based on the number of account references to prevent exceeding the maximum limit of 500 account references per batch
            $batchSize = 500
            for ($i = 0; $i -lt ($retrievedMembers | Measure-Object).Count; $i += $batchSize) {
                $permission.AccountReferences = $retrievedMembers[$i..([Math]::Min($i + $batchSize - 1, $retrievedMembers.Count - 1))]
                Write-Output $permission
            }
        }
    }
    Write-Information 'Canvas permission entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CanvasError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Canvas permission entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Canvas permission entitlements. Error: $($ex.Exception.Message)"
    }
}