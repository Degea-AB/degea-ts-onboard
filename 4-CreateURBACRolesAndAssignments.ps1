<#
.SYNOPSIS
  Apply Microsoft Defender XDR Unified RBAC roles & assignments from per-role JSON files.
  Author: Thomas Olenfalk (@ThomasOlenfalk) - Degea AB

.DESCRIPTION
  - Validates ONLY the Microsoft.Graph SDK (no Microsoft.Graph.Beta required).
  - Loads config via $PSScriptRoot:
      Roles: .\4-URBAC_Settings\roles\*.json
      Group map: .\3-AADTenantGuestAccess\GroupSettings.json
  - Run modes:
      -RunMode Validate  : Parse/resolve/validate only (no changes).
      -RunMode Setup     : Create/Update role definitions + assignments.
  - Best-effort workload validation: checks Defender provider reachability + capability action prefixes.
    (Microsoft has no public API for the actual workload toggle state; verify toggles in portal per MS Learn.)

.PARAMETER RunMode
  'Validate' (default) or 'Setup'

.PARAMETER WhatIf
  Adds dry-run behavior even in Setup mode.

.EXAMPLE
    # Validate only (no changes)
    .\4-CreateURBACRolesAndAssignments.ps1 -RunMode Validate
    
    # Apply roles and assignments as defined in the JSON files
    .\4-CreateURBACRolesAndAssignments.ps1 -RunMode Setup

    # Apply roles and assignments in dry-run mode (no actual mutations)
    .\4-CreateURBACRolesAndAssignments.ps1 -RunMode Setup -WhatIf

.REQUIREMENTS
  - Microsoft.Graph SDK (Connect-MgGraph, Invoke-MgGraphRequest).
  - Graph delegated scopes (interactive): RoleManagement.ReadWrite.Defender, Group.Read.All, Directory.Read.All
    or application permission equivalent.

.REFERENCES
  - Unified RBAC model & activation: https://learn.microsoft.com/defender-xdr/manage-rbac
  - Activate workloads: https://learn.microsoft.com/defender-xdr/activate-defender-rbac
#>

[CmdletBinding()]
param(
  [ValidateSet('Validate', 'Setup')]
  [string]$RunMode = 'Validate',
  [switch]$WhatIf
)

#region --- Graph bootstrap (no Beta module required) ---
function Get-DefenderActionCatalog {
  # Returns a HashSet[string] of all allowedResourceActions discoverable in this tenant
  $catalog = New-Object System.Collections.Generic.HashSet[string]
  $uris = @(
    "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions"
  )
  foreach ($uri in $uris) {
    try {
      $res = Invoke-MgGraphRequest -Method GET -Uri $uri
      foreach ($def in $res.value) {
        foreach ($perm in $def.permissions) {
          foreach ($act in $perm.allowedResourceActions) {
            if ($act) { [void]$catalog.Add($act) }
          }
        }
      }
    }
    catch {
      # Non-fatal; continue so we at least get built-ins
    }
  }
  return $catalog
}

function Test-AllowedActions {
  param(
    [string[]]$Actions,
    $CatalogHashSet
  )
  $invalid = @()
  foreach ($a in $Actions) {
    if (-not $CatalogHashSet.Contains($a)) { $invalid += $a }
  }
  return , $invalid
}

function New-CommonFixes {
  param([string[]]$InvalidActions)

  $suggestions = @()

  # Common mismatch: Raw data uses "rawdata", not "secops"
  foreach ($a in $InvalidActions) {
    if ($a -like "microsoft.xdr/secops/email/*/read") {
      $suggestions += $a.Replace("secops/email", "rawdata/email")
    }
  }

  # Common mismatch: "securitydatabasics" vs "securitydata"
  foreach ($a in $InvalidActions) {
    if ($a -like "microsoft.xdr/secops/securitydatabasics/*") {
      $suggestions += $a.Replace("securitydatabasics", "securitydata")
    }
  }

  $suggestions | Select-Object -Unique
}

function Confirm-Graph {
  $authModule = Get-Module -ListAvailable Microsoft.Graph
  if (-not $authModule) {
    Write-Host "Microsoft.Graph module not found. Installing..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
  }

  # Required scopes
  $scopes = @(
    'RoleManagement.ReadWrite.Defender',
    'Group.Read.All',
    'Directory.Read.All'
  )
  if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes $scopes
  }
  else {
    # Ensure our current token has the scopes; if not, reconnect.
    $ctx = Get-MgContext
    $missing = $scopes | Where-Object { $ctx.Scopes -notcontains $_ }
    if ($missing) {
      Disconnect-MgGraph -ErrorAction SilentlyContinue
      Connect-MgGraph -Scopes $scopes
    }
  }
  Write-Host "Connected to Microsoft Graph. Tenant: $((Get-MgContext).TenantId)" -ForegroundColor Cyan
}
#endregion

#region --- Paths & config loading ---
$rolesFolder = Join-Path $PSScriptRoot '4-URBAC_Settings\roles'
$groupMapPath = Join-Path $PSScriptRoot '3-AADTenantGuestAccess\GroupSettings.json'

if (-not (Test-Path $rolesFolder)) { throw "Roles folder not found: $rolesFolder" }
if (-not (Test-Path $groupMapPath)) { throw "Group settings file not found: $groupMapPath" }

# Load group settings (as provided)
$groupSettingsRaw = Get-Content $groupMapPath -Raw | ConvertFrom-Json
$groupSettings = @($groupSettingsRaw.groups)  # expect .groups[] with displayName and URBACRoles
if (-not $groupSettings) { throw "No 'groups' found in $groupMapPath" }

# Load role files
$roleFiles = Get-ChildItem $rolesFolder -Filter *.json -File
if (-not $roleFiles) { throw "No role JSON files found in $rolesFolder" }

$roleConfigs = foreach ($rf in $roleFiles) {
  try {
    $r = Get-Content $rf.FullName -Raw | ConvertFrom-Json
    [PSCustomObject]@{
      FilePath    = $rf.FullName
      DisplayName = $r.displayName
      Description = $r.description
      Permissions = $r.permissions
      Assignment  = $r.assignment
    }
  }
  catch {
    throw "Failed to parse role file $($rf.Name): $_"
  }
}

# Basic validation
foreach ($rc in $roleConfigs) {
  if (-not $rc.DisplayName) { throw "Role file '$($rc.FilePath)' missing 'displayName'." }
  if (-not $rc.Assignment -or -not $rc.Assignment.groupRef) {
    throw "Role '$($rc.DisplayName)' is missing assignment.groupRef"
  }
}
#endregion

#region --- Permission label mapping (from SOP wizard) ---
# These map UI labels (as in the SOP screenshots) to Defender URBAC action strings.
# Keep aligned to your SOP revisions (4-TSD SOP - 04 Onboard Microsoft 365 Defender Unified RBAC.pdf).
$permMap = @{
  # Security operations
  'Security data basics (read)'                         = 'microsoft.xdr/secops/securitydatabasics/read'
  'Alerts (manage)'                                     = 'microsoft.xdr/secops/alerts/manage'
  'Response (manage)'                                   = 'microsoft.xdr/secops/response/manage'
  'Basic live response (manage)'                        = 'microsoft.xdr/secops/liveresponse/basic/manage'
  'Advanced live response (manage)'                     = 'microsoft.xdr/secops/liveresponse/advanced/manage'
  'File collection (manage)'                            = 'microsoft.xdr/secops/filecollection/manage'
  'Email & collaboration quarantine (manage)'           = 'microsoft.xdr/secops/email/quarantine/manage'
  'Email & collaboration advanced actions (manage)'     = 'microsoft.xdr/secops/email/advanced/manage'

  # Raw data (Email & collaboration)
  'Email & collaboration metadata (read)'               = 'microsoft.xdr/secops/email/metadata/read'
  'Email & collaboration content (read)'                = 'microsoft.xdr/secops/email/content/read'

  # Security posture
  'Vulnerability management (read)'                     = 'microsoft.xdr/securityposture/vulnerability/read'
  'Exception handling (manage)'                         = 'microsoft.xdr/securityposture/exception/manage'
  'Remediation handling (manage)'                       = 'microsoft.xdr/securityposture/remediation/manage'
  'Secure Score (read)'                                 = 'microsoft.xdr/securityposture/securescore/read'
  'Secure Score (manage)'                               = 'microsoft.xdr/securityposture/securescore/manage'

  # Authorization and settings
  'Authorization (Read-only)'                           = 'microsoft.xdr/configuration/authorization/read'
  'Authorization (Read and manage)'                     = 'microsoft.xdr/configuration/authorization/manage'
  'Security settings → Detection tuning (manage)'       = 'microsoft.xdr/configuration/securitysettings/detectiontuning/manage'
  'Security settings → Core security settings (read)'   = 'microsoft.xdr/configuration/securitysettings/core/read'
  'Security settings → Core security settings (manage)' = 'microsoft.xdr/configuration/securitysettings/core/manage'
  'System settings (Read-only)'                         = 'microsoft.xdr/configuration/systemsettings/read'
  'System settings (Read and manage)'                   = 'microsoft.xdr/configuration/systemsettings/manage'
}
#endregion

#region --- Helper functions ---
function Resolve-UrbacActions {
  param([object]$Permissions)

  # Convert PSCustomObject → Hashtable safely
  if ($Permissions -is [pscustomobject]) {
    $tmp = @{}
    foreach ($prop in $Permissions.PSObject.Properties) {
      $tmp[$prop.Name] = $prop.Value
    }
    $Permissions = $tmp
  }

  if ($Permissions -isnot [hashtable]) {
    throw "Permissions block is not a Hashtable or PSCustomObject."
  }

  $actions = New-Object System.Collections.Generic.List[string]

  foreach ($group in $Permissions.Keys) {
    foreach ($label in $Permissions[$group]) {
      if (-not $permMap.ContainsKey($label)) {
        throw "Unknown permission label '$label' - add it to the mapping table."
      }
      $actions.Add($permMap[$label])
    }
  }

  return ($actions | Select-Object -Unique)
}

function Resolve-GroupObjectId {
  param([string]$DisplayName)

  # Prefer v1.0 for groups
  $url = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$($DisplayName.Replace("'","''"))'"
  $res = Invoke-MgGraphRequest -Method GET -Uri $url
  if (-not $res.value) { throw "Group '$DisplayName' not found in Entra ID." }
  if ($res.value.Count -gt 1) { throw "Multiple groups found with displayName '$DisplayName'. Please ensure uniqueness." }
  return $res.value[0].id
}

function Confirm-RoleDefinition {
  param(
    [string]$DisplayName,
    [string]$Description,
    [string[]]$AllowedResourceActions
  )

  $findUrl = "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions?`$filter=displayName eq '$($DisplayName.Replace("'","''"))'"
  $existing = Invoke-MgGraphRequest -Method GET -Uri $findUrl

  if ($existing.value) {
    $defId = $existing.value[0].id
    Write-Host "Updating roleDefinition '$DisplayName' ($defId)..." -ForegroundColor Cyan
    if (-not $WhatIf) {
      $body = @{
        description = $Description
        permissions = @(@{ allowedResourceActions = $AllowedResourceActions })
      } | ConvertTo-Json -Depth 5
      Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions/$defId" `
        -Body $body -ContentType "application/json"
    }
    return $defId
  }
  else {
    Write-Host "Creating roleDefinition '$DisplayName'..." -ForegroundColor Cyan
    if ($WhatIf) { return "[WHATIF-$DisplayName]" }
    $body = @{
      displayName = $DisplayName
      description = $Description
      isBuiltIn   = $false
      permissions = @(@{ allowedResourceActions = $AllowedResourceActions })
    } | ConvertTo-Json -Depth 5
    
    Write-Host $body -ForegroundColor Gray

    $created = Invoke-MgGraphRequest -Method POST `
      -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions" `
      -Body $body -ContentType "application/json"
    return $created.id
  }
}

function Confirm-RoleAssignment {
  param(
    [string]$RoleDefinitionId,
    [string]$AssignmentName,
    [string]$GroupObjectId,
    [ValidateSet('All', 'Specific')]
    [string]$DataSources,
    [string[]]$SpecificDataSources
  )

  $scope = if ($DataSources -eq 'All') { @{ type = "allDataSources" } } else { @{ type = "selectedDataSources"; values = $SpecificDataSources } }

  $filter = "principalId eq '$GroupObjectId' and roleDefinitionId eq '$RoleDefinitionId'"
  $url = "https://graph.microsoft.com/beta/roleManagement/defender/roleAssignments?`$filter=$($filter.Replace(' ','%20'))"
  $exists = Invoke-MgGraphRequest -Method GET -Uri $url

  if ($exists.value) {
    $assignId = $exists.value[0].id
    Write-Host "Updating assignment '$AssignmentName' (principal=$GroupObjectId)..." -ForegroundColor DarkYellow
    if (-not $WhatIf) {
      $body = @{
        displayName      = $AssignmentName
        roleDefinitionId = $RoleDefinitionId
        principalId      = $GroupObjectId
        scope            = $scope
      } | ConvertTo-Json -Depth 5
      Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleAssignments/$assignId" `
        -Body $body -ContentType "application/json"
    }
  }
  else {
    Write-Host "Creating assignment '$AssignmentName' (principal=$GroupObjectId)..." -ForegroundColor DarkYellow
    if (-not $WhatIf) {
      $body = @{
        displayName      = $AssignmentName
        roleDefinitionId = $RoleDefinitionId
        principalId      = $GroupObjectId
        scope            = $scope
      } | ConvertTo-Json -Depth 5
      Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleAssignments" `
        -Body $body -ContentType "application/json"
    }
  }
}

function Test-UrbacCapabilities {
  # Best-effort capability check: ensure action categories we depend on exist *somewhere* in the tenant.
  # NOTE: This is NOT a guarantee that workload toggles are active/enforced.
  $needPrefixes = @(
    'microsoft.xdr/secops/liveresponse/',       # Endpoints (Live Response)
    'microsoft.xdr/secops/email/',              # Email & collaboration
    'microsoft.xdr/securityposture/securescore/'# Secure Score
  )

  $defs = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions?`$top=50"
  if (-not $defs.value) { return @{ ok = $false; missing = $needPrefixes } }

  $have = New-Object System.Collections.Generic.HashSet[string]
  foreach ($d in $defs.value) {
    foreach ($perm in $d.permissions) {
      foreach ($act in $perm.allowedResourceActions) {
        foreach ($pfx in $needPrefixes) {
          if ($act -like "$pfx*") { [void]$have.Add($pfx) }
        }
      }
    }
  }

  $missing = $needPrefixes | Where-Object { -not $have.Contains($_) }
  return @{
    ok      = ($missing.Count -eq 0)
    missing = $missing
  }
}
#endregion

#region --- Main ---
try {
  Confirm-Graph

  Write-Host "`n=== Validation: Defender URBAC provider ===" -ForegroundColor White
  try {
    $res = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions?`$top=1"
    $providerOK = $true
  }
  catch {
    $providerOK = $false
  }
  if (-not $providerOK) {
    Write-Warning "Defender URBAC provider is not reachable via Graph. Ensure URBAC is available and that your account has the right permissions."
    if ($RunMode -eq 'Setup') { throw "Cannot proceed without Defender URBAC provider." }
  }
  else {
    Write-Host "Defender URBAC provider reachable." -ForegroundColor Green
  }

  Write-Host "`n=== Validation: Workload capabilities (best-effort) ===" -ForegroundColor White
  $caps = Test-UrbacCapabilities
  if (-not $caps.ok) {
    Write-Warning ("Could not confirm all capability prefixes: missing -> " + ($caps.missing -join ', '))
    Write-Host "Manually verify workload toggles in the Defender portal: Settings → Microsoft Defender XDR → Permissions and roles → Activate workloads." -ForegroundColor Yellow
    # Reference: MS Learn activation guidance
    # https://learn.microsoft.com/defender-xdr/activate-defender-rbac
  }
  else {
    Write-Host "Capability prefixes present for Endpoints, Email & collaboration, and Secure Score." -ForegroundColor Green
  }

  Write-Host "`n=== Resolving Group ObjectIds from GroupSettings.json ===" -ForegroundColor White
  # Build a map: URBACRoles -> group objectId(s)
  $roleToGroupIds = @{}
  foreach ($g in $groupSettings) {
    if ($g.URBACRoles) {
      $rid = Resolve-GroupObjectId -DisplayName $g.displayName
      if (-not $roleToGroupIds.ContainsKey($g.URBACRoles)) { $roleToGroupIds[$g.URBACRoles] = @() }
      $roleToGroupIds[$g.URBACRoles] += $rid
      Write-Host "Resolved '$($g.displayName)' -> $rid (URBACRoles='$($g.URBACRoles)')" -ForegroundColor Gray
    }
  }

  Write-Host "`n=== Role plan (" + $RunMode + ") ===" -ForegroundColor White
  foreach ($rc in $roleConfigs) {
    $actions = Resolve-UrbacActions -Permissions $rc.Permissions

    # Assignment mapping
    $roleKey = $rc.DisplayName
    $principalIds = @()
    if ($roleToGroupIds.ContainsKey($roleKey)) {
      $principalIds = $roleToGroupIds[$roleKey] | Select-Object -Unique
    }
    else {
      Write-Warning "No group entry in GroupSettings.json with URBACRoles='$roleKey'. This role will have no assignment unless you add it."
    }

    Write-Host ("Role: " + $rc.DisplayName)
    Write-Host (" - From file: " + $rc.FilePath)
    Write-Host (" - Actions: " + $actions.Count)
    Write-Host (" - Assignment: " + $rc.Assignment.name + " | DataSources=" + $rc.Assignment.dataSources)
    if ($principalIds) {
      foreach ($prid in $principalIds) { Write-Host ("   - PrincipalId: " + $prid) }
    }

    if ($RunMode -eq 'Setup') {
      # Build catalog once (outside the per-role loop is better; do it once at the top after connecting)
      if (-not $script:ActionCatalog) {
        Write-Host "Building tenant Defender URBAC action catalog..." -ForegroundColor White
        $script:ActionCatalog = Get-DefenderActionCatalog
        Write-Host ("Catalog size: {0} actions" -f $script:ActionCatalog.Count) -ForegroundColor Gray
      }

      # ... inside the per-role loop after you've built $actions:
      $invalid = Test-AllowedActions -Actions $actions -CatalogHashSet $script:ActionCatalog
      # If $invalid is empty, set it to empty array to avoid null issues
      if (-not $invalid) { $invalid = @() }
      if ($invalid.Count -gt 0) {
        Write-Error "Aborting: Invalid allowedResourceActions detected:"
        $invalid | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }

        $hints = New-CommonFixes -InvalidActions $invalid
        if ($hints) {
          Write-Host "`nSuggestions based on common mismatches (verify against catalog):" -ForegroundColor Yellow
          $hints | ForEach-Object { Write-Host "  → $_" -ForegroundColor Yellow }
        }
        else {
          Write-Host "`nTIP: Create a one-off role in the portal with the desired checkboxes," `
            "then GET its roleDefinition to see the exact allowedResourceActions for your tenant." `
            -ForegroundColor Yellow
        }

        if ($RunMode -eq 'Setup') { throw "Invalid actions present; fix mapping and rerun." }
        else { return }  # In Validate mode, just stop here
      }

      $roleDefId = Confirm-RoleDefinition -DisplayName $rc.DisplayName -Description $rc.Description -AllowedResourceActions $actions
      foreach ($prid in $principalIds) {
        $ds = ($rc.Assignment.dataSources -eq 'All') ? 'All' : 'Specific'
        Confirm-RoleAssignment -RoleDefinitionId $roleDefId `
          -AssignmentName $rc.Assignment.name `
          -GroupObjectId $prid `
          -DataSources $ds `
          -SpecificDataSources $rc.Assignment.specificDataSources
      }
    }
  }

  Write-Host "`n=== Completed. ===" -ForegroundColor Green
  if ($RunMode -eq 'Validate') {
    Write-Host "No changes were made (Validate mode). Use -RunMode Setup to apply." -ForegroundColor Yellow
  }
  elseif ($WhatIf) {
    Write-Host "WhatIf: no mutations executed." -ForegroundColor Yellow
  }

}
catch {
  Write-Error $_
}
#endregion