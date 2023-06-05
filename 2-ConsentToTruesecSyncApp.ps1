# Author: Thomas Olenfalk
# Company: Degea AB
# Prerequisites: Global Administrator Role

# Start URL in default browser
Start-Process "https://login.microsoftonline.com/organizations/v2.0/adminconsent?client_id=650c28b2-db2e-4e95-8124-0d3410659df4&scope=https://graph.microsoft.com/.default"

Write-Host -ForegroundColor Yellow "Press Enter once you have consented to the application"
Pause
Write-Host -ForegroundColor Yellow "Pausing for 30 seconds while service principal is created."
Start-Sleep -Seconds 30

#Graph
Disconnect-MgGraph
$scopes = "Application.ReadWrite.All"
Connect-MgGraph -Scopes $scopes

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