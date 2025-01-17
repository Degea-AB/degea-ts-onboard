# Author: Thomas Olenfalk
# Company: Degea AB
# Prerequisites: Step 4 has been run and Global Administrator Role
# Notes: 
    #The security group 'Degea Security Readers' needs to be added manually to the Reader role in Defender for Endpoint after the script has been run
    #This script should only be run in the case where Degea does not have regular administrative access (GDAP)

#Functions
function New-MailNickname {
    #Function removes diacritics from characters, sets all chars to lower case and removes white space

    [CmdletBinding()]
    param (
        [String]$InputString
    )

    # If string is null then return empty string
    if ($InputString -eq $null) {
        return [string]::Empty
    }
    $Normalized = $InputString.Normalize("FormD")

    #Loop through all chars, add only characters
    foreach ($Char in [Char[]]$Normalized) {
        $CharCategory = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($Char)
        if ($CharCategory -ne "NonSpacingMark") {
            $Result += $Char
        }
    }

    # Change to lower case and remove whitespace
    $Result = $Result.ToLower() -replace '\s', ''
    # Remove any remaining non char characters
    $Result = $Result -replace '[^a-z0-9]', ''
    # Limit length to 64
    if ($Result.Length -gt 64) {
        $Result = $Result.Substring(0, 64)
    }

    return $Result
}

#Graph
Disconnect-MgGraph
$scopes = "Policy.ReadWrite.CrossTenantAccess", #Cross tenant access
"Application.ReadWrite.All", #Edit Service principal
'Group.ReadWrite.All', # Create groups
'RoleManagement.ReadWrite.Directory' # Assign AAD Roles
Connect-MgGraph -Scopes $scopes -ContextScope Process

# Open URL to consent application
Start-Process "https://login.microsoftonline.com/common/adminconsent?client_id=2fb9874d-773d-4b74-bc24-282f4c0e7816"

Write-Host -ForegroundColor Yellow "Consent to the application, then press Enter to continue. Waiting 30 seconds to create service principal."
Start-Sleep -Seconds 30
Pause

$xtSettingsJson = Get-Content "$PSScriptRoot\6-DegeaAccess\crossTenantSettings.json"
$xtSettingsPSObj = $xtSettingsJson | ConvertFrom-Json

# Create
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners" -Body $xtSettingsJson

Start-Sleep -Seconds 5

# Verify
$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners/e832fb77-95d5-4bff-8f4e-09d1d922582e"
if (    $response.b2bcollaborationinbound.applications.accesstype -eq $xtSettingsPSObj.b2bCollaborationInbound.applications.accesstype -and `
        $response.b2bcollaborationinbound.applications.targets.target -eq $xtSettingsPSObj.b2bCollaborationInbound.applications.targets.target -and `
        $response.b2bCollaborationInbound.usersAndGroups.accessType -eq $xtSettingsPSObj.b2bCollaborationInbound.usersAndGroups.accessType -and `
        $response.b2bCollaborationInbound.usersAndGroups.targets.target -eq $xtSettingsPSObj.b2bCollaborationInbound.usersAndGroups.targets.target ) {
    Write-Host -ForegroundColor Green "B2B Collaboration settings OK"
}
else {
    Write-Host -ForegroundColor Red "B2B Collaboration settings incorrect"
}

if (    $response.inboundTrust.isMfaAccepted -eq $xtSettingsPSObj.inboundTrust.isMfaAccepted -and `
        $response.inboundTrust.isCompliantDeviceAccepted -eq $xtSettingsPSObj.inboundTrust.isCompliantDeviceAccepted -and `
        $response.inboundTrust.isHybridAzureADJoinedDeviceAccepted -eq $xtSettingsPSObj.inboundTrust.isHybridAzureADJoinedDeviceAccepted ) {
    Write-Host -ForegroundColor Green "Inbound trust settings OK"
}
else {
    Write-Host -ForegroundColor Red "Inbound trust settings incorrect"
}

Pause
Clear-Host

$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{2fb9874d-773d-4b74-bc24-282f4c0e7816}')"

# Hide app
$tags = [PSCustomObject]@{ tags = @("WindowsAzureActiveDirectoryIntegratedApp", "HideApp") } | ConvertTo-Json
$response = Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{2fb9874d-773d-4b74-bc24-282f4c0e7816}')" -Body $tags

# Add note
$notes = [pscustomobject]@{
    notes = "This application is used to synchronize Degea users and group memberships."
} | ConvertTo-Json
$response = Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{2fb9874d-773d-4b74-bc24-282f4c0e7816}')" -Body $notes

# Verify
$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{2fb9874d-773d-4b74-bc24-282f4c0e7816}')"

if ($response.notes -eq "This application is used to synchronize Degea users and group memberships." -and `
    $response.tags -contains "HideApp") {
    Write-Host -ForegroundColor Green 'Settings applied successfully to service principal'
} 
else {
    Write-Host -ForegroundColor Red 'Settings not applied successfully to service principal'
}

Pause
Clear-Host


$groupSettings = Get-Content "$PSScriptRoot\6-DegeaAccess\GroupSettings.json" | ConvertFrom-Json

#Get ID for service principal

$allRoles = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/directoryRoles" | Select-Object -ExpandProperty value

#Create groups
foreach ($group in $groupSettings.groups) {
    # isAssignableToRole - AADRoleAssignable
    $groupObject = $group | Select-Object mailenabled, displayName, description, isAssignableToRole
    #Create group
    $groupObject | Add-Member -NotePropertyMembers @{
        mailNickname    = (New-MailNickname -InputString $groupObject.displayName)
        securityEnabled = $true
    }

    $body = $groupObject | ConvertTo-Json

    $groupResponse = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups" -Body $body

    #Add owners (if it has a value)
    if ($group.OwnersSP) {
        $response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{$($group.OwnersSP)}')"
        $servicePrincipalId = $response.id
        $uri = "https://graph.microsoft.com/v1.0/groups/$($groupResponse.id)/owners/`$ref"
        $body = [PSCustomObject]@{
            "@odata.id" = "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId"
        } | ConvertTo-Json
        Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body
    }

    #Assign AAD roles (if it has a value)
    if ($group.AADRoleId) {
        # Activate role template if it is not activated
        if ($allRoles.roleTemplateId -notcontains $group.AADRoleId) {
            $body = [PSCustomObject]@{
                roleTemplateId = $group.AADRoleId
            } | ConvertTo-Json
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/directoryRoles" -Body $body
        }
        $uri = "https://graph.microsoft.com/v1.0/directoryRoles/roleTemplateId=$($group.AADRoleId)/members/`$ref"
        $body = [PSCustomObject]@{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($groupResponse.id)"
        } | ConvertTo-Json
        Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body
    }
}
