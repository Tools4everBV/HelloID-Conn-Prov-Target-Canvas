#####################################################
# HelloID-Conn-Prov-Target-Canvas-Update
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$pp = $previousPerson | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    'user[name]'          = "$($p.Name.GivenName) $($p.Name.FamilyName)"
    'user[short_name]'    = $p.DisplayName
    'user[sortable_name]' = ""
    'user[email]'         = $p.Accounts.MicrosoftActiveDirectory.mail
}

$previousAccount = [PSCustomObject]@{
    'user[name]'          = "$($pp.Name.GivenName) $($pp.Name.FamilyName)"
    'user[short_name]'    = $pp.DisplayName
    'user[sortable_name]' = ""
    'user[email]'         = $pp.Accounts.MicrosoftActiveDirectory.mail
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
    # Verify if the account must be updated
    $splatCompareProperties = @{
        ReferenceObject  = @($previousAccount.PSObject.Properties)
        DifferenceObject = @($account.PSObject.Properties)
    }
    $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({$_.SideIndicator -eq '=>'})
    if ($propertiesChanged) {
        $action = 'Update'
    } else {
        $action = 'NoChanges'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Update Canvas account for: [$($p.DisplayName)] will be executed during enforcement"
            })
    }

    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Update' {
                Write-Verbose "Updating Canvas account with accountReference: [$aRef]"
                $splatParams = @{
                    Uri     = "$($config.BaseUrl)/api/v1/accounts/$($config.AccountId)/users"
                    Method  = 'PUT'
                    Headers = $headers
                    Body    = $account | ConvertTo-Json
                }
                $null = Invoke-RestMethod @splatParams -Verbose:$false
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to Canvas account with accountReference: [$aRef]"
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = 'Update account was successful'
                IsError = $false
            })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not update Canvas account. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not update Canvas account. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
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
