# Author: Thomas Olenfalk
# Company: Degea AB
# Prerequisites: Global Administrator Role
# Start URL in default browser
Start-Process "https://login.microsoftonline.com/common/adminconsent?client_id=5d051ad5-01ff-41de-8336-6962ea18a341"

Write-Host -ForegroundColor Yellow "Press Enter once you have consented to the application"
Pause
Write-Host -ForegroundColor Yellow "Pausing for 30 seconds while service principal is created."
Start-Sleep -Seconds 30

#Graph
Disconnect-MgGraph
$scopes = "Application.ReadWrite.All"
Connect-MgGraph -Scopes $scopes -ContextScope Process

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