<#
.SYNOPSIS
    Removes the Azure resources created by Deploy-McpToAca.ps1 (Container App,
    Container Apps environment, and Azure Container Registry) - or the entire
    resource group.

.DESCRIPTION
    By default the script reads last-deploy.json (written by the deploy script)
    to discover exactly what to delete. You can also pass the names explicitly.

    Two modes:
      * Targeted (default): deletes the Container App, then the environment,
        then the ACR. Leaves the resource group in place.
      * -DeleteResourceGroup: deletes the whole resource group in one shot
        (use only if the RG is dedicated to this demo).

    AGENT 365 NOTE: Microsoft does not currently support deleting a BYO MCP
    server registration. To retire the tool, open the Microsoft 365 admin
    center -> Agents -> Tools -> Registry, select the server, and choose
    'Block'. Blocked servers cannot be invoked at runtime on any client
    surface. This script prints that reminder at the end.

.PARAMETER ResourceGroup
    Resource group to clean. Falls back to last-deploy.json.

.PARAMETER AppName
    Container App to delete. Falls back to last-deploy.json.

.PARAMETER EnvName
    Container Apps environment to delete. Falls back to last-deploy.json.

.PARAMETER AcrName
    Azure Container Registry to delete. Falls back to last-deploy.json.

.PARAMETER SubscriptionId
    Subscription to target. Falls back to last-deploy.json / current context.

.PARAMETER DeleteResourceGroup
    Delete the entire resource group instead of individual resources.

.PARAMETER Force
    Do not prompt for confirmation.

.EXAMPLE
    ./Cleanup-McpAca.ps1

.EXAMPLE
    ./Cleanup-McpAca.ps1 -DeleteResourceGroup -Force

.EXAMPLE
    ./Cleanup-McpAca.ps1 -ResourceGroup rg-prism-mcp -AppName ca-prism-employee-mcp -EnvName cae-prism-mcp -AcrName acrprismmcpab12cd
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup,
    [string]$AppName,
    [string]$EnvName,
    [string]$AcrName,
    [string]$SubscriptionId,
    [switch]$DeleteResourceGroup,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

if (-not (Test-Command "az")) {
    throw "Azure CLI (az) not found."
}

# Fill any missing parameters from the saved deployment state.
$state = Read-DeployState
if ($state) {
    Write-Ok "Loaded last-deploy.json."
    if (-not $ResourceGroup)  { $ResourceGroup  = $state.resourceGroup }
    if (-not $AppName)        { $AppName        = $state.appName }
    if (-not $EnvName)        { $EnvName        = $state.envName }
    if (-not $AcrName)        { $AcrName        = $state.acrName }
    if (-not $SubscriptionId) { $SubscriptionId = $state.subscriptionId }
}

if (-not $ResourceGroup) {
    throw "No resource group provided and no last-deploy.json found. Pass -ResourceGroup."
}

if ($SubscriptionId) {
    Invoke-Native "az" @("account", "set", "--subscription", $SubscriptionId)
}

Write-Step "Cleanup plan"
Write-Host "    Subscription   : $SubscriptionId"
Write-Host "    Resource group : $ResourceGroup"
if ($DeleteResourceGroup) {
    Write-Host "    Action         : DELETE ENTIRE RESOURCE GROUP" -ForegroundColor Yellow
}
else {
    Write-Host "    Container App  : $AppName"
    Write-Host "    Environment    : $EnvName"
    Write-Host "    ACR            : $AcrName"
}
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "This will DELETE the resources above. Continue? (y/n)"
    if ($confirm -notin @("y", "Y")) {
        Write-WarnLine "Cleanup cancelled."
        exit 0
    }
}

if ($DeleteResourceGroup) {
    Write-Step "Deleting resource group '$ResourceGroup'"
    $rgExists = az group exists --name $ResourceGroup | ConvertFrom-Json
    if ($rgExists) {
        Invoke-Native "az" @("group", "delete", "--name", $ResourceGroup, "--yes", "--no-wait")
        Write-Ok "Resource group deletion started (running in the background)."
    }
    else {
        Write-WarnLine "Resource group '$ResourceGroup' not found."
    }
}
else {
    # Delete in dependency order: app -> environment -> registry.
    if ($AppName) {
        Write-Step "Deleting Container App '$AppName'"
        $exists = az containerapp show --name $AppName --resource-group $ResourceGroup 2>$null
        if ($exists) {
            Invoke-Native "az" @("containerapp", "delete", "--name", $AppName,
                "--resource-group", $ResourceGroup, "--yes")
            Write-Ok "Deleted Container App."
        }
        else { Write-WarnLine "Container App '$AppName' not found." }
    }

    if ($EnvName) {
        Write-Step "Deleting Container Apps environment '$EnvName'"
        $exists = az containerapp env show --name $EnvName --resource-group $ResourceGroup 2>$null
        if ($exists) {
            Invoke-Native "az" @("containerapp", "env", "delete", "--name", $EnvName,
                "--resource-group", $ResourceGroup, "--yes")
            Write-Ok "Deleted environment."
        }
        else { Write-WarnLine "Environment '$EnvName' not found." }
    }

    if ($AcrName) {
        Write-Step "Deleting Azure Container Registry '$AcrName'"
        $exists = az acr show --name $AcrName --resource-group $ResourceGroup 2>$null
        if ($exists) {
            Invoke-Native "az" @("acr", "delete", "--name", $AcrName,
                "--resource-group", $ResourceGroup, "--yes")
            Write-Ok "Deleted ACR."
        }
        else { Write-WarnLine "ACR '$AcrName' not found." }
    }
}

# Remove the local state file so a re-deploy starts clean.
$statePath = Get-DeployStatePath
if (Test-Path $statePath) {
    Remove-Item $statePath -Force
    Write-Ok "Removed local deployment state ($statePath)."
}

Write-Host ""
Write-Ok "Azure cleanup finished."
Write-Host ""
Write-WarnLine "Agent 365 side: deleting a BYO MCP registration is not supported."
Write-Host "    To retire the tool, go to Microsoft 365 admin center ->" -ForegroundColor DarkGray
Write-Host "    Agents -> Tools -> Registry -> select 'PRISM-EmployeeDirectory' -> Block." -ForegroundColor DarkGray
