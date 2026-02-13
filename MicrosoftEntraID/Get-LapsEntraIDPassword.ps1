<#.SYNOPSIS
Retrieves the LAPS password for a Microsoft Entra ID device.

.DESCRIPTION
Gets the Windows Local Administrator Password Solution (LAPS) password for a specified device in Microsoft Entra ID (formerly Azure AD).

.PARAMETER DeviceID
The Microsoft Entra ID (Azure AD) Device ID for which you want to retrieve the LAPS password. This is the unique identifier assigned to the device in Microsoft Entra ID.

.EXAMPLE
PS> Get-LapsEntraIDPassword -DeviceID "12345678-1234-1234-1234-123456789012"
Retrieves the LAPS password for the specified device ID.

.EXAMPLE
PS> Get-LapsEntraIDPassword -DeviceID "12345678-1234-1234-1234-123456789012" -IncludePasswords
Retrieves the LAPS password for the specified device ID, including the password itself as a secure string.

.EXAMPLE
PS> Get-LapsEntraIDPassword -DeviceID "12345678-1234-1234-1234-123456789012" -IncludePasswords -AsPlainText
Retrieves the LAPS password for the specified device ID, including the password itself, and displays the password in plain text.

.EXAMPLE
PS> Get-LapsEntraIDPassword -DeviceID "12345678-1234-1234-1234-123456789012" -IncludePasswords -IncludeHistory
Retrieves the LAPS password for the specified device ID, including the password itself, and includes the password history.

.EXAMPLE
PS> Get-LapsEntraIDPassword -DeviceID "12345678-1234-1234-1234-123456789012" -IncludePasswords -IncludeHistory -AsPlainText
Retrieves the LAPS password for the specified device ID, including the password itself, includes the password history, and displays the password in plain text.

.EXAMPLE
$windowsDevices = Get-MgDevice -All | Where-Object { $_.OperatingSystem -eq "Windows" }
$total = $windowsDevices.Count
$counter = 0

# filtre sur FR3228 et DIP-2410-16
$lapsPwd = $windowsDevices | ForEach-Object { 
    $counter++
    Write-Host "Processing device $($_.DisplayName) with ID $($_.Id) ($($counter)/$($total))"
    Get-LapsEntraIDPassword -DeviceID $_.DeviceId -IncludePasswords -AsPlainText
}

$lapsPwd = $windowsDevices | Where-Object { $_.DisplayName -match 'FR3228|DIP-2410-16' } | ForEach-Object { 

Retrieves the LAPS passwords for all Windows devices in Microsoft Entra ID.

.NOTES
Requires appropriate permissions in Microsoft Entra ID to read LAPS passwords.
This cmdlet is part of the Microsoft365-Toolbox module.

#>

function Get-LapsEntraIDPassword {
    param(
        [Parameter(Mandatory = $true, HelpMessage = 'The Microsoft Entra ID (Azure AD) Device ID for which you want to retrieve the LAPS password.')]
        [string]$DeviceID,
        [switch]$IncludePasswords,
        [switch]$AsPlainText,
        [switch]$IncludeHistory
    )

    #Connect to Microsoft Graph
    #Connect-MgGraph -Scope DeviceLocalCredential.Read.All, Device.Read.All

    #Define your device name here
    #$DeviceName = ''
    #Store the device id value for your target device
    #$DeviceId = (Get-MgDevice -All | Where-Object { $_.DisplayName -eq $DeviceName } | Select-Object DeviceId).DeviceId

    #Define the URI path
    $uri = 'v1.0/directory/deviceLocalCredentials/' + $DeviceId
    # ?$select=credentials will cause the server to return all credentials, ie latest plus history

    if ($IncludePasswords.IsPresent) {
        $uri = $uri + '?$select=credentials'
    }

    #Generate a new correlation ID
    $correlationID = [System.Guid]::NewGuid()
        
    #Build the request header
    $headers = @{}
    $headers.Add('ocp-client-name', 'Get-LapsAADPassword Windows LAPS Cmdlet')
    $headers.Add('ocp-client-version', '1.0')
    $headers.Add('client-request-id', $correlationID)

    #Initation the request to Microsoft Graph for the LAPS password
    try {
        $response = Invoke-MgGraphRequest -Method GET -Uri $URI -Headers $headers -OutputType Json
    }
    catch {
        Write-Warning "Device ID: $DeviceId $($_.Exception.Message -replace "`n", ' ' -replace "`r", ' ')"
        $object = [PSCustomObject][ordered]@{
            DeviceName             = '$null'
            DeviceId               = $deviceID
            PasswordExpirationTime = $null
        }

        return $object
    }

    if ([string]::IsNullOrWhitespace($response)) {
        $object = [PSCustomObject][ordered]@{
            DeviceName             = '$null'
            DeviceId               = $deviceID
            PasswordExpirationTime = $null
        }

        return $object
    }

    # Build custom PS output object
    $resultsJson = ConvertFrom-Json $response
    
    $lapsDeviceId = $resultsJson.deviceName

    $lapsDeviceId = New-Object([System.Guid])
    $lapsDeviceId = [System.Guid]::Parse($resultsJson.id)

    # Grab password expiration time (only applies to the latest password)
    $lapsPasswordExpirationTime = Get-Date $resultsJson.refreshDateTime

    if ($IncludePasswords) {
        # Copy the credentials array
        $credentials = $resultsJson.credentials

        # Sort the credentials array by backupDateTime.
        $credentials = $credentials | Sort-Object -Property backupDateTime -Descending

        # Note: current password (ie, the one most recently set) is now in the zero position of the array

        # If history was not requested, truncate the credential array down to just the latest one
        if (-not $IncludeHistory) {
            $credentials = @($credentials[0])
        }

        foreach ($credential in $credentials) {

            # Cloud returns passwords in base64, convert:
            if ($AsPlainText) {
                $password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($credential.passwordBase64))
            }
            else {
                $bytes = [System.Convert]::FromBase64String($credential.passwordBase64)

                $plainText = [System.Text.Encoding]::UTF8.GetString($bytes)

                $password = ConvertTo-SecureString $plainText -AsPlainText -Force
            }

            $lapsPasswordExpirationTime = $null

            $object = [PSCustomObject][ordered]@{
                DeviceName             = $resultsJson.deviceName
                DeviceId               = $lapsDeviceId
                Account                = $credential.accountName
                Password               = $password
                PasswordExpirationTime = $lapsPasswordExpirationTime
                PasswordUpdateTime     = Get-Date $credential.backupDateTime
            }

            $object
        }
    }
    else {
        # Output a single object that just displays latest password expiration time
        # Note, $IncludeHistory is ignored even if specified in this case
        $object = [PSCustomObject][ordered]@{
            DeviceName             = $resultsJson.deviceName
            DeviceId               = $lapsDeviceId
            PasswordExpirationTime = $lapsPasswordExpirationTime
        }

        $object
    }
}