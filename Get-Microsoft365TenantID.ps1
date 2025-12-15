# Another great way to get tenant ID from domain: https://www.whatismytenantid.com/result
function Get-Microsoft365TenantID {
	param(
		[CmdletBinding()]
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Domain
	)

	(Invoke-WebRequest https://login.windows.net/$Domain/.well-known/openid-configuration -UseBasicParsing | ConvertFrom-Json).Token_Endpoint.Split('/')[3]
}