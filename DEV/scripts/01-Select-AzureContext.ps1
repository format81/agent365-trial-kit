<#
.SYNOPSIS
    Interactively selects the Microsoft Entra tenant, Azure subscription and
    resource group, then writes a365.config.json for the Agent 365 CLI.

.DESCRIPTION
    Nothing is hard-coded. The script:
      1. Signs you in with 'az login' (per tenant if you pass -TenantId).
      2. Lets you pick a subscription from the ones you can access.
      3. Lets you pick an existing resource group or create a new one.
      4. Writes a365.config.json from a365.config.template.json.

    NOTE: Microsoft Agent 365 is in PREVIEW.

.PARAMETER TenantId
    Optional. Sign in to a specific tenant. If omitted, you can pick the tenant
    from the accounts az returns.

.PARAMETER AgentName
    Base name for the agent (used to derive blueprint/identity display names).

.PARAMETER NoDeviceCode
    Use the interactive browser sign-in instead of the device code flow.
    By default the script uses 'az login --use-device-code', which is more
    reliable in VS Code / remote sessions where the browser can't auto-open.

.EXAMPLE
    .\01-Select-AzureContext.ps1

.EXAMPLE
    .\01-Select-AzureContext.ps1 -TenantId <guid> -AgentName "Contoso Helpdesk"
#>
[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$AgentName,
    [switch]$NoDeviceCode
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

if (-not (Test-Command "az")) {
    Write-ErrLine "Azure CLI (az) is required. Run .\00-Prerequisites.ps1 first."
    exit 1
}

# Device code sign-in is the default (reliable when the browser can't auto-open).
$loginFlow = if ($NoDeviceCode) { @() } else { @("--use-device-code") }

# ---------------------------------------------------------------------------
# Step 1: Sign in / select tenant
# ---------------------------------------------------------------------------
Write-Step "Signing in to Azure"
if (-not $NoDeviceCode) {
    Write-Host "    Using device code sign-in. Follow the prompted URL + code to authenticate." -ForegroundColor DarkGray
}
if ($TenantId) {
    Invoke-Native "az" (@("login", "--tenant", $TenantId) + $loginFlow)
}
else {
    # Show tenants the user can reach so they can choose one explicitly.
    Invoke-Native "az" (@("login") + $loginFlow)

    Write-Step "Available tenants"
    $tenants = @(az account list --query "[].{name:name, tenantId:tenantId}" -o json | ConvertFrom-Json |
        Sort-Object tenantId -Unique)
    if (-not $tenants) { throw "No tenants returned by az account list." }

    for ($i = 0; $i -lt $tenants.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f $i, $tenants[$i].tenantId)
    }
    $sel = Read-Selection -Prompt "Select tenant index" -Count $tenants.Count
    $TenantId = $tenants[$sel].tenantId
    Write-Ok "Selected tenant: $TenantId"
}

# ---------------------------------------------------------------------------
# Step 2: Select subscription
# ---------------------------------------------------------------------------
Write-Step "Select an Azure subscription"
$subs = @(az account list --query "[?tenantId=='$TenantId'].{name:name, id:id, state:state}" -o json |
    ConvertFrom-Json | Where-Object { $_.state -eq "Enabled" })
if (-not $subs) { throw "No enabled subscriptions found for tenant $TenantId." }

for ($i = 0; $i -lt $subs.Count; $i++) {
    Write-Host ("  [{0}] {1}  ({2})" -f $i, $subs[$i].name, $subs[$i].id)
}
$subSel = Read-Selection -Prompt "Select subscription index" -Count $subs.Count
$subscription = $subs[$subSel]
Invoke-Native "az" @("account", "set", "--subscription", $subscription.id)
Write-Ok "Active subscription: $($subscription.name)"

# ---------------------------------------------------------------------------
# Step 3: Select or create a resource group
# ---------------------------------------------------------------------------
Write-Step "Select or create a resource group"
$groups = @(az group list --query "[].{name:name, location:location}" -o json | ConvertFrom-Json)
if ($groups) {
    for ($i = 0; $i -lt $groups.Count; $i++) {
        Write-Host ("  [{0}] {1}  ({2})" -f $i, $groups[$i].name, $groups[$i].location)
    }
}
Write-Host "  [n] Create a NEW resource group"
Write-Host "  You can also type an index, 'n', or an existing/new resource group name." -ForegroundColor DarkGray
$rgSel = Read-Host "Select resource group index, 'n', or name"

$rgName = $null
$location = $null

# Resolve the selection: index | 'n' | existing name | new name
$idx = 0
if ($rgSel -eq "n") {
    $createNew = $true
}
elseif ([int]::TryParse($rgSel, [ref]$idx) -and $idx -ge 0 -and $idx -lt $groups.Count) {
    # Numeric index into the existing list.
    $rg = $groups[$idx]
    $rgName = $rg.name
    $location = $rg.location
    $createNew = $false
    Write-Ok "Using resource group '$rgName' ($location)."
}
else {
    # Treat the input as a resource group name.
    $match = $groups | Where-Object { $_.name -eq $rgSel } | Select-Object -First 1
    if ($match) {
        $rgName = $match.name
        $location = $match.location
        $createNew = $false
        Write-Ok "Using resource group '$rgName' ($location)."
    }
    else {
        Write-WarnLine "Resource group '$rgSel' does not exist yet."
        $answer = Read-Host "Create it? (y/n)"
        if ($answer -notin @("y", "Y")) { throw "Invalid resource group selection '$rgSel'." }
        $rgName = $rgSel
        $createNew = $true
    }
}

if ($createNew) {
    if (-not $rgName) { $rgName = Read-Host "New resource group name" }
    $location = Read-Host "Azure region (e.g. westeurope, eastus)"
    Invoke-Native "az" @("group", "create", "--name", $rgName, "--location", $location, "--only-show-errors")
    Write-Ok "Created resource group '$rgName' in $location."
}

# ---------------------------------------------------------------------------
# Step 4: Write a365.config.json from the template
# ---------------------------------------------------------------------------
if (-not $AgentName) {
    $AgentName = Read-Host "Agent base name (e.g. Contoso Helpdesk)"
}

Write-Step "Writing a365.config.json"
$templatePath = Join-Path (Get-DevRoot) "a365.config.template.json"
$config = Get-Content $templatePath -Raw | ConvertFrom-Json

$config.agentName      = $AgentName
$config.agentIdentityDisplayName  = "$AgentName Identity"
$config.agentBlueprintDisplayName = "$AgentName Blueprint"
$config.agentDescription = "$AgentName - LangChain agent onboarded to Agent 365."
$config.environment    = "prod"
$config.tenantId       = $TenantId
$config.subscriptionId = $subscription.id
$config.resourceGroup  = $rgName
$config.location       = $location

$configPath = Get-ConfigPath
$config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
Write-Ok "Wrote $configPath"

Write-Host ""
Write-Ok "Azure context ready."
Write-Host "    Next:" -ForegroundColor DarkGray
Write-Host "      - Create ONLY the Entra Agent ID blueprint : .\02-New-AgentBlueprint.ps1" -ForegroundColor DarkGray
Write-Host "      - Full deploy + onboard to Agent 365       : .\03-Deploy-AndOnboard.ps1" -ForegroundColor DarkGray
