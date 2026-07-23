################################################################
# HelloID-Conn-Prov-Target-Canvas-SubPermissions-Group
# PowerShell V2
################################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Script Mapping lookup values
# Lookup values which are used in the mapping to determine the subPermissions
$PrimaryLookupKey = { $_.Custom.LesGroepCodeCreate }  # Mandatory

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

# Begin
try {
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($Actioncontext.configuration.access_token)")
    $headers.Add('Accept', 'application/Json')
    $headers.Add('Content-Type', 'application/Json')

    try {
        Write-Information 'Verifying if a Canvas account exists'
        $splatParams = @{
            Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/users/$($actionContext.References.Account)"
            Method  = 'GET'
            Headers = $headers
        }        
        $correlatedAccount = Invoke-RestMethod @splatParams -Verbose:$false
    }
    catch {
        if ($_.Exception.Message -notmatch '404' ) {
            throw $_
        }
    }

    if ($null -ne $correlatedAccount) {
        $lifecycleProcess = 'ManageSubPermissions'
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    switch ($lifecycleProcess) {
        'ManageSubPermissions' {
            # Collect current permissions
            $currentPermissions = @{}
            foreach ($permission in $actionContext.CurrentPermissions) {
                $currentPermissions[$permission.Reference.Id] = $permission.DisplayName
            }

            $splatRetrievePermissionsParams = @{
                Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/accounts/$($Actioncontext.configuration.AccountId)/groups?sort=id&per_page=500"
                Method  = 'GET'
                Headers = $headers
            }
            $retrievedPermissions = (Invoke-RestMethod @splatRetrievePermissionsParams -FollowRelLink) | ForEach-Object { $_ } | Select-Object id, name                           
            $retrievedPermissionsGrouped = $retrievedPermissions | Group-Object -Property name -AsHashTable            

            # Collect desired permissions
            $desiredPermissions = @{}
            if (-not($actionContext.Operation -eq 'revoke')) {
                foreach ($contract in $personContext.Person.Contracts) { 

                    $primaryValue = $contract | ForEach-Object $PrimaryLookupKey

                    if ($contract.Context.InConditions -or ($actionContext.DryRun -eq $true)) {                         
                        if (!([string]::IsNullOrEmpty($primaryValue))) {
                            $group = $retrievedPermissionsGrouped["$primaryValue"]
                            if ($null -ne $group) {
                                $mappedItem = @{
                                    Name = "$($group.id)"
                                    Id   = "$($group.name)"                                
                                }
                                $desiredPermissions[$mappedItem.Name] = $mappedItem.Id
                            }
                            else {
                                Write-Warning "No existing Canvas groups found for: [$primaryValue]"
                            }
                        }
                    }                    
                }
            }

            # Process desired permissions to grant
            foreach ($permission in $desiredPermissions.GetEnumerator()) {
                $outputContext.SubPermissions.Add([PSCustomObject]@{
                        DisplayName = $permission.Value
                        Reference   = [PSCustomObject]@{
                            Id = $permission.Name
                        }
                    })

                if (-not $currentPermissions.ContainsKey($permission.Name)) {
                    if (-not($actionContext.DryRun -eq $true)) {
                        # Make sure to test with special characters and if needed; add utf8 encoding.
                        if (-not($actionContext.DryRun -eq $true)) {
                            Write-Information "Granting Canvas permission: [$($permission.Value)] - [$($permission.Name)]"
                            $splatParams = @{
                                Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/groups/$($permission.Name)/memberships?user_id=$($actionContext.References.Account)"
                                Method  = 'POST'
                                Headers = $headers
                            }        
                            $grantedPermission = Invoke-RestMethod @splatParams -Verbose:$false
                            Write-Information "Canvas permission: [$($permission.Value)] - [$($permission.Name)] succesfully granted with membership_id [$($grantedPermission.id)]"

                        }
                        else {
                            Write-Information "[DryRun] Grant Canvas permission: [$($permission.Value)] - [$($permission.Name)], will be executed during enforcement"
                        }
                    }

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = 'GrantPermission'
                            Message = "Granted access to permission [$($permission.Value)]"
                            IsError = $false
                        })
                }
            }

            # Process current permissions to revoke
            $newCurrentPermissions = @{}
            foreach ($permission in $currentPermissions.GetEnumerator()) {
                if (-not $desiredPermissions.ContainsKey($permission.Name)) {
                    if (-not($actionContext.DryRun -eq $true)) {
                        # Write permission revoke logic here
                        if (-not($actionContext.DryRun -eq $true)) {
                            Write-Information "Revoking Canvas permission: [$($permission.Value)] - [$($permission.Name)]"

                            $splatParams = @{
                                Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/groups/$($permission.Name)/users/$($actionContext.References.Account)"
                                Method  = 'DELETE'
                                Headers = $headers
                            }        
                            $null = Invoke-RestMethod @splatParams -Verbose:$false
                        }
                        else {
                            Write-Information "[DryRun] Revoke Canvas permission: [$($permission.Value)] - [$($permission.Name)], will be executed during enforcement"
                        }
                    }

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = 'RevokePermission'
                            Message = "Revoked access to permission [$($permission.Value)]"
                            IsError = $false
                        })
                }
                else {
                    $newCurrentPermissions[$permission.Name] = $permission.Value
                }
            }
            $outputContext.Success = $true
            break
        }

        'NotFound' {
            Write-Information "Canvas account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Canvas account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CanvasError -ErrorObject $ex
        $auditLogMessage = "Could not revoke Canvas permission for account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage). Action initiated by: [$($actionContext.Origin)]"
        $warningMessage = "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not revoke Canvas permission for account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message). Action initiated by: [$($actionContext.Origin)]"
        $warningMessage = "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    if ($PSItem.Exception.Response.StatusCode -eq 'NotFound') {
        $outputContext.success = $true
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Skipped $($actionMessage). Reason: User is already no longer a member."
                IsError = $false
            })
    }
    else {
        Write-Warning $warningMessage
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $auditLogMessage
                IsError = $true
            })
    }
}