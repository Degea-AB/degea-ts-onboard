# This script updates the URBAC role reference file with the latest roles and permissions from the URBAC settings file.
# Update a tenant with new URBAC role settings, then export the roles from the permissions page and input the file into the script.

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

$activatedWorkloads | Set-Content .\workloads.txt
$roles = $content[0..($startRow - 2)] | Where-Object { $_ -ne "" } | Select-Object -Skip 1 | ConvertFrom-Csv -Delimiter ','
$roles | Select-Object "Role name",@{l="Permissions";e={($_."Permissions" -split ';').Trim()}},"Assigned users and groups" | ConvertTo-Json -Depth 4 | Set-content .\urbacroles.json