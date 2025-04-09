# Run this script after setting up the URBAC roles and assignments in the URBAC settings
# This script will validate the URBAC roles and assignments against the URBAC settings
# Export the roles from the permissions page and input the file into the script

# file:
$file = Read-Host "Enter the path to the URBAC settings file (e.g. C:\temp\URBACSettings.csv)"
if (-not (Test-Path $file)) {
    Write-Host -ForegroundColor Red "File not found: $file"
    exit
}

#find row with "Activation status", validate workloads
$content = Get-Content $file
$startRow = $content.IndexOf("Activation status") + 1
$activatedWorkloads = $content[$startRow..($content.Length - 1)]

$rbacWorkloads = Get-Content "$PSScriptRoot\4-URBAC_Settings\workloads.txt"
$urbacRoleReference = Get-Content "$PSScriptRoot\4-URBAC_Settings\urbacroles.json" | ConvertFrom-Json

$rbacWorkloads | ForEach-Object {
    if ($activatedWorkloads -notcontains $_) {
        Write-Host -ForegroundColor Red "Workload $(($_ -split '\,')[0]) is not activated in the URBAC settings"
    }
    else {
        Write-Host -ForegroundColor Green "Workload $(($_ -split '\,')[0]) is activated in the URBAC settings"
    }
}

# select the other rows. skip 0 and empty rows before "Activation status"
$roles = $content[0..($startRow - 2)] | Where-Object { $_ -ne "" } | Select-Object -Skip 1 | ConvertFrom-Csv -Delimiter ','
$roles = $roles | Select-Object "Role name", @{l = "Permissions"; e = { ($_."Permissions" -split ';').Trim() } }, "Assigned users and groups"

# Go through reference role assignments, check if they exist in the tenant
foreach($roleassignment in $urbacRoleReference) {
    Write-Host ""
    Write-Host ""
    Write-Host -ForegroundColor Yellow "Validating role $((($roleassignment."Role name") -split '\,')[0])"
    $errorCount = 0
    $tenantRoleAssignment = $roles | Where-Object { $_."Role name" -eq $roleassignment."Role name" }
    if ($null -eq $tenantRoleAssignment) {
        Write-Host -ForegroundColor Red "Role $((($roleassignment."Role name") -split '\,')[0]) is not found in the tenant"
    }
    else {
        Write-Host -ForegroundColor Green "Role $((($roleassignment."Role name") -split '\,')[0]) is found in the tenant"
        $tenantPermissions = $tenantRoleAssignment."Permissions" | ForEach-Object { $_.Trim() }
        $referencePermissions = $roleassignment.permissions | ForEach-Object { $_.Trim() }
        foreach ($permission in $referencePermissions) {
            if ($tenantPermissions -notcontains $permission) {
                Write-Host -ForegroundColor Red "    Permission $permission is not found in the tenant for role $((($roleassignment."Role name") -split '\,')[0])"
                $errorCount++
            }
            
        }
        if ($errorCount -eq 0) {
            Write-Host -ForegroundColor Green "    All permissions are found in the tenant for role $((($roleassignment."Role name") -split '\,')[0])"
        }
        $tenantAssignedUsers = $tenantRoleAssignment."Assigned users and groups" | ForEach-Object { $_.Trim() }
        $referenceAssignedUsers = $roleassignment."Assigned users and groups" | ForEach-Object { $_.Trim() }
        foreach ($assignedUser in $referenceAssignedUsers) {
            if ($tenantAssignedUsers -notcontains $assignedUser) {
                Write-Host -ForegroundColor Red "    Assigned user $assignedUser is not found in the tenant for role $((($roleassignment."Role name") -split '\,')[0])"
                $errorCount++
            }
        }
        if ($errorCount -eq 0) {
            Write-Host -ForegroundColor Green "    All assigned users are found in the tenant for role $((($roleassignment."Role name") -split '\,')[0])"
        }
    }
}