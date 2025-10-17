<#
.SYNOPSIS
Get-MgRoleReport.ps1 - Reports on Microsoft Entra ID (Azure AD) roles

.DESCRIPTION 
By default, the report contains only the roles with members.
To get all the role, included empty roles, add -IncludeEmptyRoles $true

.OUTPUTS
The report is output to an array contained all the audit logs found.
To export in a csv, do Get-MgRoleReport | Export-CSV -NoTypeInformation "$(Get-Date -Format yyyyMMdd)_adminRoles.csv" -Encoding UTF8

.PARAMETER IncludeEmptyRoles
Switch parameter to include empty roles in the report

.PARAMETER IncludePIMEligibleAssignments
Boolean parameter to include PIM eligible assignments in the report. Default is $true

.PARAMETER ForceNewToken
Switch parameter to force getting a new token from Microsoft Graph

.PARAMETER MaesterMode
Switch parameter to use with the Maester framework (internal process not presented here)

.EXAMPLE
Get-MgRoleReport

Get all the roles with members, including PIM eligible assignments but without empty roles

.EXAMPLE
Get-MgRoleReport -IncludeEmptyRoles

Get all the roles, including the ones without members

.EXAMPLE
Get-MgRoleReport -IncludePIMEligibleAssignments $false
Get all the roles with members (without empty roles), but without PIM eligible assignments

.EXAMPLE
Get-MgRoleReport | Export-CSV -NoTypeInformation "$(Get-Date -Format yyyyMMdd)_adminRoles.csv" -Encoding UTF8

.LINK
https://itpro-tips.com/get-the-office-365-admin-roles-and-track-the-changes/

.NOTES
Written by Bastien Perez (Clidsys.com - ITPro-Tips.com)
For more Office 365/Microsoft 365 tips and news, check out ITPro-Tips.com.

Version History:
## [1.8.2] - 2025-10-17
### Changed
- Fix `onPremisesSyncEnabled` property

## [1.8.1] - 2025-10-17
### Added
- Add `RecommendationSync` property

## [1.8.0] - 2025-10-08
### Added
- Add `IncludeEmptyRoles` switch parameter to get all roles, even the ones without members

### Changed
- Use List for mgRoles for better performance

## [1.7.0] - 2025-04-04
### Changed
- Add scopes for `RoleManagement.Read.All` and `AuditLog.Read.All` permissions

## [1.6] - 2025-02-26
### Changed
- Add `permissionsNeeded` variable
- Add `onpremisesSyncEnabled` property for groups
- Add all type objects in the cache array
- Add `LastNonInteractiveSignInDateTime` property for users

## [1.5.0] - 2025-02-25
### Changed
- Always return `true` or `false` for `onPremisesSyncEnabled` properties
- Fix issues with `objectsCacheArray` that was not working
- Sign-in activity tracking for service principals

### Plannned for next release
- Switch to `Invoke-MgGraphRequest` instead of `Get-Mg*` CMDlets

## [1.4.0] - 2025-02-13
### Added
- Sign-in activity tracking for users
- Account enabled status.
- On-premises sync enabled status.
- Remove old parameters
- Test if already connected to Microsoft Graph and with the right permissions

## [1.3.0] - 2024-05-15
### Changed
- Changes not specified.

## [1.2.0] - 2024-03-13
### Changed
- Changes not specified.

## [1.1.0] - 2023-12-01
### Changed
- Changes not specified.

## [1.0.0] - 2023-10-19
### Initial Release

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
DEALINGS IN THE SOFTWARE.

#>
function Get-MgRoleReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$IncludeEmptyRoles = $false,
        [Parameter(Mandatory = $false)]
        [boolean]$IncludePIMEligibleAssignments = $true,
        [Parameter(Mandatory = $false)]
        [switch]$ForceNewToken,
        # using with the Maester framework
        [Parameter(Mandatory = $false)]
        [switch]$MaesterMode        
    )

    [System.Collections.Generic.List[PSObject]]$rolesMembersArray = @()
    [System.Collections.Generic.List[Object]]$objectsCacheArray = @()
    [System.Collections.Generic.List[Object]]$mgRolesArrayAssignment = @()

    $modules = @(
        'Microsoft.Graph.Authentication'
        'Microsoft.Graph.Identity.Governance'
        'Microsoft.Graph.Users'
        'Microsoft.Graph.Groups'
        'Microsoft.Graph.Beta.Reports'
    )
    
    foreach ($module in $modules) {
        try {
            Import-Module $module -ErrorAction Stop 
        }
        catch {
            Write-Warning "First, install module $module"
            return
        }
    }

    $isConnected = $false

    $isConnected = $null -ne (Get-MgContext -ErrorAction SilentlyContinue)
    
    if ($ForceNewToken.IsPresent) {
        Write-Verbose 'Disconnecting from Microsoft Graph'
        $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
        $isConnected = $false
    }
    
    $scopes = (Get-MgContext).Scopes

    # Audit.Log.Read.All for sign-in activity
    # RoleManagement.Read.All for role assignment (PIM eligible and permanent)
    # Directory.Read.All for user and group and service principal information
    $permissionsNeeded = 'Directory.Read.All', 'RoleManagement.Read.All', 'AuditLog.Read.All'
    foreach ($permission in $permissionsNeeded) {
        if ($scopes -notcontains $permission) {
            Write-Verbose "You need to have the $permission permission in the current token, disconnect to force getting a new token with the right permissions"
        }
    }

    if (-not $isConnected) {
        Write-Verbose "Connecting to Microsoft Graph. Scopes: $permissionsNeeded"
        $null = Connect-MgGraph -Scopes $permissionsNeeded -NoWelcome
    }

    Write-Verbose 'Collecting  roles with assignments...'

    try {
        #$mgRolesArrayAssignment = Get-MgRoleManagementDirectoryRoleDefinition -ErrorAction Stop
        
        Get-MgRoleManagementDirectoryRoleAssignment -All -ExpandProperty Principal | ForEach-Object {
            $mgRolesArrayAssignment.Add($_)
        }

        #$mgRolesArrayAssignment = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' -OutputType PSObject).Value

        $mgRolesDefinition = Get-MgRoleManagementDirectoryRoleAssignment -All -ExpandProperty roleDefinition

    }
    catch {
        Write-Warning $($_.Exception.Message)
    }

    # In *Assignment, we don't have the role definition, so we need to get it and add it to the object
    foreach ($assignment in $mgRolesArrayAssignment) {
        # Add the role definition to the object
        Add-Member -InputObject $assignment -MemberType NoteProperty -Name RoleDefinitionExtended -Value ($mgRolesDefinition | Where-Object { $_.id -eq $assignment.id }).roleDefinition 
        # Add-Member -InputObject $assignment -MemberType NoteProperty -Name RoleDefinitionExtended -Value ($mgRolesDefinition | Where-Object { $_.id -eq $assignment.id }).roleDefinition.description 
    } 
    

    if ($IncludePIMEligibleAssignments) {
        Write-Verbose 'Collecting PIM eligible role assignments...'
        try {
            (Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All -ExpandProperty * -ErrorAction Stop | Select-Object id, principalId, directoryScopeId, roleDefinitionId, status, principal, @{Name = 'RoleDefinitionExtended'; Expression = { $_.roleDefinition } }) | ForEach-Object {
                $mgRolesArrayAssignment.Add($_)
            }
            #$mgRoles += (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilitySchedule' -OutputType PSObject).Value
        }
        catch {
            Write-Warning "Unable to get PIM eligible role assignments: $($_.Exception.Message)"
        }
    }

    foreach ($assignment in $mgRolesArrayAssignment) {    
        $principal = switch ($assignment.principal.AdditionalProperties.'@odata.type') {
            '#microsoft.graph.user' { $assignment.principal.AdditionalProperties.userPrincipalName; break }
            '#microsoft.graph.servicePrincipal' { $assignment.principal.AdditionalProperties.appId; break }
            '#microsoft.graph.group' { $assignment.principalid; break }
            'default' { '-' }
        }

        $object = [PSCustomObject][ordered]@{    
            Principal            = $principal
            PrincipalDisplayName = $assignment.principal.AdditionalProperties.displayName
            PrincipalType        = $assignment.principal.AdditionalProperties.'@odata.type'.Split('.')[-1]
            PrincipalObjectID    = $assignment.principal.id
            AssignedRole         = $assignment.RoleDefinitionExtended.displayName
            AssignedRoleDefinitionId = $assignment.RoleDefinitionId
            AssignedRoleScope    = $assignment.directoryScopeId
            AssignmentType       = if ($assignment.status -eq 'Provisioned') { 'Eligible' } else { 'Permanent' }
            RoleIsBuiltIn        = $assignment.RoleDefinitionExtended.isBuiltIn
            RoleTemplate         = $assignment.RoleDefinitionExtended.templateId
            DirectMember         = $true
            Recommendations      = 'Check if the user has alternate email or alternate phone number on Microsoft Entra ID'
            RecommendationSync   = $null
        }

        $rolesMembersArray.Add($object)

        if ($object.PrincipalType -eq 'group') {
            # need to get ID for Get-MgGroupMember
            $group = Get-MgGroup -GroupId $object.Principal -Property Id, onPremisesSyncEnabled
            $object | Add-Member -MemberType NoteProperty -Name 'OnPremisesSyncEnabled' -Value $([bool]($group.onPremisesSyncEnabled -eq $true))

            #$group = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($object.Principal)" -OutputType PSObject)

            $groupMembers = Get-MgGroupMember -GroupId $group.Id -Property displayName, userPrincipalName
            #$groupMembers = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($group.Id)/members" -OutputType PSObject).Value

            foreach ($member in $groupMembers) {
                $typeMapping = @{
                    '#microsoft.graph.user'             = 'user'
                    '#microsoft.graph.group'            = 'group'
                    '#microsoft.graph.servicePrincipal' = 'servicePrincipal'
                    '#microsoft.graph.device'           = 'device'
                    '#microsoft.graph.orgContact'       = 'contact'
                    '#microsoft.graph.application'      = 'application'
                }

                $memberType = if ($typeMapping[$member.AdditionalProperties.'@odata.type']) {
                    $typeMapping[$member.AdditionalProperties.'@odata.type']
                }
                else {
                    'Unknown'
                }

                $object = [PSCustomObject][ordered]@{
                    Principal            = $member.AdditionalProperties.userPrincipalName
                    PrincipalDisplayName = $member.AdditionalProperties.displayName
                    PrincipalType        = $memberType
                    AssignedRole         = $assignment.RoleDefinitionExtended.displayName
                    AssignedRoleScope    = $assignment.directoryScopeId
                    AssignmentType       = if ($assignment.status -eq 'Provisioned') { 'Eligible' } else { 'Permanent' }
                    RoleIsBuiltIn        = $assignment.RoleDefinitionExtended.isBuiltIn
                    RoleTemplate         = $assignment.RoleDefinitionExtended.templateId
                    DirectMember         = $false
                    Recommendations      = 'Check if the user has alternate email or alternate phone number on Microsoft Entra ID'
                    RecommendationSync  = $null
                }

                $rolesMembersArray.Add($object)
            }
        }
    }

    $object = [PSCustomObject] [ordered]@{
        Principal            = 'Partners'
        PrincipalDisplayName = 'Partners'
        PrincipalType        = 'Partners'
        AssignedRole         = 'Partners'
        AssignedRoleScope    = 'Partners'
        AssignmentType       = 'Partners'
        RoleIsBuiltIn        = 'Not applicable'
        RoleTemplate         = 'Not applicable'
        DirectMember         = 'Not applicable'
        Recommendations      = 'Please check this URL to identify if you have partner with admin roles https: / / admin.microsoft.com / AdminPortal / Home#/partners. More information on https://practical365.com/identifying-potential-unwanted-access-by-your-msp-csp-reseller/'
        RecommendationSync  = $null
    }    
    
    $rolesMembersArray.Add($object)

    #foreach user, we check if the user is global administrator. If global administrator, we add a new parameter to the object recommandationRole to tell the other role is not useful
    $globalAdminsHash = @{}
    $rolesMembersArray | Where-Object { $_.AssignedRole -eq 'Global Administrator' } | ForEach-Object {
        $globalAdminsHash[$_.Principal] = $true
    }

    $rolesMembersArray | ForEach-Object {
        if ($globalAdminsHash.ContainsKey($_.Principal) -and $_.AssignedRole -ne 'Global Administrator') {
            $_ | Add-Member -MemberType NoteProperty -Name 'RecommandationRole' -Value 'This user is Global Administrator. The other role(s) is/are not useful'
        }
        else {
            $_ | Add-Member -MemberType NoteProperty -Name 'RecommandationRole' -Value ''
        }
    }

    foreach ($member in $rolesMembersArray) {
        Write-Verbose "Processing $($member.AssignedRole) - $($member.AssignedRole)"

        $lastSignInDateTime = $null
        $accountEnabled = $null
        $onPremisesSyncEnabled = $null
        
        if ($objectsCacheArray.Principal -contains $member.Principal) {
            $accountEnabled = ($objectsCacheArray | Where-Object { $_.Principal -eq $member.Principal }).AccountEnabled
            $lastSignInDateTime = ($objectsCacheArray | Where-Object { $_.Principal -eq $member.Principal }).LastSignInDateTime
            $lastNonInteractiveSignInDateTime = ($objectsCacheArray | Where-Object { $_.Principal -eq $member.Principal }).LastNonInteractiveSignInDateTime
            $onPremisesSyncEnabled = ($objectsCacheArray | Where-Object { $_.Principal -eq $member.Principal }).onPremisesSyncEnabled
        }
        else {
            $lastSignInActivity = $null

            switch ($member.PrincipalType) {
                'user' {
                    # If we use Get-MgUser -UserId $member.Principal -Property AccountEnabled, SignInActivity, onPremisesSyncEnabled, 
                    # we encounter the error 'Get-MgUser_Get: Get By Key only supports UserId, and the key must be a valid GUID'.
                    # This is because the sign-in data comes from a different source that requires a GUID to retrieve the account's sign-in activity. 
                    # Therefore, we must provide the account's object identifier for the command to function correctly.
                    # To overcome this issue, we use the -Filter parameter to search for the user by their UserPrincipalName.
                    $mgUser = Get-MgUser -Filter "UserPrincipalName eq '$($member.Principal)'" -Property AccountEnabled, SignInActivity, onPremisesSyncEnabled
                    $accountEnabled = $mgUser.AccountEnabled
                    $lastSignInDateTime = $mgUser.signInActivity.LastSignInDateTime
                    $lastNonInteractiveSignInDateTime = $mgUser.signInActivity.LastNonInteractiveSignInDateTime
                    $onPremisesSyncEnabled = [bool]($mgUser.onPremisesSyncEnabled -eq $true)
                    
                    break
                }

                'group' {
                    $accountEnabled = 'Not applicable'
                    $lastSignInDateTime = 'Not applicable'
                    $lastNonInteractiveSignInDateTime = 'Not applicable'
                    # onpremisesSyncEnabled already get from Get-MgGroup in the previous loop
                    $onPremisesSyncEnabled = $member.OnPremisesSyncEnabled

                    break
                }

                'servicePrincipal' {
                    $lastSignInActivity = (Get-MgBetaReportServicePrincipalSignInActivity -Filter "appId eq '$($member.Principal)'").LastSignInActivity
                    $accountEnabled = 'Not applicable'
                    $lastSignInDateTime = $lastSignInActivity.LastSignInDateTime
                    $lastNonInteractiveSignInDateTime = $lastSignInActivity.LastNonInteractiveSignInDateTime
                    $onPremisesSyncEnabled = $false
                    
                    break
                }
                
                'Partners' {
                    $accountEnabled = 'Not applicable'
                    $lastSignInDateTime = 'Not applicable'
                    $lastNonInteractiveSignInDateTime = 'Not applicable'
                    $onPremisesSyncEnabled = 'Not applicable'

                    break
                }

                'default' {
                    $accountEnabled = 'Not applicable'
                    $lastSignInDateTime = 'Not applicable'
                    $lastNonInteractiveSignInDateTime = 'Not applicable'
                    $onPremisesSyncEnabled = 'Not applicable'

                }
            }
        }

        $member | Add-Member -MemberType NoteProperty -Name 'LastSignInDateTime' -Value $lastSignInDateTime
        $member | Add-Member -MemberType NoteProperty -Name 'LastNonInteractiveSignInDateTime' -Value $lastNonInteractiveSignInDateTime
        $member | Add-Member -MemberType NoteProperty -Name 'AccountEnabled' -Value $accountEnabled
        $member | Add-Member -MemberType NoteProperty -Name 'OnPremisesSyncEnabled' -Value $onPremisesSyncEnabled

        if($onPremisesSyncEnabled) {
            $member.RecommendationSync = 'Privileged accounts should be cloud-only.'
        }

        # only add if not already in the cache
        if (-not $objectsCacheArray.Principal -contains $member.Principal) {
            $objectsCacheArray.Add($member)
        }
    }
    
    if ($IncludeEmptyRoles.IsPresent) {

        Write-Verbose 'Collecting all roles...'
        try {
            #$mgRolesArrayAssignment = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions' -OutputType PSObject).Value
            $mgRolesDefinition = Get-MgRoleManagementDirectoryRoleDefinition -All -ErrorAction Stop

            $emptyRoles = $mgRolesDefinition | Where-Object { $mgRolesArrayAssignment.RoleDefinitionId -notcontains $_.id }

            foreach ($emptyRole in $emptyRoles) {
                $object = [PSCustomObject][ordered]@{    
                    Principal                        = 'Role has no members'
                    PrincipalDisplayName             = $null
                    PrincipalType                    = $null
                    PrincipalObjectID                = $null
                    AssignedRole                     = $emptyRole.displayName
                    AssignedRoleScope                = $null
                    AssignmentType                   = $null
                    RoleIsBuiltIn                    = $emptyRole.isBuiltIn
                    RoleTemplate                     = $emptyRole.templateId
                    DirectMember                     = $null
                    Recommendations                  = $null
                    LastSignInDateTime               = $null
                    LastNonInteractiveSignInDateTime = $null
                    AccountEnabled                   = $null
                    OnPremisesSyncEnabled            = $null
                    RecommandationRole               = $null
                }

                $rolesMembersArray.Add($object)
            }
        }
        catch {
            Write-Warning $($_.Exception.Message)   
        }   

    }
    return $rolesMembersArray
}