##########################################################
# HelloID-Conn-Prov-Target-Canvas-Resources-Group
# PowerShell V2
##########################################################
$correlationField = 'LesgroepCodeCreate'
$correlationValue = "*.26*.*"

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
    Write-Information 'Retrieving permissions'     
    
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Authorization', "Bearer $($Actioncontext.Configuration.access_token)")
    $headers.Add('Accept', 'application/Json')
    $headers.Add('Content-Type', 'application/octet-stream')

    $splatListGroupParams = @{
        Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/accounts/$($Actioncontext.configuration.AccountId)/groups?sort=id&per_page=$pageSize"
        Method  = 'GET'
        Headers = $headers
    }
    $existingGroups = Invoke-RestMethod @splatListGroupParams -FollowRelLink
    Write-Information "Retrieved [$($existingGroups.Count)] groups"
    
    $resourceContext.SourceData = ( $resourceContext.SourceData | Where-Object {
            -not([string]::IsNullOrEmpty($_."$correlationField")) -and # Filter to exclude contracts without a value
            $_."$correlationField" -like $correlationValue -and # Filter to include contracts corresponding to the correlationvalue
            $_.Verbintenisstatus -eq 'Definitief' -and # Filter only students with a definitive commitment
            $_."$correlationField" -notin $existingGroups.Name # Filter only groups which do not already exist
        })

    Write-Information "Creating [$($resourceContext.SourceData.Count)] resources"

    if ($($resourceContext.SourceData.Count) -gt 0) {
        foreach ($resource in $resourceContext.SourceData) {   
            try {
                # Make sure to test with special characters and if needed; add utf8 encoding.
                if (-not ($actionContext.DryRun -eq $True)) {
                    Write-Information "Create [$($resource."$correlationField")] Canvas resource"
                    $group = [PSCustomObject][ordered]@{
                        group_id = $($resource."$correlationField")
                        name     = $($resource."$correlationField")
                        status   = 'available'
                    }
                    
                    # ConvertTo-Csv returns an array of CSV lines. Joining with CRLF creates the raw CSV document.
                    $csv = ($group | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
                    $csv += "`r`n"

                    
                    $splatImportGroupParams = @{
                        Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/accounts/$($Actioncontext.configuration.AccountId)/sis_imports?import_type=instructure_csv&extension=csv"
                        Method  = 'POST'
                        Headers = $headers            
                        Body    = $csv
                    }

                    $response = Invoke-RestMethod @splatImportGroupParams
                    Write-Information "Canvas [$($resource."$correlationField")] resource created through SIS-import with id [$($response.id)] and state $($response.workflow_state)"                    
                }
                else {
                    Write-Information "[DryRun] Create Canvas [$($resource."$correlationField")] resource, will be executed during enforcement"
                }

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'CreateResource'
                        Message = "Created Canvas resource: [$($resource."$correlationField")]"
                        IsError = $false
                    })            
            }
            catch {
                $outputContext.Success = $false
                $ex = $PSItem
                if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                    $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                    $errorObj = Resolve-CanvasError -ErrorObject $ex
                    $auditLogMessage = "Could not create Canvas resource. Error: $($errorObj.FriendlyMessage)"
                    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
                }
                else {
                    $auditLogMessage = "Could not create Canvas resource. Error: $($ex.Exception.Message)"
                    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
                }
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = $auditLogMessage
                        IsError = $true
                    })
            }                
        }
    }
    else {
        $outputContext.Success = $true
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = 'CreateResource'
                Message = "No groups to be created [$($resourceContext.SourceData.Count)]. All groups are found in existing Canvas groups [$($existingGroups.Count)]"
                IsError = $false
            })  
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CanvasError -ErrorObject $ex
        $auditLogMessage = "Could not create Canvas resource. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create Canvas resource. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}