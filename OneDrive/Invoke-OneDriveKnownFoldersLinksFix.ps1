$oneDriveRoot = $env:OneDriveCommercial
$userProfile = $env:USERPROFILE

$oneDriveDesktop = [Environment]::GetFolderPath('Desktop')
$oneDriveMyDocuments = [Environment]::GetFolderPath('MyDocuments')
$oneDriveMyPictures = [Environment]::GetFolderPath('MyPictures')

function Invoke-OneDriveKnownFoldersLinksFix {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Folder,
		[Parameter(Mandatory = $true)]
		[string]$OneDriveFolder
	)
		
	if ($oneDriveFolder -like "$oneDriveRoot*") {
		Write-Host "$folder is on OneDrive $oneDriveFolder" -ForegroundColor green
		$junctionsFolder = $null
		$junctionsFolder = Get-ChildItem "$userProfile\$folder" -Force | Where-Object -Property Attributes -Like '*ReparsePoint*'
		
		if ($null -ne $junctionsFolder) {
			$junctionsFolder | ForEach-Object {
				$tempFolder = New-Item -Path $env:SystemDrive\temp_OneDrive_$(Get-Date -Format 'yyyyMMdd') -ItemType Directory -ErrorAction SilentlyContinue

				Write-Host "Move junction folder $($_.FullName) to $($tempFolder.FullName) because it causes issues for the move (access denied on folder if we do not)" -ForegroundColor green

				Move-Item -Path $_.FullName -Destination $tempFolder.FullName -Force
			}
		}

		Write-Host "Move $userProfile\$folder to $OneDriveFolder" -ForegroundColor green
		try {
			Move-Item "$userProfile\$folder" $OneDriveFolder -ErrorAction SilentlyContinue
		}
		catch {
			Write-Warning "Unable to move items from $userProfile\$folder to $OneDriveFolder. $($_.Exception.Message)"
			return
		}

		Write-Host "Delete $userProfile\$folder folder" -ForegroundColor green
		try {
			Remove-Item "$userProfile\$folder" -Recurse -Force
		}
		catch {
			Write-Warning "Unable to remove folder $userProfile\$folder. $($_.Exception.Message)"
			return
		}

		Write-Host "Create symbolic link $userProfile\$folder => $oneDriveFolde" -ForegroundColor green
		cmd /c mklink /J "$userProfile\$Folder" "$oneDriveFolder"
	}
}

Invoke-OneDriveKnownFoldersLinksFix -Folder Desktop -OneDriveFolder $oneDriveDesktop
Invoke-OneDriveKnownFoldersLinksFix -Folder Images -OneDriveFolder $oneDriveMyPictures
Invoke-OneDriveKnownFoldersLinksFix -Folder Documents -OneDriveFolder $oneDriveMyDocuments