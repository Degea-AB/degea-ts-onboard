# Author: Thomas Olenfalk
# Company: Degea AB
# Prerequisites: Step 2 has been run (sync app) and Global Administrator Role
#Note: PIM portion of Graph API requests are in Beta and may need to be updated

#
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
