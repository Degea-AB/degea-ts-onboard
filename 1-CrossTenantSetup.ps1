# Author: Thomas Olenfalk
# Company: Degea AB
# Prerequisites: Global Administrator Role

#Graph
Disconnect-MgGraph #Clear context
$scopes = "Policy.ReadWrite.CrossTenantAccess"
Connect-MgGraph -Scopes $scopes

$xtSettingsJson = Get-Content "$PSScriptRoot\1-CrossTenantSetup\crossTenantSettings.json"
$xtSettingsPSObj = $xtSettingsJson | ConvertFrom-Json

# Create
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners" -Body $xtSettingsJson

Start-Sleep -Seconds 5

# Verify
$response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners/07d2f395-f69c-43ab-88a2-b82f1151042d"
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
