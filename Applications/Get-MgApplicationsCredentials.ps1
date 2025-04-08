<#
Version History:

## [1.2] - 2025-04-04
### Changed
- Format output for Owners property

## [1.1] - 2025-02-26
### Changed
- Transform the script into a function
- Add `ForceNewToken` parameter
- Test if already connected to Microsoft Graph and with the right permissions

## [1.0] - 2024-xx-xx
### Initial Release
#>

function Get-MgApplicationsCredentials {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$ForceNewToken
    )

    try {
        # for Get-MgApplication/Get-MgApplicationOwner
        Import-Module 'Microsoft.Graph.Applications' -ErrorAction Stop -ErrorVariable mgGraphAppsMissing
    }
    catch {
        if ($mgGraphAppsMissing) {
            Write-Warning "Failed to import Microsoft.Graph.Applications module: $($mgGraphAppsMissing.Exception.Message)"
        }
        if ($mgGraphIdentitySignInsMissing) {
            Write-Warning "Failed to import Microsoft.Graph.Identity.SignIns module: $($mgGraphIdentitySignInsMissing.Exception.Message)"
        }
        return
    }

    $isConnected = $false

    $isConnected = $null -ne (Get-MgContext -ErrorAction SilentlyContinue)
    
    if ($ForceNewToken.IsPresent) {
        Write-Verbose 'Disconnecting from Microsoft Graph'
        $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
        $isConnected = $false
    }
    
    $scopes = (Get-MgContext).Scopes

    $permissionsNeeded = 'Application.Read.All'
    $permissionMissing = $permissionsNeeded -notin $scopes

    if ($permissionMissing) {
        Write-Verbose "You need to have the $permissionsNeeded permission in the current token, disconnect to force getting a new token with the right permissions"
    }

    if (-not $isConnected) {
        Write-Verbose "Connecting to Microsoft Graph. Scopes: $permissionsNeeded"
        $null = Connect-MgGraph -Scopes $permissionsNeeded -NoWelcome
    }

    [System.Collections.Generic.List[PSObject]]$credentialsArray = @()

    $mgApps = Get-MgApplication -All

    foreach ($mgApp in $mgApps) {
        $owner = Get-MgApplicationOwner -ApplicationId $mgApp.Id

        # if severral owners, join them with '|'

        foreach ($keyCredential in $mgApp.KeyCredentials) {
            $object = [PSCustomObject][ordered]@{
                DisplayName           = $mgApp.DisplayName
                CredentialType        = 'KeyCredentials'
                AppId                 = $mgApp.AppId
                CredentialDescription = $keyCredential.DisplayName
                CredentialStartDate   = $keyCredential.StartDateTime
                CredentialExpiryDate  = $keyCredential.EndDateTime
                # CredentialExpiryDate is date time, compared to now and see it is valid
                CredentialValid       = $keyCredential.EndDateTime -gt (Get-Date)
                Type                  = $keyCredential.Type
                Usage                 = $keyCredential.Usage
                Owners                = $owner.AdditionalProperties.userPrincipalName -join '|'
            }

            $credentialsArray.Add($object)
        }

        foreach ($passwordCredential in $mgApp.PasswordCredentials) {
            $object = [PSCustomObject][ordered]@{
                DisplayName           = $mgApp.DisplayName
                CredentialType        = 'PasswordCredentials'
                AppId                 = $mgApp.AppId
                CredentialDescription = $passwordCredential.DisplayName
                CredentialStartDate   = $passwordCredential.StartDateTime
                CredentialExpiryDate  = $passwordCredential.EndDateTime
                # CredentialExpiryDate is date time, compared to now and see it is valid
                CredentialValid       = $passwordCredential.EndDateTime -gt (Get-Date)
                Type                  = 'NA'
                Usage                 = 'NA'
                Owners                = $owner.AdditionalProperties.userPrincipalName -join '|'
            }

            $credentialsArray.Add($object)
        }
    }

    return $credentialsArray
}