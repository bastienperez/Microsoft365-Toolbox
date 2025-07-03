<#
# TODO: add MFA state
.SYNOPSIS
Get-ExchangeRoleReport - Reports on Exchange RBAC roles and permissions.

.DESCRIPTION 
This script produces a report of the membership of Exchange RBAC role groups.
By default, the report contains only the groups with members.

.OUTPUTS
The report is output to an array contained all the audit logs found.
To export in a csv, do Get-ExchangeRoleReport | Export-CSV -NoTypeInformation "$(Get-Date -Format yyyyMMdd)_adminRoles.csv" -Encoding UTF8

.EXAMPLE
Get-RBACReport


.LINK


.NOTES
Written by Bastien Perez (ITPro-Tips.com)

Version history:
V1.0, 14 april 2022 - Initial version
v2.0 22 november 2024 - Add option to see permission graph - not work by now

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
DEALINGS IN THE SOFTWARE.

#>
function Get-ExchangeRoleReport {
    [CmdletBinding()]
    param (
        [switch]$ShowGraph
    )

    try {
        Import-Module ExchangeOnlineManagement -ErrorAction stop
    }
    catch {
        Write-Warning 'First, install the official Microsoft Import-Module ExchangeOnlineManagement module : Install-Module ExchangeOnlineManagement'
        return
    }

    try {
        # -ShowPartnerLinked : 
        # This ShowPartnerLinked switch specifies whether to return built-in role groups that are of type PartnerRoleGroup. You don't need to specify a value with this switch.
        # This type of role group is used in the cloud-based service to allow partner service providers to manage their customer organizations.
        # These types of role groups can't be edited and are not shown by default.
        $exchangeRoles = Get-RoleGroup -ShowPartnerLinked -ErrorAction Stop
    }
    catch {
        Connect-ExchangeOnline
        $exchangeRoles = Get-RoleGroup -ShowPartnerLinked -ErrorAction Stop
    }
   
    $exchangeRolesMembership = New-Object 'System.Collections.Generic.List[System.Object]'

    foreach ($exchangeRole in $exchangeRoles) {        
        try {
            $roleMembers = @(Get-RoleGroupMember -Identity $exchangeRole.Identity -ResultSize Unlimited)

            # Add green color if member found into the role
            if ($roleMembers.count -gt 0) {
                Write-Host -ForegroundColor Green "Role $($exchangeRole.Name) - Member(s) found: $($roleMembers.count)"
            }
            else {
                Write-Host -ForegroundColor Cyan "Role $($exchangeRole.Name) - Member found: $($roleMembers.count)"
            }

            if ($exchangeRole.Description -eq '' -and $exchangeRole.Name -like 'ISVMailboxUsers_*') {
                $roleDescription = 'Third-party application developer mailbox role'
            }
            else {
                $roleDescription = $exchangeRole.Description
            }

            if ($roleMembers.count -eq 0) {
                $object = [PSCustomObject][ordered]@{
                    'Role'                       = $exchangeRole.Name
                    'MemberName'                 = '-'
                    'MemberDisplayName'          = '-'
                    'MemberPrimarySMTPAddres'    = '-'
                    'MemberIsDirSynced'          = '-'
                    'MemberObjectID'             = '-'
                    'MemberRecipientTypeDetails' = '-'
                    # si descriptin vide et si nom like ISVMailboxUsers_* on donne une description 'Third-party application developer mailbox role'
                    'RoleDescription'            = $roleDescription
                }
                
                $exchangeRolesMembership.Add($object)

            }
            else {         

                foreach ($roleMember in $roleMembers) {                
                    # if user already exist in the arraylist, we look for to prevent a new Get-MsolUser (time consuming)
                    # Select only the first if user already exists in multiple roles
                   
                    $object = [PSCustomObject][ordered]@{
                        'Role'                       = $exchangeRole.Name
                        'MemberName'                 = $roleMember.Name
                        'MemberDisplayName'          = $roleMember.DisplayName
                        'MemberPrimarySMTPAddres'    = $roleMember.PrimarySmtpAddress
                        'MemberIsDirSynced'          = $roleMember.IsDirSynced
                        'MemberObjectID'             = $roleMember.ExternalDirectoryObjectId
                        'MemberRecipientTypeDetails' = $roleMember.RecipientTypeDetails
                        'RoleDescription'            = $roleDescription
                    }

                    $exchangeRolesMembership.Add($object)
                }

            }
        }
        catch {
            Write-Warning $_.Exception.Message
        }
    }

    # TODO: Add Get-ManagementRoleAssignment to obtain permissions, as this is sometimes not done via a group
    #Get-ManagementRoleAssignment -RoleAssigneeType User
    
    return $exchangeRolesMembership
}