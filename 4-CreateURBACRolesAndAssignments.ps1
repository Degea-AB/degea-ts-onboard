<#
.SYNOPSIS
  Apply Microsoft Defender XDR Unified RBAC roles and assignments from per-role JSON files.

.DESCRIPTION
  - Uses raw allowedResourceActions from each role JSON file (no local label mapping).
  - Default behaviour is portal-seeded mode:
      * update existing roleDefinitions if found
      * create/update assignments
      * skip missing roleDefinitions unless -AllowCreateMissing is used
  - This is intentional because some tenants currently return HTTP 500 when POSTing
    /beta/roleManagement/defender/roleDefinitions even with correct scopes/admin rights.
  - Roles folder:
      .\4-URBAC_Settings\roles\*.json

.PARAMETER RunMode
  Validate (default) or Setup

.PARAMETER WhatIf
  Dry-run for Setup mode

.PARAMETER AllowCreateMissing
  If a roleDefinition does not already exist, attempt to create it with Graph.
  Leave this OFF if your tenant still fails on POST /roleManagement/defender/roleDefinitions.

.EXAMPLE
  .\4-CreateURBACRolesAndAssignments.ps1 -RunMode Validate

.EXAMPLE
  .\4-CreateURBACRolesAndAssignments.ps1 -RunMode Setup

.EXAMPLE
  .\4-CreateURBACRolesAndAssignments.ps1 -RunMode Setup -WhatIf

.EXAMPLE
  .\4-CreateURBACRolesAndAssignments.ps1 -RunMode Setup -AllowCreateMissing
#>
#Requires -Version 7.2

[CmdletBinding()]
param(
  [ValidateSet('Validate', 'Setup')]
  [string]$RunMode = 'Validate',

  [switch]$WhatIf,

  [switch]$AllowCreateMissing
)

#region --- Graph bootstrap ---

function Confirm-Graph {
  $authModule = Get-Module -ListAvailable Microsoft.Graph
  if (-not $authModule) {
    Write-Host "Microsoft.Graph module not found. Installing..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
  }

  $scopes = @(
    'RoleManagement.ReadWrite.Defender',
    'RoleManagement.ReadWrite.Directory',
    'Group.Read.All',
    'Directory.ReadWrite.All'
  )

  Connect-MgGraph -Scopes $scopes -UseDeviceCode -ContextScope Process

  $ctx = Get-MgContext
  Write-Host "Connected to Microsoft Graph. Tenant: $($ctx.TenantId)" -ForegroundColor Cyan
  Write-Host ("Scopes: " + ($ctx.Scopes -join ', ')) -ForegroundColor DarkGray
}

function Get-GraphCollection {
  param(
    [Parameter(Mandatory)]
    [string]$Uri
  )

  $items = @()
  $next  = $Uri

  while ($next) {
    $res = Invoke-MgGraphRequest -Method GET -Uri $next
    if ($res.value) {
      $items += @($res.value)
    }
    $next = $res.'@odata.nextLink'
  }

  return ,$items
}

#endregion

#region --- Helpers ---

function Compare-StringSets {
  param(
    [AllowNull()][string[]]$Left,
    [AllowNull()][string[]]$Right
  )

  $l = @($Left  | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
  $r = @($Right | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

  if ($l.Count -ne $r.Count) { return $false }

  for ($i = 0; $i -lt $l.Count; $i++) {
    if ($l[$i] -cne $r[$i]) { return $false }
  }

  return $true
}

function Compare-JsonLike {
  param(
    $Left,
    $Right
  )

  $leftJson  = ($Left  | ConvertTo-Json -Depth 10 -Compress)
  $rightJson = ($Right | ConvertTo-Json -Depth 10 -Compress)

  return ($leftJson -ceq $rightJson)
}

function Resolve-GroupObjectId {
  param(
    [Parameter(Mandatory)]
    [string]$DisplayName
  )

  $escaped = $DisplayName.Replace("'","''")
  $url = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$escaped'"

  $res = Invoke-MgGraphRequest -Method GET -Uri $url

  if (-not $res.value) {
    throw "Group '$DisplayName' not found in Entra ID."
  }

  if ($res.value.Count -gt 1) {
    throw "Multiple groups found with displayName '$DisplayName'. Please ensure uniqueness."
  }

  return $res.value[0].id
}

function Get-RoleDefinitionByDisplayName {
  param(
    [Parameter(Mandatory)]
    [string]$DisplayName
  )

  $escaped = $DisplayName.Replace("'","''")
  $url = "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions?`$filter=displayName eq '$escaped'"

  $res = Invoke-MgGraphRequest -Method GET -Uri $url
  if ($res.value) {
    return $res.value[0]
  }

  return $null
}

function Get-ExistingRoleActions {
  param(
    [Parameter(Mandatory)]
    $RoleDefinition
  )

  $actions = @()

  foreach ($perm in @($RoleDefinition.rolePermissions)) {
    $actions += @($perm.allowedResourceActions)
  }

  return @($actions | Where-Object { $_ } | Sort-Object -Unique)
}

function Ensure-RoleDefinition {
  param(
    [Parameter(Mandatory)]
    [string]$DisplayName,

    [string]$Description,

    [Parameter(Mandatory)]
    [string[]]$AllowedResourceActions
  )

  $existing = Get-RoleDefinitionByDisplayName -DisplayName $DisplayName

  if ($existing) {
    $existingActions = Get-ExistingRoleActions -RoleDefinition $existing
    $needsActionUpdate = -not (Compare-StringSets -Left $existingActions -Right $AllowedResourceActions)
    $needsDescUpdate   = (($existing.description ?? '') -cne ($Description ?? ''))

    if (-not $needsActionUpdate -and -not $needsDescUpdate) {
      Write-Host "RoleDefinition '$DisplayName' already matches desired state." -ForegroundColor Green
      return $existing.id
    }

    Write-Host "Updating roleDefinition '$DisplayName' ($($existing.id))..." -ForegroundColor Cyan

    if (-not $WhatIf) {
      $body = @{
        displayName     = $DisplayName
        description     = $Description
        rolePermissions = @(
          @{
            allowedResourceActions = @($AllowedResourceActions | Sort-Object -Unique)
          }
        )
      } | ConvertTo-Json -Depth 10

      Write-Host $body -ForegroundColor DarkGray

      Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions/$($existing.id)" `
        -Body $body `
        -ContentType "application/json" | Out-Null
    }

    return $existing.id
  }

  if (-not $AllowCreateMissing) {
    Write-Warning "RoleDefinition '$DisplayName' does not exist. Skipping create because -AllowCreateMissing was not used."
    return $null
  }

  Write-Host "Creating roleDefinition '$DisplayName'..." -ForegroundColor Cyan

  if ($WhatIf) {
    return "[WHATIF-$DisplayName]"
  }

  $body = @{
    displayName     = $DisplayName
    description     = $Description
    rolePermissions = @(
      @{
        allowedResourceActions = @($AllowedResourceActions | Sort-Object -Unique)
      }
    )
  } | ConvertTo-Json -Depth 10

  Write-Host $body -ForegroundColor DarkGray

  $created = Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions" `
    -Body $body `
    -ContentType "application/json"

  return $created.id
}

function Ensure-RoleAssignment {
  param(
    [Parameter(Mandatory)]
    [string]$RoleDefinitionId,

    [Parameter(Mandatory)]
    [string]$AssignmentName,

    [Parameter(Mandatory)]
    [string]$GroupObjectId,

    [ValidateSet('All', 'Specific')]
    [string]$DataSources,

    [string[]]$SpecificDataSources
  )

  $desiredAppScopeIds = if ($DataSources -eq 'All') {
    @("/")
  }
  else {
    @($SpecificDataSources)
  }

  $filter = "principalIds/any(p:p eq '$GroupObjectId') and roleDefinitionId eq '$RoleDefinitionId'"
  $url = "https://graph.microsoft.com/beta/roleManagement/defender/roleAssignments?`$filter=$([System.Uri]::EscapeDataString($filter))"

  $existing = Invoke-MgGraphRequest -Method GET -Uri $url

  if ($existing.value) {
    $assignment = $existing.value[0]

    $existingPrincipalIds = @($assignment.principalIds)
    $existingAppScopeIds  = @($assignment.appScopeIds)

    $needsNameUpdate = (($assignment.displayName ?? '') -cne ($AssignmentName ?? ''))
    $needsPrincipalUpdate = -not (Compare-StringSets -Left $existingPrincipalIds -Right @($GroupObjectId))
    $needsScopeUpdate = -not (Compare-StringSets -Left $existingAppScopeIds -Right $desiredAppScopeIds)

    if (-not $needsNameUpdate -and -not $needsPrincipalUpdate -and -not $needsScopeUpdate) {
      Write-Host "Assignment '$AssignmentName' already matches desired state." -ForegroundColor Green
      return
    }

    Write-Host "Deleting existing assignment '$($assignment.displayName)' ($($assignment.id)) before recreate..." -ForegroundColor DarkYellow

    if (-not $WhatIf) {
      Invoke-MgGraphRequest -Method DELETE `
        -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleAssignments/$($assignment.id)" `
        | Out-Null
    }
  }

  Write-Host "Creating assignment '$AssignmentName' (principal=$GroupObjectId)..." -ForegroundColor DarkYellow

  if (-not $WhatIf) {
    $body = @{
      displayName      = $AssignmentName
      roleDefinitionId = $RoleDefinitionId
      principalIds     = @($GroupObjectId)
      appScopeIds      = @($desiredAppScopeIds)
    } | ConvertTo-Json -Depth 10

    Write-Host $body -ForegroundColor DarkGray

    Invoke-MgGraphRequest -Method POST `
      -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleAssignments" `
      -Body $body `
      -ContentType "application/json" | Out-Null
  }
}

#endregion

#region --- Load role files ---

$rolesFolder = Join-Path $PSScriptRoot '4-URBAC_Settings\roles'
if (-not (Test-Path $rolesFolder)) {
  throw "Roles folder not found: $rolesFolder"
}

$roleFiles = Get-ChildItem $rolesFolder -Filter *.json -File
if (-not $roleFiles) {
  throw "No role JSON files found in $rolesFolder"
}

$roleConfigs = foreach ($rf in $roleFiles) {
  try {
    $raw = Get-Content $rf.FullName -Raw | ConvertFrom-Json

    $actions = @($raw.allowedResourceActions | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

    [PSCustomObject]@{
      FilePath               = $rf.FullName
      DisplayName            = $raw.displayName
      Description            = $raw.description
      AllowedResourceActions = $actions
      Assignment             = $raw.assignment
    }
  }
  catch {
    throw "Failed to parse role file '$($rf.Name)': $_"
  }
}

foreach ($rc in $roleConfigs) {
  if (-not $rc.DisplayName) {
    throw "Role file '$($rc.FilePath)' is missing 'displayName'."
  }

  if (-not $rc.AllowedResourceActions -or $rc.AllowedResourceActions.Count -eq 0) {
    throw "Role '$($rc.DisplayName)' is missing 'allowedResourceActions'."
  }

  if (-not $rc.Assignment) {
    throw "Role '$($rc.DisplayName)' is missing 'assignment'."
  }

  if (-not $rc.Assignment.name) {
    throw "Role '$($rc.DisplayName)' is missing assignment.name."
  }

  if (-not $rc.Assignment.dataSources) {
    throw "Role '$($rc.DisplayName)' is missing assignment.dataSources."
  }

  if (-not $rc.Assignment.groupRef) {
    throw "Role '$($rc.DisplayName)' is missing assignment.groupRef."
  }

  if ($rc.Assignment.dataSources -eq 'Specific' -and (-not $rc.Assignment.specificDataSources)) {
    throw "Role '$($rc.DisplayName)' uses Specific dataSources but no assignment.specificDataSources were supplied."
  }
}

#endregion

#region --- Main ---

try {
  Confirm-Graph

  Write-Host "`n=== Validation: Defender URBAC provider ===" -ForegroundColor White
  try {
    $null = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/roleManagement/defender/roleDefinitions?`$top=1"
    Write-Host "Defender URBAC provider reachable." -ForegroundColor Green
  }
  catch {
    throw "Defender URBAC provider is not reachable via Graph. $($_.Exception.Message)"
  }

  Write-Host "`n=== Role plan ($RunMode) ===" -ForegroundColor White

  foreach ($rc in $roleConfigs) {
    Write-Host "Role: $($rc.DisplayName)"
    Write-Host " - From file: $($rc.FilePath)"
    Write-Host " - Actions: $($rc.AllowedResourceActions.Count)"
    Write-Host " - Assignment: $($rc.Assignment.name) | DataSources=$($rc.Assignment.dataSources)"
    Write-Host " - GroupRef: $($rc.Assignment.groupRef)"

    if ($RunMode -eq 'Validate') {
      continue
    }

    $groupObjectId = Resolve-GroupObjectId -DisplayName $rc.Assignment.groupRef
    Write-Host " - PrincipalId: $groupObjectId"

    $roleDefId = Ensure-RoleDefinition `
      -DisplayName $rc.DisplayName `
      -Description $rc.Description `
      -AllowedResourceActions $rc.AllowedResourceActions

    if (-not $roleDefId) {
      Write-Warning "Skipping assignment for '$($rc.DisplayName)' because no roleDefinition ID is available."
      continue
    }

    $dataSources = if ($rc.Assignment.dataSources -eq 'All') { 'All' } else { 'Specific' }

    Ensure-RoleAssignment `
      -RoleDefinitionId $roleDefId `
      -AssignmentName $rc.Assignment.name `
      -GroupObjectId $groupObjectId `
      -DataSources $dataSources `
      -SpecificDataSources $rc.Assignment.specificDataSources
  }

  Write-Host "`n=== Completed. ===" -ForegroundColor Green

  if ($RunMode -eq 'Validate') {
    Write-Host "No changes were made (Validate mode)." -ForegroundColor Yellow
  }
  elseif ($WhatIf) {
    Write-Host "WhatIf: no mutations executed." -ForegroundColor Yellow
  }
}
catch {
  Write-Error $_
}

#endregion