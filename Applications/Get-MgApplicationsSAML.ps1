# article : https://itpro-tips.com/get-azure-ad-saml-certificate-details/
# the information about the SAML applications clams is not available in the Microsoft Graph API v1 but in https://main.iam.ad.ext.azure.com/api/ApplicationSso/<service-principal-id>/FederatedSsoV2 so we don't get them
<#
Version History:

## [1.2] - 2025-04-04
### Changed
- Change Write-Warning message in the catch block to Import-Module

## [1.1] - 2025-02-26
### Changed
- Transform the script into a function
- Add `ForceNewToken` parameter
- Test if already connected to Microsoft Graph and with the right permissions

## [1.0] - 2024-xx-xx
### Initial Release
#>

function Get-MgApplicationsSAML {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$ForceNewToken
    )
    
    try {
        # At the date of writing (december 2023), PreferredTokenSigningKeyEndDateTime parameter is only on Beta profile
        Import-Module 'Microsoft.Graph.Beta.Applications' -ErrorAction Stop -ErrorVariable mgGraphAppsMissing
    }
    catch {
        if ($mgGraphAppsMissing) {
            Write-Warning "Please install the Microsoft.Graph.Beta.Applications module: $($mgGraphAppsMissing.Exception.Message)"
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
    
    [System.Collections.Generic.List[PSObject]]$samlApplicationsArray = @()
    $samlApplications = Get-MgBetaServicePrincipal -Filter "PreferredSingleSignOnMode eq 'saml'"

    foreach ($samlApp in $samlApplications) {
        $object = [PSCustomObject][ordered]@{
            DisplayName                         = $samlApp.DisplayName
            Id                                  = $samlApp.Id
            AppId                               = $samlApp.AppId
            LoginUrl                            = $samlApp.LoginUrl
            LogoutUrl                           = $samlApp.LogoutUrl
            NotificationEmailAddresses          = $samlApp.NotificationEmailAddresses -join '|'
            AppRoleAssignmentRequired           = $samlApp.AppRoleAssignmentRequired
            PreferredSingleSignOnMode           = $samlApp.PreferredSingleSignOnMode
            PreferredTokenSigningKeyEndDateTime = $samlApp.PreferredTokenSigningKeyEndDateTime
            # PreferredTokenSigningKeyEndDateTime is date time, compared to now and see it is valid
            PreferredTokenSigningKeyValid       = $samlApp.PreferredTokenSigningKeyEndDateTime -gt (Get-Date)
            ReplyUrls                           = $samlApp.ReplyUrls -join '|'
            SignInAudience                      = $samlApp.SignInAudience
        }

        $samlApplicationsArray.Add($object)
    }

    return $samlApplicationsArray
}