<#
.SYNOPSIS
    EXPLICIT option: create an Agent Blueprint in Microsoft Entra Agent ID using
    the Agent 365 CLI, and show the user exactly what happens.

.DESCRIPTION
    An agent blueprint is the IT-approved, governance-enforced definition of an
    agent (its identity, permitted tool access and compliance constraints).
    Creating one provisions a first-class Microsoft Entra Agent ID for the agent
    - the foundation for Entra governance, Purview data protection and Defender
    monitoring.

    This script runs (and echoes) the real Agent 365 CLI commands:
        a365 setup requirements      # optional prerequisite check
        a365 setup blueprint         # create the Entra Agent ID blueprint

    Use -DryRun to preview the CLI actions without making changes.
    Use -WhatIfPrereq to skip the requirements check.

    Minimum role: Agent ID Developer (for blueprint creation).
    NOTE: Microsoft Agent 365 is in PREVIEW.

    Docs:
      https://learn.microsoft.com/microsoft-agent-365/developer/reference/cli/setup
      https://learn.microsoft.com/entra/agent-id/identity-platform/agent-blueprint

.PARAMETER AgentName
    Agent base name. If omitted, taken from a365.config.json.

.PARAMETER TenantId
    Tenant ID. If omitted, taken from a365.config.json (or az account show).

.PARAMETER DryRun
    Pass --dry-run to the CLI so nothing is changed.

.EXAMPLE
    .\02-New-AgentBlueprint.ps1

.EXAMPLE
    .\02-New-AgentBlueprint.ps1 -AgentName "Contoso Helpdesk" -TenantId <guid> -DryRun
#>
[CmdletBinding()]
param(
    [string]$AgentName,
    [string]$TenantId,
    [switch]$DryRun,
    [switch]$SkipRequirements
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

if (-not (Test-Command "a365")) {
    Write-ErrLine "Agent 365 CLI (a365) not found. Run .\00-Prerequisites.ps1 -Install first."
    exit 1
}

# Resolve agent name / tenant from config when not provided explicitly.
$config = Read-A365Config
if (-not $AgentName -and $config) { $AgentName = $config.agentName }
if (-not $TenantId  -and $config) { $TenantId  = $config.tenantId }

Write-Step "About to create an Entra Agent ID blueprint (PREVIEW)"
Write-Host "    Agent name : $AgentName"
Write-Host "    Tenant     : $TenantId"
Write-Host ""
Write-Host "    What the CLI will do:" -ForegroundColor DarkGray
Write-Host "      1. Register an Entra ID application (the blueprint)." -ForegroundColor DarkGray
Write-Host "      2. Establish the agent's first-class Entra Agent ID." -ForegroundColor DarkGray
Write-Host "      3. Configure inheritable permissions for future agent instances." -ForegroundColor DarkGray
Write-Host ""

# Build common CLI args. When no config file exists, the CLI supports a
# config-free flow via --agent-name (+ optional --tenant-id).
$commonArgs = @()
if ($AgentName) { $commonArgs += @("--agent-name", $AgentName) }
if ($TenantId)  { $commonArgs += @("--tenant-id", $TenantId) }
if ($DryRun)    { $commonArgs += @("--dry-run") }

# ---------------------------------------------------------------------------
# Step 1 (optional): validate prerequisites
# ---------------------------------------------------------------------------
if (-not $SkipRequirements) {
    Write-Step "a365 setup requirements"
    try {
        # NOTE: 'setup requirements' does not accept --tenant-id.
        Invoke-Native "a365" @("setup", "requirements")
    }
    catch {
        Write-WarnLine "Requirements check reported issues. Review the output above."
    }
}

# ---------------------------------------------------------------------------
# Step 2: create the blueprint
# ---------------------------------------------------------------------------
Write-Step "a365 setup blueprint"
Write-Host "    (This is the explicit Entra Agent ID blueprint creation step.)" -ForegroundColor DarkGray

# Run the CLI directly so a non-zero exit (e.g. missing 'wids' claim) doesn't
# crash the script with a raw exception - we give actionable guidance instead.
& a365 @(@("setup", "blueprint") + $commonArgs)
$blueprintExit = $LASTEXITCODE

Write-Host ""
if ($blueprintExit -ne 0) {
    Write-ErrLine "a365 setup blueprint failed (exit $blueprintExit)."
    Write-Host "    Most common cause: the client app is missing the 'wids' optional claim," -ForegroundColor Yellow
    Write-Host "    so the CLI cannot detect Global Administrator and skips permission grants." -ForegroundColor Yellow
    Write-Host "    Fix it (as Application/Global Admin), then sign out/in and retry:" -ForegroundColor Yellow
    Write-Host "      .\scripts\Add-WidsClaim.ps1 -AppId <client-app-id>" -ForegroundColor DarkGray
    Write-Host "      az logout; az login --use-device-code" -ForegroundColor DarkGray
    Write-Host "      .\scripts\02-New-AgentBlueprint.ps1" -ForegroundColor DarkGray
    exit $blueprintExit
}

if ($DryRun) {
    Write-Ok "Dry run complete - no changes were made."
}
else {
    Write-Ok "Agent blueprint created in Entra Agent ID."
    Write-Host "    Verify in Microsoft 365 admin center / Entra admin center, then run:" -ForegroundColor DarkGray
    Write-Host "      a365 query-entra blueprint-scopes" -ForegroundColor DarkGray
    Write-Host "    Or continue to full onboarding: .\03-Deploy-AndOnboard.ps1" -ForegroundColor DarkGray
}
