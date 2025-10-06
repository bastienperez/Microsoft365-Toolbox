# https://github.com/itpro-tips/Microsoft365-Toolbox

function Search-EmailAddressInMicrosoftCloud {
    [CmdletBinding()]
    Param(
        [string[]]$SearchEmails,
        [string[]]$SearchByDomain
    )

    function AddtoHashTable {
        Param
        (
            $HashTable,
            $Users
        )
        foreach ($user in $users) {
            foreach ($emailaddress in $user.emailaddresses) {
                #Write-Host 'Processing' $emailaddress -ForegroundColor green
                $emailaddress = $emailaddress -replace 'X500:', ''
                $emailaddress = $emailaddress -replace 'smtp:', ''
                $emailaddress = $emailaddress -replace 'sip:', ''
                $emailaddress = $emailaddress -replace 'spo:', ''

                if ($SearchByDomain) {
                    if ($emailaddress -notlike "*$SearchByDomain") {
                        continue
                    }
                }
				
                if (-not($allM365EmailAddressesHashTable.ContainsKey($emailaddress))) {
                    $allM365EmailAddressesHashTable.add($emailaddress, ($emailaddress + '|' + $user.objectID + '|' + $user.DisplayName + '|' + $user.RecipientTypeDetails))
                }
                else {
                    # Write the details (objectID, RecipientType) of this account to better identification (if an email exists in some different objects type)
                    # don't write the objectID again
                    if ($allM365EmailAddressesHashTable[$emailaddress] -like "*$($user.objectID)*") {
                        # if objectID and recipientTypeDetails already exists, write nothing, otherwise write only the recipienttypedetails
                        if (-not($allM365EmailAddressesHashTable[$emailaddress] -like "*$($user.RecipientTypeDetails)*")) {
                            $allM365EmailAddressesHashTable[$emailaddress] = $allM365EmailAddressesHashTable[$emailaddress] + '|' + $user.RecipientTypeDetails
                        }
                    }
                    else {
                        $allM365EmailAddressesHashTable[$emailaddress] = $allM365EmailAddressesHashTable[$emailaddress] + '|' + $user.DisplayName + '|' + $user.objectID + '|' + $user.RecipientTypeDetails
                    }
                }
            }
        }
    }

    $modules = @(
        'ExchangeOnlineManagement'
        'Microsoft.Graph.Authentication'
        'Microsoft.Graph.Users'
    )

    foreach ($module in $modules) {
        try {
            Import-Module $modules -ErrorAction stop
        }
        catch {
            Write-Warning "First, install the Microsoft $modules module first : Install-Module $modules"
            return
        }
    }

    try {
        #WarningAction = silentlycontinue because of warning message when resultsize is bigger than 10
        $null = Get-Recipient -ResultSize 1 -ErrorAction Stop -WarningAction silentlycontinue
    }
    catch {
        Write-Host 'Connect Exchange Online' -ForegroundColor Green
        Connect-ExchangeOnline
    }

    try {
        $null = Get-MsolUser -MaxResults 1 -ErrorAction Stop 
    }
    catch {
        Write-Host 'Connect MsolService Online' -ForegroundColor Green
        Connect-MgGraph -Scopes 'User.Read.All' -NoWelcome
    }

    $allM365EmailAddressesHashTable = @{}

    ###### Exchange Online infrastructure
    Write-Host 'Get All Exchange Online recipients...' -ForegroundColor Green
    $allExchangeRecipients = Get-Recipient * -ResultSize unlimited | Select-Object DisplayName, RecipientTypeDetails, EmailAddresses, @{Name = 'objectID'; Expression = { $_.ExternalDirectoryObjectId } }
    
    Write-Host 'Get All softDeletedMailbox...' -ForegroundColor Green
    $softDeleted = Get-Mailbox -SoftDeletedMailbox -ResultSize unlimited | Select-Object DisplayName, RecipientTypeDetails, EmailAddresses, @{Name = 'objectID'; Expression = { $_.ExternalDirectoryObjectId } }

    ##### Azure Active Directory infrastructure
    Write-Host 'Get All Microsoft 365 users...' -ForegroundColor Green

    # Microsoft 365 users - UPN name
    # Same thing but with UPN because sometimes the UPN is not the same as the SMTP proxyaddresses
    $entraIDUsers = Get-MgUser -All -Property UserPrincipalName, ID, UserType, ProxyAddresses
    
    $m365UPNUsers = $entraIDUsers | Select-Object DisplayName, @{Name = 'objectID'; Expression = { $_.ID } }, @{Name = 'EmailAddresses'; Expression = { $_.UserPrincipalName } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member' -or $null -eq $_.UserType) { 'Microsoft365User' } else { 'GuestUser' } } }
    $m365EmailAddresses = $entraIDUsers | Select-Object DisplayName, @{Name = 'objectID'; Expression = { $_.ID } }, @{Name = 'EmailAddresses'; Expression = { $_.ProxyAddresses } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member') { 'Microsoft365User' }else { 'GuestUser' } } }
    $m365AlternateEmailAddresses = $entraIDUsers | Select-Object DisplayName, @{Name = 'objectID'; Expression = { $_.ID } }, @{Name = 'EmailAddresses'; Expression = { $_.OtherMails } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member' -or $null -eq $_.UserType) { 'O365UserAlternateEmailAddress' } else { 'GuestUserAlternateEmailAddress' } } }

    Write-Host 'Get All Microsoft 365 deleted users...' -ForegroundColor Green

    $entraIDDeletedUsers = Get-MgDirectoryDeletedItemAsUser -All

    $entraIDDeletedUsersUPN = $entraIDDeletedUsers | Select-Object DisplayName, @{Name = 'objectID'; Expression = { $_.ID } }, @{Name = 'EmailAddresses'; Expression = { $_.UserPrincipalName } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member') { 'DeletedMicrosoft365User' }else { 'DeletedGuestUser' } } }
    $entraIDDeletedUsersEmailAddresses = $entraIDDeletedUsers | Select-Object DisplayName, @{Name = 'objectID'; Expression = { $_.ID } }, @{Name = 'EmailAddresses'; Expression = { $_.ProxyAddresses } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member') { 'DeletedMicrosoft365User' }else { 'DeletedGuestUser' } } }

    # Creating hashtable
    Write-Host 'Creating HashTable...' -ForegroundColor Green
    AddtoHashTable -HashTable $allM365EmailAddressesHashTable -Users $allExchangeRecipients
    AddtoHashTable -HashTable $allM365EmailAddressesHashTable -Users $softDeleted

    AddtoHashTable -HashTable $allM365EmailAddressesHashTable -Users $m365UPNUsers 
    AddtoHashTable -HashTable $allM365EmailAddressesHashTable -Users $m365EmailAddresses
    AddtoHashTable -HashTable $allM365EmailAddressesHashTable -Users $m365AlternateEmailAddresses

    AddtoHashTable -HashTable $allM365EmailAddressesHashTable -Users $entraIDDeletedUsersUPN 
    AddtoHashTable -HashTable $allM365EmailAddressesHashTable -Users $entraIDDeletedUsersEmailAddresses

    if ($SearchEmails) {
        foreach ($SearchEmail in $SearchEmails) {

            if ($allM365EmailAddressesHashTable.Contains($SearchEmail)) {
                Write-Host $SearchEmail 'matching: ' -ForegroundColor Yellow -NoNewline
                $allM365EmailAddressesHashTable[$SearchEmail]
            }
            else {
                Write-Host $SearchEmail 'not found' -ForegroundColor Red
            }
        }
    }
    
    else {
        return $allM365EmailAddressesHashTable
    }
}