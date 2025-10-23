<#
.SYNOPSIS
    Retrieves all Entra ID applications configured for SCIM provisioning.

.DESCRIPTION
    This function returns a list of all Entra ID applications with SCIM provisioning enabled,
    along with their synchronization job details and settings.

.EXAMPLE
    $scimApps = Get-MgApplicationSCIM

    Retrieves all Entra ID applications with SCIM provisioning enabled.

.EXAMPLE
    Get-MgApplicationSCIM -ForceNewToken

    Forces the function to disconnect and reconnect to Microsoft Graph to obtain a new access token.

    .EXAMPLE
    Get-MgApplicationSCIM -Export

    Exports the SCIM configuration details to a CSV file.

    .EXAMPLE
    Get-MgApplicationSCIM -ObjectID "xxx-xxx-xxx"

    Retrieves the SCIM configuration for a specific application by its ObjectID.

    .NOTES
    .REQUIREMENTS
    This function requires the Microsoft.Graph.Applications and Microsoft.Graph.Authentication modules.

    .AUTHOR
    Bastien Perez

    .LIMITATIONS
    The groups assignments are not retrieved because based on https://main.iam.ad.ext.azure.com

    .CHANGELOG
    ### Added
    - Export functionality for synchronization job details
    - Support for additional synchronization job properties

    ## [1.1] - 2025-02-26
    ### Changed
    - Transform the script into a function
    - Replace `Write-Host` with `Write-Verbose`

    ## [1.0] - 2024-xx-xx
    ### Initial Release
#>

function Get-MgApplicationSCIM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ObjectID,
        [Parameter(Mandatory = $false)]
        [switch]$ForceNewToken,
        [Parameter(Mandatory = $false)]
        [switch]$Export
    )

    [System.Collections.Generic.List[PSCustomObject]]$synchronizationJobsArray = @()
    [System.Collections.Generic.List[PSCustomObject]]$synchronizationJobsDetailsArray = @()

    if ($ForceNewToken.IsPresent) {
        if (Get-MgContext) {
            $null = Disconnect-MgGraph
        }

        $scopes = @(
            'Directory.Read.All'
        )

        Connect-MgGraph -Scopes $scopes -NoWelcome
    }
    if ($ObjectID) {
        $servicePrincipals = Get-MgServicePrincipal -ServicePrincipalId $ObjectID
    }
    else {
        $servicePrincipals = Get-MgServicePrincipal -All -Property DisplayName, Id
    }

    Write-Host "$($servicePrincipals.Count) service principals found"

    $i = 0
    foreach ($servicePrincipal in $servicePrincipals) {
        $i++
        Write-Host "($i/$($servicePrincipals.Count)) - $($servicePrincipal.DisplayName)  and check for synchronization jobs" -ForegroundColor Cyan
        # Service principal is the ObjectID in Microsoft Entra ID
        $job = Get-MgServicePrincipalSynchronizationJob -ServicePrincipalId $servicePrincipal.Id -All
        
        if ($job) {
            Write-Host "$($servicePrincipal.DisplayName) - Synchronization job found" -ForegroundColor Green
            
            # We need to keep $servicePrincipal.Id in a new property ServicePrincipalID

            $job | Add-Member -MemberType NoteProperty -Name ServicePrincipalId -Value $servicePrincipal.Id
            $job | Add-Member -MemberType NoteProperty -Name DisplayName -Value $servicePrincipal.DisplayName
        
            $provisioningSettings = Invoke-GraphRequest -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($job.ServicePrincipalId)/synchronization/secrets" -Method Get -OutputType PSObject

            $job | Add-Member -MemberType NoteProperty -Name ProvisioningBaseAddress -Value $($provisioningSettings.Value | Where-Object { $_.key -eq 'BaseAddress' }).Value
            $job | Add-Member -MemberType NoteProperty -Name ProvisioningSyncAll -Value $($provisioningSettings.Value | Where-Object { $_.key -eq 'SyncAll' }).Value
            $SyncNotificationSettings = ($provisioningSettings.Value | Where-Object { $_.key -eq 'SyncNotificationSettings' }).Value | ConvertFrom-Json
            $job | Add-Member -MemberType NoteProperty -Name ProvisioningNotificationEnabled -Value $SyncNotificationSettings.Enabled
            $job | Add-Member -MemberType NoteProperty -Name ProvisioningNotificationRecipientAddress -Value $SyncNotificationSettings.Recipients
            $job | Add-Member -MemberType NoteProperty -Name ProvisioningNotificationDeleteThresholdEnabled -Value $SyncNotificationSettings.DeleteThresholdEnabled
            $job | Add-Member -MemberType NoteProperty -Name ProvisioningNotificationDeleteThresholdValue -Value $SyncNotificationSettings.DeleteThresholdValue
            $job | Add-Member -MemberType NoteProperty -Name ProvisioningNotificationHumanResourcesLookaheadQueryEnabled -Value $SyncNotificationSettings.HumanResourcesLookaheadQueryEnabled    

            # status Value
            $job | Add-Member -MemberType NoteProperty -Name StatusCode -Value $job.Status.Code
            $job | Add-Member -MemberType NoteProperty -Name CountSuccessiveCompleteFailures -Value $job.Status.CountSuccessiveCompleteFailures
            $job | Add-Member -MemberType NoteProperty -Name EscrowsPruned -Value $job.Status.EscrowsPruned
            $job | Add-Member -MemberType NoteProperty -Name SteadyStateFirstAchievedTime -Value $job.Status.SteadyStateFirstAchievedTime
            $job | Add-Member -MemberType NoteProperty -Name SteadyStateLastAchievedTime -Value $job.Status.SteadyStateLastAchievedTime
            $job | Add-Member -MemberType NoteProperty -Name TroubleshootingUrl -Value $job.Status.TroubleshootingUrl

            # synchronizationJobSettings Value
            foreach ($property in $job.SynchronizationJobSettings) {
                $job | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value
            }

            # we exclude the Status and SynchronizationJobSettings properties because we already got its values
            $job = $job | Select-Object -ExcludeProperty Status, SynchronizationJobSettings
            $synchronizationJobsArray.Add($job)
        }
        else {
            Write-Host "$($servicePrincipal.DisplayName) - No synchronization job found" -ForegroundColor Yellow
        }
    }

    $j = 0
    foreach ($job in $synchronizationJobsArray) {
        $j++

        # Get information about

        Write-Host "Get synchronization settings $($job.DisplayName) ($j/$($synchronizationJobsArray.Count))"

        $jobSchema = Get-MgServicePrincipalSynchronizationJobSchema -ServicePrincipalId $job.ServicePrincipalId -SynchronizationJobId $job.Id

        $job | Add-Member -MemberType NoteProperty -Name Scheduling -Value $job.Schedule.Interval
        $job | Add-Member -MemberType NoteProperty -Name SchedulingState -Value $job.Schedule.State
        $job | Add-Member -MemberType NoteProperty -Name LastSuccessfulExecutionDate -Value $job.Status.LastSuccessfulExecution.TimeEnded
        $job | Add-Member -MemberType NoteProperty -Name LastSuccessfulExecutionState -Value $job.Status.LastSuccessfulExecution.State
        $job | Add-Member -MemberType NoteProperty -Name LastSuccessfulExecutionWithExportsDate -Value $job.Status.LastSuccessfulExecutionWithExports.TimeEnded
        $job | Add-Member -MemberType NoteProperty -Name LastSuccessfulExecutionWithExportsState -Value $job.Status.LastSuccessfulExecutionWithExports.State

        if ($job.Status.Quarantine.CurrentBegan) {
            $job | Add-Member -MemberType NoteProperty -Name Quarantined -Value $true
        }
        else {
            $job | Add-Member -MemberType NoteProperty -Name Quarantined -Value $false
        }

        foreach ($type in $job.Status.SynchronizedEntryCountByType) {
            # it's not an hashtable but an array
            $key = $type.Key
            $count = $type.Value

            $job | Add-Member -MemberType NoteProperty -Name "SynchronizedEntryCountByType_$key" -Value $count
        }

        [System.Collections.Generic.List[PSCustomObject]]$attributesArray = @()
    
        foreach ($objectMapping in $jobSchema.SynchronizationRules.ObjectMappings) {

            foreach ($mapping in $objectMapping) {
                $res = $null

                $targetObjectType = $mapping.TargetObjectName

                foreach ($attribute in $mapping.AttributeMappings) {
                
                    $object = [PSCustomObject][ordered]@{
                        Type                    = $targetObjectType
                        DefaultValue            = $attribute.DefaultValue
                        ExportMissingReferences = $attribute.ExportMissingReferences
                        FlowBehavior            = $attribute.FlowBehavior
                        FlowType                = $attribute.FlowType
                        MatchingPriority        = $attribute.MatchingPriority
                        SourceExpression        = $attribute.Source.Expression
                        SourceAttributeName     = $attribute.Source.AttributeName
                        TargetAttributeName     = $attribute.TargetAttributeName
                    }

                    $attributesArray.Add($object)

                    # add delimiter if not the first attribute
                    if ($null -ne $res) {
                        $res = "$res # "
                    }

                    if ([string]::IsNullOrWhitespace($object.SourceAttributeName)) {
                        $res = "$res$($object.SourceExpression) --> $($object.TargetAttributeName)"
                    }
                    else {
                        $res = "$res$($object.SourceAttributeName) --> $($object.TargetAttributeName)"
                    }
                }           
            }

            $job | Add-Member -MemberType NoteProperty -Name "Attributes-$($object.Type)" -Value $res
        }
    
        # exclude properties because they are not needed
        $job = $job | Select-Object * -ExcludeProperty Schedule, Schema

        $synchronizationJobsDetailsArray.Add($job)
    }

    if ($Export.IsPresent) {
        $dateTimeStamp = Get-Date -Format 'yyyyMMdd-HHmm'
        $tenantInfo = Get-MgContext
        $tenantName = if ($tenantInfo.TenantId) { $tenantInfo.TenantId } else { 'notenant' }
        $fileName = "$dateTimeStamp`_$tenantName`_SCIMConfigurations.csv"
        
        $synchronizationJobsDetailsArray | Export-Csv -Path $fileName -NoTypeInformation -Encoding UTF8
        Write-Host "Data exported to: $fileName"
    }
    else {
        return $synchronizationJobsDetailsArray
    }
}