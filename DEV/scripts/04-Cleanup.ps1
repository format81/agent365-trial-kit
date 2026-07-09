<#
.SYNOPSIS
    Removes the resources created by this trial: the Agent 365 blueprint/identity
    (via the Agent 365 CLI) and the Azure App Service resources.

.DESCRIPTION
    Cleanup runs in two independent parts, each opt-out:

      1. Agent 365 cleanup (a365 cleanup ...) - removes the Entra ID blueprint,
         the agent instance identity/user, and any Azure resources the CLI itself
         created. Use -Scope to choose what to remove.

      2. Azure App Service cleanup - deletes the Web App and App Service Plan that
         03-Deploy-AndOnboard.ps1 provisioned (best-effort, name-based).

    NOTE: Microsoft Agent 365 is in PREVIEW. Confirm subcommands with
    'a365 cleanup -h' for your CLI version.

    Docs: https://learn.microsoft.com/microsoft-agent-365/developer/reference/cli/

.PARAMETER Scope
    What to clean in Agent 365:
      all       -> a365 cleanup            (blueprint + instance + Azure)
      azure     -> a365 cleanup azure      (App Service, App Service Plan)
      blueprint -> a365 cleanup blueprint  (Entra ID blueprint app + SP)
      instance  -> a365 cleanup instance   (agent instance identity + user)
      none      -> skip Agent 365 cleanup entirely

.PARAMETER DeleteAppService
    Also delete the Azure Web App + App Service Plan by name (asp-<name> /
    app-<name>-*) in the configured resource group.

.PARAMETER Force
    Do not prompt for confirmation.

.PARAMETER DryRun
    Preview Agent 365 CLI cleanup actions with --dry-run (where supported).

.EXAMPLE
    .\04-Cleanup.ps1

.EXAMPLE
    .\04-Cleanup.ps1 -Scope blueprint -DeleteAppService -Force
#>
[CmdletBinding()]
param(
    [ValidateSet("all", "azure", "blueprint", "instance", "none")]
    [string]$Scope = "all",
    [switch]$DeleteAppService,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

$config = Read-A365Config
if (-not $config) {
    Write-WarnLine "a365.config.json not found. Cleanup will rely on defaults / current az context."
}

$agentName = if ($config) { $config.agentName } else { $null }
$subId     = if ($config) { $config.subscriptionId } else { $null }
$rg        = if ($config) { $config.resourceGroup } else { $null }

Write-Step "Cleanup plan"
Write-Host "    Agent          : $agentName"
Write-Host "    Resource group : $rg"
Write-Host "    A365 scope     : $Scope"
Write-Host "    Delete WebApp  : $DeleteAppService"
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "This will DELETE resources. Continue? (y/n)"
    if ($confirm -notin @("y", "Y")) {
        Write-WarnLine "Cleanup cancelled."
        exit 0
    }
}

# ---------------------------------------------------------------------------
# Part 1: Agent 365 cleanup via the CLI
# ---------------------------------------------------------------------------
if ($Scope -ne "none") {
    if (-not (Test-Command "a365")) {
        Write-WarnLine "Agent 365 CLI (a365) not found. Skipping Agent 365 cleanup."
    }
    else {
        $cleanupArgs = @("cleanup")
        if ($Scope -ne "all") { $cleanupArgs += $Scope }
        if ($DryRun) { $cleanupArgs += "--dry-run" }

        Write-Step "a365 $($cleanupArgs -join ' ')"
        Push-Location (Get-DevRoot)
        try {
            # Do not hard-fail the whole script if the CLI returns non-zero;
            # continue to Azure cleanup and report.
            & a365 @cleanupArgs
            if ($LASTEXITCODE -ne 0) {
                Write-WarnLine "a365 cleanup returned exit code $LASTEXITCODE. Review the output above."
            }
            else {
                Write-Ok "Agent 365 cleanup completed."
            }
        }
        finally {
            Pop-Location
        }
    }
}
else {
    Write-WarnLine "Skipping Agent 365 cleanup (-Scope none)."
}

# ---------------------------------------------------------------------------
# Part 2: Azure App Service cleanup (best-effort, name-based)
# ---------------------------------------------------------------------------
if ($DeleteAppService) {
    if (-not (Test-Command "az")) {
        Write-WarnLine "Azure CLI (az) not found. Skipping App Service cleanup."
    }
    elseif (-not $rg) {
        Write-WarnLine "No resource group in config. Skipping App Service cleanup."
    }
    else {
        if ($subId) { Invoke-Native "az" @("account", "set", "--subscription", $subId) }

        $safeName = ($agentName -replace '[^a-zA-Z0-9]', '').ToLower()
        if (-not $safeName) { $safeName = "agent" }
        $planName = "asp-$safeName"

        Write-Step "Deleting Web App(s) matching 'app-$safeName-*' in $rg"
        $apps = az webapp list --resource-group $rg --query "[?starts_with(name, 'app-$safeName-')].name" -o json |
            ConvertFrom-Json
        foreach ($app in $apps) {
            if ($DryRun) {
                Write-Host "    [dry-run] would delete webapp $app" -ForegroundColor DarkGray
            }
            else {
                Invoke-Native "az" @("webapp", "delete", "--name", $app, "--resource-group", $rg)
                Write-Ok "Deleted Web App $app"
            }
        }
        if (-not $apps) { Write-WarnLine "No matching Web Apps found." }

        Write-Step "Deleting App Service Plan '$planName' in $rg"
        $planExists = az appservice plan list --resource-group $rg --query "[?name=='$planName'].name" -o tsv
        if ($planExists) {
            if ($DryRun) {
                Write-Host "    [dry-run] would delete plan $planName" -ForegroundColor DarkGray
            }
            else {
                Invoke-Native "az" @("appservice", "plan", "delete", "--name", $planName, "--resource-group", $rg, "--yes")
                Write-Ok "Deleted App Service Plan $planName"
            }
        }
        else {
            Write-WarnLine "App Service Plan '$planName' not found."
        }
    }
}
else {
    Write-WarnLine "Skipping App Service deletion (pass -DeleteAppService to remove it)."
}

Write-Host ""
Write-Ok "Cleanup finished."
Write-Host "    Tip: verify in the Microsoft 365 admin center and the Azure portal that nothing remains." -ForegroundColor DarkGray
