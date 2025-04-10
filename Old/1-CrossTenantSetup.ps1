# Author: Thomas Olenfalk
# Company: Degea AB
# Prerequisites: Global Administrator Role

#Graph
Disconnect-MgGraph #Clear context
$scopes = "Policy.ReadWrite.CrossTenantAccess"
Connect-MgGraph -Scopes $scopes -ContextScope Process

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
