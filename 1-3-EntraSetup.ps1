# Author: Thomas Olenfalk
# Company: Degea AB
# Prerequisites: Global Administrator Role

# This script will
# 1. Create cross tenant access policy to Truesec SOC tenant (07d2f395-f69c-43ab-88a2-b82f1151042d)
# 2. Consent to Truesec SOC sync app and edit properties on the app (650c28b2-db2e-4e95-8124-0d3410659df4), opens in browser
# 3. Consent to Defender API access app and edit properties on the app (3bb658be-4eac-4832-baca-65fbde07f547), opens in browser
# 4. Consent to custom detection app and edit properties on the app (5d051ad5-01ff-41de-8336-6962ea18a341), opens in browser
# 5. Create groups for Truesec SOC and assign roles to the groups
# 6. Enable and assign PIM for the group "Truesec SOC Admins PIM"

#Graph
Disconnect-MgGraph #Clear context
$scopes = "Policy.ReadWrite.CrossTenantAccess", # Create cross tenant access policy
"Application.ReadWrite.All", # Create applications
"Group.ReadWrite.All", # Create groups
"RoleManagement.ReadWrite.Directory", # Assign AAD Roles
"PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup" # Privileged role assignment for groups (PIM)
Connect-MgGraph -Scopes $scopes -ContextScope Process

#region CrossTenantAccessPolicy
$errorCount = 0
$errorLocation = @()
$xtSettingsJson = Get-Content "$PSScriptRoot\1-CrossTenantSetup\crossTenantSettings.json"
$xtSettingsPSObj = $xtSettingsJson | ConvertFrom-Json

# Create
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners" -Body $xtSettingsJson

Start-Sleep -Seconds 5

# Verify
$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners/07d2f395-f69c-43ab-88a2-b82f1151042d"
$response.b2bCollaborationInbound.Keys | ForEach-Object {
    $key = $_
    $response.b2bCollaborationInbound.Keys | ForEach-Object {
        if ($response.b2bCollaborationInbound.$key.$_ -ne $xtSettingsPSObj.b2bCollaborationInbound.$key.$_) {
            $errorCount++
            $errorLocation += [PSCustomObject]@{
                "Parent Setting" = "B2B Collaboration Inbound"
                Value   = "$key > $($_): $($response.b2bCollaborationInbound.$key.$_)"
                ExpectedValue = $xtSettingsPSObj.b2bCollaborationInbound.$key.$_
            }
        }
    }
}
$response.inboundTrust.Keys | ForEach-Object {
    if ($response.inboundTrust.$_ -ne $xtSettingsPSObj.inboundTrust.$_) {
        $errorCount++
        $errorLocation += [PSCustomObject]@{
            "Parent Setting" = "Inbound Trust"
            Value   = "$($_): $($response.inboundTrust.$_)"
            ExpectedValue = $xtSettingsPSObj.inboundTrust.$_
        }
    }
}

if ($errorCount -eq 0) {
    Write-Host -ForegroundColor Green "All settings OK"
}
else {
    Write-Host -ForegroundColor Red "Settings incorrect"
    Write-Host -ForegroundColor Red "Errors: $errorCount"
    $errorLocation
}
#endregion

#region Truesec sync app
# Truesec sync app
# Start URL in default browser
Start-Process "https://login.microsoftonline.com/organizations/v2.0/adminconsent?client_id=650c28b2-db2e-4e95-8124-0d3410659df4&scope=https://graph.microsoft.com/.default"

Write-Host -ForegroundColor Yellow "Press Enter once you have consented to the application"
Pause
Write-Host -ForegroundColor Yellow "Pausing for 30 seconds while service principal is created."
Start-Sleep -Seconds 30


$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{650c28b2-db2e-4e95-8124-0d3410659df4}')"

# Hide app
$tags = [PSCustomObject]@{ tags = @("WindowsAzureActiveDirectoryIntegratedApp", "HideApp") } | ConvertTo-Json
$response = Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{650c28b2-db2e-4e95-8124-0d3410659df4}')" -Body $tags

# Add note
$notes = [pscustomobject]@{
    notes = "This application is used to synchronize Truesec SOC users and group memberships."
} | ConvertTo-Json
$response = Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{650c28b2-db2e-4e95-8124-0d3410659df4}')" -Body $notes

# Verify
$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{650c28b2-db2e-4e95-8124-0d3410659df4}')"

if ($response.notes -eq "This application is used to synchronize Truesec SOC users and group memberships." -and `
    $response.tags -contains "HideApp") {
    Write-Host -ForegroundColor Green 'Settings applied successfully to service principal'
} 
else {
    Write-Host -ForegroundColor Red 'Settings not applied successfully to service principal'
}
#endregion

#region Defender API access app
# Defender API access app
# Start URL in default browser
Start-Process "https://login.microsoftonline.com/common/adminconsent?client_id=3bb658be-4eac-4832-baca-65fbde07f547"

Write-Host -ForegroundColor Yellow "Press Enter once you have consented to the application"
Pause
Write-Host -ForegroundColor Yellow "Pausing for 30 seconds while service principal is created."
Start-Sleep -Seconds 30



$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{3bb658be-4eac-4832-baca-65fbde07f547}')"

# Hide app
$tags = [PSCustomObject]@{ tags = @("WindowsAzureActiveDirectoryIntegratedApp", "HideApp") } | ConvertTo-Json
$response = Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{3bb658be-4eac-4832-baca-65fbde07f547}')" -Body $tags

# Add note
$notes = [pscustomobject]@{
    notes = "This application is used by Truesec SOC to fetch security information and update IOCs and custom detection rules."
} | ConvertTo-Json
$response = Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{3bb658be-4eac-4832-baca-65fbde07f547}')" -Body $notes

# Verify
$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{3bb658be-4eac-4832-baca-65fbde07f547}')"

if ($response.notes -eq "This application is used by Truesec SOC to fetch security information and update IOCs and custom detection rules." -and `
        $response.tags -contains "HideApp") {
    Write-Host -ForegroundColor Green 'Settings applied successfully to service principal'
} 
else {
    Write-Host -ForegroundColor Red 'Settings not applied successfully to service principal'
}
#endregion

#region Custom detection app

#Custom detection app
# Start URL in default browser
Start-Process "https://login.microsoftonline.com/common/adminconsent?client_id=5d051ad5-01ff-41de-8336-6962ea18a341"

Write-Host -ForegroundColor Yellow "Press Enter once you have consented to the application"
Pause
Write-Host -ForegroundColor Yellow "Pausing for 30 seconds while service principal is created."
Start-Sleep -Seconds 30


$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{5d051ad5-01ff-41de-8336-6962ea18a341}')"

# Hide app
$tags = [PSCustomObject]@{ tags = @("WindowsAzureActiveDirectoryIntegratedApp", "HideApp") } | ConvertTo-Json
$response = Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{5d051ad5-01ff-41de-8336-6962ea18a341}')" -Body $tags

# Add note
$notes = [pscustomobject]@{
    notes = "This application is used by Truesec SOC to manage custom detection rules in Defender XDR"
} | ConvertTo-Json
$response = Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{5d051ad5-01ff-41de-8336-6962ea18a341}')" -Body $notes

# Verify
$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appid='{5d051ad5-01ff-41de-8336-6962ea18a341}')"

if ($response.notes -eq "This application is used by Truesec SOC to manage custom detection rules in Defender XDR" -and `
        $response.tags -contains "HideApp") {
    Write-Host -ForegroundColor Green 'Settings applied successfully to service principal'
} 
else {
    Write-Host -ForegroundColor Red 'Settings not applied successfully to service principal'
}

#endregion


#region Truesec SOC groups

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
$scopes = 'Group.ReadWrite.All', # Create groups
'Application.Read.All', # Look up ID for ServicePrincipal
'RoleManagement.ReadWrite.Directory', # Assign AAD Roles
'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup' # Privileged role assignment for groups (PIM)

Connect-MgGraph -Scopes $scopes -ContextScope Process

$groupSettings = Get-Content "$PSScriptRoot\3-AADTenantGuestAccess\GroupSettings.json" | ConvertFrom-Json

#Get all active directory role templates
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
        foreach($role in $group.AADRoleId) {
            # Activate role template if it is not activated
            if ($allRoles.roleTemplateId -notcontains $role) {
                $body = [PSCustomObject]@{
                    roleTemplateId = $role
                } | ConvertTo-Json
                Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/directoryRoles" -Body $body
            }
            $uri = "https://graph.microsoft.com/v1.0/directoryRoles/roleTemplateId=$role/members/`$ref"
            $body = [PSCustomObject]@{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($groupResponse.id)"
            } | ConvertTo-Json
            Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body
        }
    }



    # PIM

    if ($group.displayName -eq "Truesec SOC Admins") {
        $adminGroupId = $groupResponse.id
    }
    
    if ($group.displayName -eq "Truesec SOC Admins PIM") {
        # Open link to enable PIM on group
        "https://portal.azure.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/EnablePrivilegedAccess/groupId/$($groupResponse.id)" | clip
        "https://portal.azure.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/EnablePrivilegedAccess/groupId/$($groupResponse.id)"
        Write-Host -ForegroundColor Yellow "URL copied to clipboard."
        Write-Host -ForegroundColor Yellow "Enable PIM on group, press Enter once done"
        Pause
        Write-Host -ForegroundColor Yellow "Waiting 10 seconds for PIM to enable"
        Start-Sleep -Seconds 10

        # Open link to edit group membership PIM rules
        Clear-Host
        
        "https://portal.azure.com/#view/Microsoft_Azure_PIMCommon/ResourceMenuBlade/~/RoleSettings/resourceId/$($groupResponse.id)/resourceType/Security/provider/aadgroup/resourceDisplayName/Truesec%20SOC%20Admins%20PIM/resourceExternalId/$($groupResponse.id)" | clip
        "https://portal.azure.com/#view/Microsoft_Azure_PIMCommon/ResourceMenuBlade/~/RoleSettings/resourceId/$($groupResponse.id)/resourceType/Security/provider/aadgroup/resourceDisplayName/Truesec%20SOC%20Admins%20PIM/resourceExternalId/$($groupResponse.id)"
        Write-Host -ForegroundColor Yellow "URL copied to clipboard."
        Write-Host -ForegroundColor Yellow "Edit the 'Member' role, enable 'Allow permanent eligible assignment' under 'Assignment', then save. Press Enter once done."
        Pause

        #PIM
        #Body
        $body = [PSCustomObject]@{
            accessId      = "member"
            principalId   = $adminGroupId
            groupId       = $groupResponse.id
            action        = 'adminAssign'
            scheduleInfo  = [PSCustomObject] @{
                startDateTime = Get-Date -Date (Get-Date).ToUniversalTime() -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
                expiration    = [PSCustomObject] @{
                    type = "noExpiration" # No expiration
                    #expiration = Get-Date -Date (Get-Date).AddYears(1) -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
                }
            }
            justification = "Truesec setup"
        } | ConvertTo-Json -Depth 4

        Invoke-MgGraphRequest -method POST -uri https://graph.microsoft.com/beta/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests -body $body -ErrorAction SilentlyContinue
    }
}
#endregion