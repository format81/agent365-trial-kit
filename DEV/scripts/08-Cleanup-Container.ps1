<#
.SYNOPSIS
    Removes the container resources created by 07-Deploy-Container.ps1:
    the Web App for Containers, its App Service Plan, and the Azure Container
    Registry.

.DESCRIPTION
    By default reads last-container-deploy.json (written by the deploy script)
    to know exactly what to delete. You can override any name explicitly.

    NOTE: This does NOT remove Agent 365 blueprint/instance state. Use
    04-Cleanup.ps1 for the Agent 365 side.

.PARAMETER AppName
    Web App name. Defaults to the value in last-container-deploy.json.

.PARAMETER PlanName
    App Service Plan name. Defaults to the state file.

.PARAMETER AcrName
    Azure Container Registry name. Defaults to the state file.

.PARAMETER KeepAcr
    Do not delete the ACR (useful if it is shared/reused).

.PARAMETER Force
    Do not prompt for confirmation.

.PARAMETER DryRun
    Print what would be deleted without deleting.

.EXAMPLE
    .\08-Cleanup-Container.ps1 -Force

.EXAMPLE
    .\08-Cleanup-Container.ps1 -AppName app-x-ctr-123 -PlanName asp-x-ctr -AcrName acrx123 -Force
#>
[CmdletBinding()]
param(
    [string]$AppName,
    [string]$PlanName,
    [string]$AcrName,
    [switch]$KeepAcr,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

if (-not (Test-Command "az")) {
    Write-ErrLine "Azure CLI (az) not found. Run .\00-Prerequisites.ps1 first."
    exit 1
}

$config = Read-A365Config
$rg    = if ($config) { $config.resourceGroup } else { $null }
$subId = if ($config) { $config.subscriptionId } else { $null }

$statePath = Join-Path $PSScriptRoot "last-container-deploy.json"
$state = $null
if (Test-Path $statePath) {
    $state = Get-Content $statePath -Raw | ConvertFrom-Json
    if (-not $AppName)  { $AppName = $state.appName }
    if (-not $PlanName) { $PlanName = $state.planName }
    if (-not $AcrName)  { $AcrName = $state.acrName }
    if (-not $rg)       { $rg = $state.resourceGroup }
    if (-not $subId)    { $subId = $state.subscriptionId }
}

if (-not $rg) {
    Write-ErrLine "No resource group found (a365.config.json / state file missing). Pass names explicitly."
    exit 1
}
if (-not ($AppName -or $PlanName -or $AcrName)) {
    Write-ErrLine "Nothing to delete: no app/plan/acr resolved. Pass -AppName/-PlanName/-AcrName."
    exit 1
}

Write-Step "Container cleanup plan (resource group: $rg)"
Write-Host "    Web App          : $(if ($AppName) { $AppName } else { '(none)' })"
Write-Host "    App Service Plan : $(if ($PlanName) { $PlanName } else { '(none)' })"
Write-Host "    ACR              : $(if ($AcrName -and -not $KeepAcr) { $AcrName } else { '(kept/none)' })"
Write-Host ""

if ($DryRun) { Write-WarnLine "Dry run: nothing deleted."; return }

if (-not $Force) {
    $answer = Read-Host "Delete these resources? (y/n)"
    if ($answer -notin @("y", "Y")) { Write-WarnLine "Aborted."; return }
}

if ($subId) { Invoke-Native "az" @("account", "set", "--subscription", $subId) }

function Remove-IfExists {
    param([string]$Kind, [string[]]$ShowArgs, [string[]]$DeleteArgs, [string]$Name)
    if (-not $Name) { return }
    $exists = az @ShowArgs 2>$null
    if ($exists) {
        Write-Step "Deleting $Kind '$Name'"
        Invoke-Native "az" $DeleteArgs
        Write-Ok "$Kind '$Name' deleted."
    }
    else {
        Write-WarnLine "$Kind '$Name' not found (already removed?)."
    }
}

# Web App first (releases the plan), then plan, then ACR.
Remove-IfExists -Kind "Web App" -Name $AppName `
    -ShowArgs @("webapp", "show", "-n", $AppName, "-g", $rg, "--query", "name", "-o", "tsv") `
    -DeleteArgs @("webapp", "delete", "-n", $AppName, "-g", $rg)

Remove-IfExists -Kind "App Service Plan" -Name $PlanName `
    -ShowArgs @("appservice", "plan", "show", "-n", $PlanName, "-g", $rg, "--query", "name", "-o", "tsv") `
    -DeleteArgs @("appservice", "plan", "delete", "-n", $PlanName, "-g", $rg, "--yes")

if (-not $KeepAcr) {
    Remove-IfExists -Kind "Container Registry" -Name $AcrName `
        -ShowArgs @("acr", "show", "-n", $AcrName, "-g", $rg, "--query", "name", "-o", "tsv") `
        -DeleteArgs @("acr", "delete", "-n", $AcrName, "-g", $rg, "--yes")
}

if (Test-Path $statePath) { Remove-Item $statePath -Force }
Write-Host ""
Write-Ok "Container cleanup complete."
