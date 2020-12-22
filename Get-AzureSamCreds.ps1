<#
Name:    Get-AzureSamCreds.ps1
Author:  Robert Parkhurst <raparkhurst@digitalsynapse.io>

Original
Author:  James Meredith & Kevin Sparenberg

Purpose: Make a query to Azure Portal and configure a client/application ID and secret key combination.
         Provide results back to the screen and save the same to a CSV on the user's desktop
Version History:
 1.5: Fixed Password string
 1.0: Current Version (better documentation)
 0.5: Improved Error Handling
 0.1: Original Version

 
Variables:
    $IdentifierUris :: Unique identifying name for the Client Application
    $Role           :: Assignment of Roles
                          For read-only access only, use "Reader" (Standard Polling)
                          For read-write access, use "Owner"      (Leverage Cloud Management within Orion)
#>

param($AccountType, $Debug)

# Variables
$IdentifierUris = "https://www.solarwinds.com"
$Role           = "Reader" # or "Owner", or "Reader"



# A wrapper function for debugging output
Function PrintDebug{
	Param ($Text)
	
	if ($Debug -eq "true") {
		Write-Host "*** DEBUG:  $Text" -ForegroundColor Magenta -BackgroundColor Black
	}
}

# A wrapper function for printing error output
Function PrintError{
	Param ($Text)
	
	Write-Host "*** ERROR:  $Text" -ForegroundColor Red -BackgroundColor Black
}


Write-Host "This script can be used to create an Application Registration for SAM in either an Azure Commercial account or Azure Government Account."
Write-Host "Currently, only usgovernment is supported for government accounts."
Write-Host ""
Write-Host "To launch for usgovernment, please use -AccountType ""usgovernment"" "

#Write-Host "Value of AccountType is:  $AccountType"
#Write-Host "Value of Debug is:  $Debug"

#if ($Debug -eq "true") {
#	PrintDebug "Debug test!"
#}


# This script requires the Azure PowerShell cmdlets from the "Command-line tools" section at https://azure.microsoft.com/en-us/downloads/
if ( -not ( Get-Command -Name Login-AzureRmAccount -ErrorAction SilentlyContinue ) )
{
    Write-Error -Message "Missing the Azure PowerShell cmdlets.`nDownload the cmdlets from 'https://azure.microsoft.com/en-us/downloads/'"
}
else
{
    if ( -not $AccountInfo )
    {
		if ($AccountType -eq "usgovernment") {
			$AccountInfo = Login-AzureRmAccount -Environment AzureUSGovernment
			Write-Host " *** USGovernment Selected ***" -ForegroundColor Green -BackgroundColor Black
		} elseif ($AccountType -eq "commercial") {
			$AccountInfo = Login-AzureRmAccount
			Write-Host " *** Commercial Selected ***" -ForegroundColor Green -BackgroundColor Black
		} else {
			PrintError "No AccountType Selected!  Please use -AccountType ""usgovernment"" or -AccountType ""commercial"" "
			exit
		}
		
    }
 
    # ****** Script assumes a single tenant. ******
    # If you don't want to use your default subscription, you will have to add the following line.
    #Set-AzureRmContext -SubscriptionId "...................................."
     
    $Tenant = $AccountInfo.Context.Subscription.TenantId
    $Sub = $AccountInfo.Context.Subscription.SubscriptionId
 
    $NewPass = ( [guid]::NewGuid() ).Guid
    $NewSecurePass = ConvertTo-SecureString -String $NewPass -AsPlainText -Force 
    $MyNumber = Get-Random -Minimum 1000000000 -Maximum 9999999999
    $AppName = "SolarWindsSAM$MyNumber"
    if ( Get-AzureRmADApplication -IdentifierUri $IdentifierUris -ErrorAction SilentlyContinue )
    {
        Write-Error -Message "An application with IdentifierUris of `"$IdentifierUris`" already exists.`nRemove the current application via `"Get-AzureRmADApplication -IdentifierUri `"$IdentifierUris`" | Remove-AzureRmADApplication -Force`""
        break
    }
    else
    {
        Write-Host "Creating an application in Azure named $AppName with a password of $NewPass" -ForegroundColor Yellow
        $AppInfo = New-AzureRmADApplication -Displayname $AppName -IdentifierUris $IdentifierUris -Password $NewSecurePass
    }
    Write-Host "Application creation complete, waiting for the cloud to catch up." -ForegroundColor Yellow

    #region countdown
    $Seconds = 20; $Activity = "Waiting for Cloud Sync of Application"
    For ( $i = $Seconds; $i -ge 0; $i-- )
    {
        Write-Progress -Activity $Activity -SecondsRemaining $i -PercentComplete ( ( 100 * ( $Seconds - $i ) ) / $Seconds )
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity $Activity -Completed
    #endregion countdown

    $AppID = $AppInfo.ApplicationId.Guid.ToString()
    $Object = $AppInfo.ObjectId.Guid
    #region Output Results
    Write-Host "Here is your cloud account credential information for SAM.  Be sure to capture the secret key somewhere as it cannot be re-accessed" -ForegroundColor Yellow
    Write-Host "`n------------------------------------------------------------"
    Write-Host "Subscription ID:        $Sub"
    Write-Host "Tenant ID:              $Tenant"
    Write-Host "Application ID:         $AppID"
    Write-Host "Application Secret Key: $NewPass"
    Write-Host "------------------------------------------------------------`n"
    Write-Host "Creating a service principal for the application. Don't test these credentials in SAM until this script completes" -ForegroundColor Yellow
    "Subscription ID,$Sub`nTenant / Directory ID,$Tenant`nClient / Application ID,$AppID`nApplication Secret Key,$NewPass" | Out-File -FilePath "$env:UserProfile\Desktop\AzureKeys.csv" -Encoding ascii -Confirm:$false -Force
    Write-Host "+------------------------------------------------+`n|   CSV File with Credentials saved to Desktop   |`n+------------------------------------------------+" -ForegroundColor Cyan -BackgroundColor Black
 
    #endregion Output Results
    #$SvcPrincipal = New-AzureRmADServicePrincipal -ApplicationID $AppInfo.ApplicationID -Password $NewPass
	PrintDebug "Attempting to create service principal..."
	$SvcPrincipal = New-AzureRmADServicePrincipal -ApplicationID $AppInfo.ApplicationID -Password $NewSecurePass
    
    Write-Host "Service principal creation complete, letting the cloud catch up again..." -ForegroundColor Yellow
    
    #region countdown
    $Seconds = 35; $Activity = "Waiting for Cloud Sync of Service Principal"
    For ( $i = $Seconds; $i -ge 0; $i-- )
    {
        Write-Progress -Activity $Activity -SecondsRemaining $i -PercentComplete ( ( 100 * ( $Seconds - $i ) ) / $Seconds )
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity $Activity -Completed
    #endregion countdown

    Write-Host "Assigning Reader role to new application" -ForegroundColor Yellow
    $RoleAssign = New-AzureRmRoleAssignment -ServicePrincipalName $SvcPrincipal.ApplicationID -RoleDefinitionName $Role
    
    #region countdown
    $Seconds = 35; $Activity = "Waiting for Cloud Sync of Role Permissions"
    For ( $i = $Seconds; $i -ge 0; $i-- )
    {
        Write-Progress -Activity $Activity -SecondsRemaining $i -PercentComplete ( ( 100 * ( $Seconds - $i ) ) / $Seconds )
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity $Activity -Completed
    #endregion countdown

    Write-Host "Done - You can now add your Azure Cloud Monitoring to Orion" -ForegroundColor Green
}
