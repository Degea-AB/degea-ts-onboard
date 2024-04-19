# Author: Thomas Olenfalk
# Company: Degea AB
# Prerequisites: Global Administrator Role
# Start URL in default browser
Start-Process "https://login.microsoftonline.com/common/adminconsent?client_id=3bb658be-4eac-4832-baca-65fbde07f547"

Write-Host -ForegroundColor Yellow "Press Enter once you have consented to the application"
Pause
Write-Host -ForegroundColor Yellow "Pausing for 30 seconds while service principal is created."
Start-Sleep -Seconds 30

#Graph
Disconnect-MgGraph
$scopes = "Application.ReadWrite.All"
Connect-MgGraph -Scopes $scopes -ContextScope Process

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