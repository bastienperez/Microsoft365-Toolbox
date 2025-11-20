<#
.SYNOPSIS
    Retrieves and processes user password information from Microsoft Graph and get information about the user's password, such as the last password change date, on-premises sync status, and password policies.

.DESCRIPTION
    The Get-MgUserPasswordInfo script collects details such as the user's principal name, last password change date, on-premises sync status, and password policies.

.PARAMETER UserPrincipalName
    Specifies the user principal name(s) of the user(s) for which to retrieve password information.
    
.PARAMETER PasswordPoliciesByDomainOnly
    If specified, retrieves password policies for domains only, without retrieving individual user information.

.EXAMPLE
    Get-MgUserPasswordInfo
    Retrieves password information for all users and outputs it (default behavior).

.EXAMPLE
    Get-MgUserPasswordInfo -UserPrincipalName xxx@domain.com
    Retrieves password information for the specified user and outputs it.

.EXAMPLE
    Get-MgUserPasswordInfo -PasswordPoliciesByDomainOnly
    Retrieves password policies for all domains only.

.OUTPUTS
    PSCustomObject
        The script returns an array of custom PowerShell objects containing the following properties for each user:
        - UserPrincipalName: The user's principal name.
        - LastPasswordChangeDateTimeUTC: The last date and time the user's password was changed.
        - OnPremisesLastSyncDateTimeUTC: The last date and time the user's on-premises directory was synchronized.
        - OnPremisesSyncEnabled: Indicates whether on-premises synchronization is enabled for the user.
        - ForceChangePasswordNextSignIn: Indicates whether the user is required to change their password at the next sign-in.
        - ForceChangePasswordNextSignInWithMfa: Indicates whether the user is required to change their password at the next sign-in with multi-factor authentication.
        - PasswordPolicies: The user's password policies. Can be : Empty, 'None' or 'DisablePasswordExpiration' (the last one is especially for synced users).
        - PasswordNotificationWindowInDays: The number of days before the password expires that the user is notified.
        - PasswordValidityPeriodInDays: The number of days before the password expires.

.NOTES
    Ensure you have the necessary permissions and modules installed to run this script, such as the Microsoft Graph PowerShell module.
    The script assumes that the necessary authentication to Microsoft Graph has already been handled with the Connect-MgGraph function.
    Connect-MgGraph -Scopes 'User.Read.All', 'Domain.Read.All'
#>

function Get-MgUserPasswordInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$UserPrincipalName,
        [Parameter(Mandatory = $false)]
        [switch]$PasswordPoliciesByDomainOnly,
        [Parameter(Mandatory = $false)]
        [string]$ByDomain
    )
    
    # Import required modules
    $modules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Identity.DirectoryManagement'
    )
    
    foreach ($module in $modules) {
        try {
            $null = Import-Module $module -ErrorAction Stop
        }
        catch {
            Write-Warning "Please install $module first"
            return
        }							   
    }

    function Get-DomainPasswordPolicies {
        Write-Host -ForegroundColor Cyan 'Retrieving password policies for all domains'
        $domains = Get-MgDomain -All
        $domainPasswordPolicies = [System.Collections.Generic.List[PSObject]]$domainPasswordPolicies = @()

        foreach ($domain in $domains) {
	
            $validityPeriod = if ($domain.PasswordValidityPeriodInDays -eq '2147483647') { 
                '2147483647 (Password never expire)' 
            }
            else { 
                $domain.PasswordValidityPeriodInDays 
            }
            
            $object = [PSCustomObject][ordered]@{
                DomainName                       = $domain.ID
                AuthenticationType               = $domain.AuthenticationType
                PasswordValidityPeriod           = $validityPeriod
                PasswordValidityInheritedFrom    = $null
                PasswordNotificationWindowInDays = $domain.PasswordNotificationWindowInDays
            }

            $domainPasswordPolicies.Add($object)
        }		   

        # Inherit password policies
        foreach ($domain in $domainPasswordPolicies) {
            $found = $false
            
            foreach ($policy in $domainPasswordPolicies) {
                if ($domain.DomainName.EndsWith($policy.DomainName) -and $domain.DomainName -ne $policy.DomainName -and -not $found) {
                    $domain.PasswordNotificationWindowInDays = $policy.PasswordNotificationWindowInDays
                    $domain.PasswordValidityPeriod = $policy.PasswordValidityPeriod
                    $domain.PasswordValidityInheritedFrom = "$($policy.DomainName) domain"

                    $found = $true
                }
            }
        }
        return $domainPasswordPolicies
    }

    # Retrieve domain password policies
    $domainPasswordPolicies = Get-DomainPasswordPolicies

    if ($PasswordPoliciesByDomainOnly) {
        Write-Host -ForegroundColor Cyan "Note that if you have some federated domains, they don't have password policies because authentication is handled by another IDP (Identity Provider)"

        return $domainPasswordPolicies
    }

    $userParams = 'UserPrincipalName, LastPasswordChangeDateTime, OnPremisesLastSyncDateTime, OnPremisesSyncEnabled, PasswordProfile, PasswordPolicies, AccountEnabled, DisplayName'
    # Retrieve user password information
    if ($UserPrincipalName) {
        Write-Host -ForegroundColor Cyan "Retrieving password information for $($UserPrincipalName.Count) user(s)"
        [System.Collections.Generic.List[PSObject]]$usersList = @()
        foreach ($upn in $UserPrincipalName) {												 
            $user = Get-MgUser -UserId $upn -Property $userParams

            $usersList.Add($user)
        }
    }
    elseif($ByDomain) {
        Write-Host -ForegroundColor Cyan "Retrieving password information for users in domain: $ByDomain (exluding guest users #EXT#@$ByDomain)"

        $usersList = Get-MgUser -Filter "endswith(userPrincipalName,'$ByDomain') and not endswith(userPrincipalName,'#EXT#@$ByDomain')" -All -ConsistencyLevel eventual

    }
    else {
        Write-Host -ForegroundColor Cyan 'Retrieving password information for all users'
        $usersList = Get-MgUser -All -Property $userParams
    }

    [System.Collections.Generic.List[PSObject]]$passwordsInfoArray = @()

    foreach ($user in $usersList) {
        $userDomain = $user.UserPrincipalName.Split('@')[1]
        $userDomainPolicy = $domainPasswordPolicies | Where-Object { $_.DomainName -eq $userDomain }

        $passwordExpired = $false 

        if ($user.PasswordPolicies -eq 'DisablePasswordExpiration') {
            $userDomainPolicy.PasswordValidityPeriod = '2147483647 (Password never expire)'
            $userDomainPolicy.PasswordValidityInheritedFrom = 'User password policy'
        }

        if ($userDomainPolicy.PasswordValidityPeriod -ne '2147483647 (Password never expire)') {

            if ($user.LastPasswordChangeDateTime -lt (Get-Date).AddDays(-$userDomainPolicy.PasswordValidityPeriod)) { 
                $passwordExpired = $true 
            }
        }

        if ($userDomainPolicy.PasswordValidityPeriod -ne '2147483647 (Password never expire)') {
            $daysLeft = ($user.LastPasswordChangeDateTime.AddDays($userDomainPolicy.PasswordValidityPeriod) - (Get-Date)).Days
            if ($daysLeft -lt 0) {
                $daysLeft = 'Already expired'
            }
            else {
                $daysLeft = $daysLeft
            }
        }
        else {
            $daysLeft = 'Password never expires'
        }

        $object = [PSCustomObject][ordered]@{
            UserPrincipalName                    = $user.UserPrincipalName
            DisplayName                          = $user.DisplayName
            Enabled                              = $user.AccountEnabled
            PasswordPolicies                     = $user.PasswordPolicies
            PasswordLastSetUTCTime               = $user.LastPasswordChangeDateTime
            PasswordPolicyMaxPasswordAgeInDays   = $userDomainPolicy.PasswordValidityPeriod
            PasswordExpirationDateUTC            = if ($userDomainPolicy.PasswordValidityPeriod -ne '2147483647 (Password never expire)') { $user.LastPasswordChangeDateTime.AddDays($userDomainPolicy.PasswordValidityPeriod) }else {}
            DaysLeftBeforePasswordChangeUTC      = $daysLeft
            OnPremisesLastSyncDateTimeUTC        = $user.OnPremisesLastSyncDateTime
            ForceChangePasswordNextSignIn        = $user.PasswordProfile.ForceChangePasswordNextSignIn
            ForceChangePasswordNextSignInWithMfa = $user.PasswordProfile.ForceChangePasswordNextSignInWithMfa
            OnPremisesSyncEnabled                = $user.OnPremisesSyncEnabled
            Domain                               = $userDomain
            PasswordValidityInheritedFrom        = $userDomainPolicy.PasswordValidityInheritedFrom
            PasswordNotificationWindowInDays     = $userDomainPolicy.PasswordNotificationWindowInDays
            PasswordExpired                      = $passwordExpired
        }
    
        $passwordsInfoArray.Add($object)
    }

    return $passwordsInfoArray
}