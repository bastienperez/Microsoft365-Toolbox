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
				
                if (-not($allO365EmailAddressesHashTable.ContainsKey($emailaddress))) {
                    $allO365EmailAddressesHashTable.add($emailaddress, ($emailaddress + '|' + $user.objectID + '|' + $user.DisplayName + '|' + $user.RecipientTypeDetails))
                }
                else {
                    # Write the details (objectID, RecipientType) of this account to better identification (if an email exists in some different objects type)
                    # don't write the objectID again
                    if ($allO365EmailAddressesHashTable[$emailaddress] -like "*$($user.objectID)*") {
                        # if objectID and recipientTypeDetails already exists, write nothing, otherwise write only the recipienttypedetails
                        if (-not($allO365EmailAddressesHashTable[$emailaddress] -like "*$($user.RecipientTypeDetails)*")) {
                            $allO365EmailAddressesHashTable[$emailaddress] = $allO365EmailAddressesHashTable[$emailaddress] + '|' + $user.RecipientTypeDetails
                        }
                    }
                    else {
                        $allO365EmailAddressesHashTable[$emailaddress] = $allO365EmailAddressesHashTable[$emailaddress] + '|' + $user.DisplayName + '|' + $user.objectID + '|' + $user.RecipientTypeDetails
                    }
                }
            }
        }
    }

    try {
        Import-Module exchangeonlinemanagement -ErrorAction stop
    }
    catch {
        Write-Warning 'First, install the official Microsoft Exchange Online Management module : Install-Module exchangeonlinemanagement'
        return
    }

    try {
        Import-Module MSOnline -ErrorAction stop
    }
    catch {
        Write-Warning 'First, install the official Microsoft Online module : Install-Module MSOnline'
        return
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
        Connect-MsolService
    }

    $allO365EmailAddressesHashTable = @{}

    ###### Exchange Online infrastructure
    Write-Host 'Get All Exchange Online recipients...' -ForegroundColor Green
    $allExchangeRecipients = Get-Recipient * -ResultSize unlimited | Select-Object DisplayName, RecipientTypeDetails, EmailAddresses, @{Name = 'objectID'; Expression = { $_.ExternalDirectoryObjectId } }
    Write-Host 'Get All SoftDeletedMailbox...' -ForegroundColor Green
    $SoftDeleted = Get-Mailbox -SoftDeletedMailbox -ResultSize unlimited | Select-Object DisplayName, RecipientTypeDetails, EmailAddresses, @{Name = 'objectID'; Expression = { $_.ExternalDirectoryObjectId } }

    ##### Azure Active Directory infrastructure
    Write-Host 'Get All Office 365 users...' -ForegroundColor Green

    # Office 365 users - UPN name
    # Same thing but with UPN because sometimes the UPN is not the same as the SMTP proxyaddresses
    $Office365Users = Get-MsolUser -All

    $Office365UPNUsers = $Office365Users | Select-Object DisplayName, objectID, @{Name = 'EmailAddresses'; Expression = { $_.UserPrincipalName } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member' -or $null -eq $_.UserType) { 'Office365User' } else { 'GuestUser' } } }
    $Office365EmailAddresses = $Office365Users | Select-Object DisplayName, objectID, @{Name = 'EmailAddresses'; Expression = { $_.ProxyAddresses } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member') { 'Office365User' }else { 'GuestUser' } } }
    $Office365AlternateEmailAddresses = $Office365Users | Select-Object DisplayName, objectID, @{Name = 'EmailAddresses'; Expression = { $_.AlternateEmailAddresses } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member' -or $null -eq $_.UserType) { 'O365UserAlternateEmailAddress' } else { 'GuestUserAlternateEmailAddress' } } }

    Write-Host 'Get All Office 365 deleted users...' -ForegroundColor Green

    $Office365DeletedUsers = Get-MsolUser -ReturnDeletedUsers -All

    $Office365DeletedUsersUPN = $Office365DeletedUsers | Select-Object DisplayName, objectID, @{Name = 'EmailAddresses'; Expression = { $_.UserPrincipalName } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member') { 'DeletedOffice365User' }else { 'DeletedGuestUser' } } }
    $Office365DeletedUsersEmailAddresses = $Office365DeletedUsers | Select-Object DisplayName, objectID, @{Name = 'EmailAddresses'; Expression = { $_.ProxyAddresses } }, @{Name = 'RecipientTypeDetails'; Expression = { if ($_.UserType -eq 'Member') { 'DeletedOffice365User' }else { 'DeletedGuestUser' } } }

    # Creating hashtable
    Write-Host 'Creating HashTable...' -ForegroundColor Green
    AddtoHashTable -HashTable $allO365EmailAddressesHashTable -Users $allExchangeRecipients
    AddtoHashTable -HashTable $allO365EmailAddressesHashTable -Users $SoftDeleted

    AddtoHashTable -HashTable $allO365EmailAddressesHashTable -Users $Office365UPNUsers 
    AddtoHashTable -HashTable $allO365EmailAddressesHashTable -Users $Office365EmailAddresses
    AddtoHashTable -HashTable $allO365EmailAddressesHashTable -Users $Office365AlternateEmailAddresses

    AddtoHashTable -HashTable $allO365EmailAddressesHashTable -Users $Office365DeletedUsersUPN 
    AddtoHashTable -HashTable $allO365EmailAddressesHashTable -Users $Office365DeletedUsersEmailAddresses

    if ($SearchEmails) {
        foreach ($SearchEmail in $SearchEmails) {

            if ($allO365EmailAddressesHashTable.Contains($SearchEmail)) {
                Write-Host $SearchEmail 'matching: ' -ForegroundColor Yellow -NoNewline
                $allO365EmailAddressesHashTable[$SearchEmail]
            }
            else {
                Write-Host $SearchEmail 'not found' -ForegroundColor Red
            }
        }
    }
    
    else {
        return $allO365EmailAddressesHashTable
    }
}