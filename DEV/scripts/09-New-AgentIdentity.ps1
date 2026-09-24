<#
.SYNOPSIS
    Creates an Agent Identity under the current agent blueprint via Microsoft
    Graph, so the blueprint has at least one identity (registry no longer shows
    0) WITHOUT needing Teams or the Frontier "Autopilots" license.

.DESCRIPTION
    Reads the blueprint id from a365.generated.config.json (written by
    'a365 setup all') and creates an agent identity under it. Uses
    Microsoft Graph PowerShell (Connect-MgGraph) because Azure CLI tokens are
    rejected by the Agent Identity APIs (403). The sponsor defaults to the
    signed-in user (sponsors must be users).

    Idempotent: if an agent identity with the same display name already exists
    under this blueprint, it is not recreated (unless -Force). Works on every run
    of the flow because it always targets the blueprint in the current
    a365.generated.config.json.

    NOTE: Microsoft Agent 365 / Entra Agent ID are in PREVIEW. The agent-identity
    Graph surface is on the beta endpoint and may change.

    Docs: https://learn.microsoft.com/entra/agent-id/create-delete-agent-identities

.PARAMETER DisplayName
    Agent identity display name. Defaults to "<agentName> Agent".

.PARAMETER SponsorUserId
    Object ID of the sponsoring user. Defaults to the signed-in Graph user.

.PARAMETER SponsorUpn
    UPN of the sponsoring user (resolved to its object ID). Overrides the default.

.PARAMETER UseDeviceCode
    Sign in to Microsoft Graph with device code instead of the interactive
    broker (more reliable in remote/VS Code sessions).

.PARAMETER Force
    Create a new identity even if one with the same display name already exists.

.EXAMPLE
    .\09-New-AgentIdentity.ps1

.EXAMPLE
    .\09-New-AgentIdentity.ps1 -DisplayName "Contoso Helpdesk Agent 01" -UseDeviceCode
#>
[CmdletBinding()]
param(
    [string]$DisplayName,
    [string]$SponsorUserId,
    [string]$SponsorUpn,
    [switch]$UseDeviceCode,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

# --- Resolve config (tenant, agent name) and blueprint id (generated config) ---
$config = Read-A365Config
if (-not $config) {
    Write-ErrLine "a365.config.json not found. Run .\01-Select-AzureContext.ps1 first."
    exit 1
}
$tenantId = $config.tenantId
$agentName = $config.agentName

$genPath = Join-Path (Get-DevRoot) "a365.generated.config.json"
if (-not (Test-Path $genPath)) {
    Write-ErrLine "a365.generated.config.json not found. Run 'a365 setup all' first (creates the blueprint)."
    exit 1
}
$gen = Get-Content $genPath -Raw | ConvertFrom-Json
# agentBlueprintId == the blueprint appId used by the Agent Identity APIs.
$blueprintId = $gen.agentBlueprintId
if (-not $blueprintId) {
    Write-ErrLine "agentBlueprintId missing from a365.generated.config.json."
    exit 1
}

if (-not $DisplayName) { $DisplayName = "$agentName Agent" }

# --- Microsoft Graph PowerShell (az tokens are rejected by Agent Identity APIs) ---
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}
catch {
    Write-ErrLine "Microsoft.Graph.Authentication module not found. Install it:"
    Write-Host "        pwsh -Command `"Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force`"" -ForegroundColor DarkGray
    exit 1
}

Write-Step "Signing in to Microsoft Graph (scopes: AgentIdentity.Create.All, AgentIdentity.Read.All, User.Read)"
$connect = @{
    TenantId  = $tenantId
    Scopes    = @("AgentIdentity.Create.All", "AgentIdentity.Read.All", "User.Read")
    NoWelcome = $true
}
if ($UseDeviceCode) { $connect["UseDeviceCode"] = $true }
Connect-MgGraph @connect

# --- Resolve sponsor (must be a user) ---
if ($SponsorUpn -and -not $SponsorUserId) {
    $u = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$([uri]::EscapeDataString($SponsorUpn))"
    $SponsorUserId = $u.id
}
if (-not $SponsorUserId) {
    $me = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me"
    $SponsorUserId = $me.id
}
Write-Ok "Sponsor user id: $SponsorUserId"

# --- Idempotency: skip if an identity with this name already exists under the blueprint ---
$filter = [uri]::EscapeDataString("displayName eq '$DisplayName'")
$found = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=$filter"
$existing = @($found.value | Where-Object { $_.agentIdentityBlueprintId -eq $blueprintId })
if ($existing.Count -gt 0 -and -not $Force) {
    Write-Ok "Agent identity '$DisplayName' already exists under blueprint $blueprintId (id: $($existing[0].id)). Skipping (use -Force to add another)."
    Write-Host "    Entra: https://entra.microsoft.com > Entra ID > Agents > Agent identities" -ForegroundColor DarkGray
    return
}

# --- Create the agent identity ---
Write-Step "Creating agent identity '$DisplayName' under blueprint $blueprintId"
$bodyObj = [ordered]@{
    displayName              = $DisplayName
    agentIdentityBlueprintId = $blueprintId
    "sponsors@odata.bind"    = @("https://graph.microsoft.com/v1.0/users/$SponsorUserId")
}
$body = $bodyObj | ConvertTo-Json -Depth 5

$created = Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/beta/servicePrincipals/Microsoft.Graph.AgentIdentity" `
    -Body $body -ContentType "application/json" `
    -Headers @{ "OData-Version" = "4.0" }

Write-Host ""
Write-Ok "Agent identity created."
Write-Host "    Display name : $DisplayName"
Write-Host "    Identity id  : $($created.id)"
Write-Host "    Blueprint id : $blueprintId"
Write-Host "    Verify in Entra: https://entra.microsoft.com > Entra ID > Agents > Agent identities" -ForegroundColor DarkGray
