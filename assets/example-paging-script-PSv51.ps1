####################################################################
# HelloID-Conn-Prov-Target-Canvas-ImportPermissions-Group
# PowerShell V2
# Example script how to handle pagination when using the onpremise HelloID agent (powershell 5.1).
####################################################################

Write-Information 'Starting Canvas account entitlement import'
    
$headers = [System.Collections.Generic.Dictionary[string, string]]::new()
$headers.Add('Authorization', "Bearer $($Actioncontext.Configuration.access_token)")
$headers.Add('Accept', 'application/Json')
$headers.Add('Content-Type', 'application/Json')

   
# # Example to replace the placeholder code with:
$pageSize = 100    
   
$currentUrl = "$($Actioncontext.configuration.BaseUrl)/api/v1/accounts/$($Actioncontext.configuration.AccountId)/users?per_page=$pageSize"
$pageCount = 0
$userCount = 0
    
while ($currentUrl) {
    $pageCount++
    Write-Verbose "Fetching page $pageCount from: $currentUrl"

    $splatImportAccountParams = @{
        Uri     = $currentUrl
        Method  = 'GET'
        Headers = $headers
    }

    $response = Invoke-WebRequest @splatImportAccountParams

    # Parse the JSON response
    $users = $response.Content | ConvertFrom-Json 
        
    # Add users to collection
    if ($users -and $users.Count -gt 0) {
        $userCount += $users.Count

        foreach ($importedAccount in $users) {            
            $splatUserAccountParams = @{
                Uri     = "$($Actioncontext.configuration.BaseUrl)/api/v1/users/$($importedAccount.id)"
                Method  = 'GET'
                Headers = $headers
            }
            $userAccount = Invoke-RestMethod @splatUserAccountParams

            ##Do something with the user account, for example, output it to HelloID
            Write-Information "Retrieved user account: $($userAccount.name) with ID: $($userAccount.id)"
        }
    }
    else {
        Write-Information "No users returned on page $pageCount"
    }
        
    # Parse the Link header for the next page
    $currentUrl = $null
    if ($response.Headers.ContainsKey('Link')) {
        $linkHeader = $response.Headers['Link']
            
        # Handle both string and array responses for Link header
        if ($linkHeader -is [array]) {
            $linkHeader = $linkHeader -join ','
        }
            
        # Parse the Link header to find the 'next' rel
        $links = $linkHeader -split ','
        foreach ($link in $links) {
            if ($link -match '<([^>]+)>\s*;\s*rel="next"') {
                $currentUrl = $Matches[1]
                Write-Verbose "Next page URL found: $currentUrl"
                break
            }
        }
    }
        
    if (-not $currentUrl) {
        Write-Information "No more pages to retrieve. Completed pagination."
        Write-Information "Retrieved $($users.Count) users from page $pageCount (Total: $($userCount))"    
    }
}