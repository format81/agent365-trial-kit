<#
.SYNOPSIS
    Marks one or more Microsoft Entra Agent Identities as "Admin confirmed agent
    compromised" via the Microsoft Graph riskyAgents/confirmCompromised API, or
    verifies their current risk state in check-only mode.

.DESCRIPTION
    The script interactively asks for the Tenant ID and the object id of the Agent
    Identity to act on. It authenticates using the device code flow and then either:

      - Confirm mode (default): calls the beta Entra ID Protection endpoint
            POST /beta/identityProtection/riskyAgents/confirmCompromised
        which sets riskState = confirmedCompromised and riskLevel = high.

      - Check-only mode (-CheckOnly): performs a read-only GET to report the current
        riskState and riskLevel without applying any change.

    Requirements:
      - Graph permission: IdentityRiskyAgent.ReadWrite.All (delegated, admin consented)
      - Minimum role (delegated access): Security Administrator
      - Microsoft Entra ID Protection (P2) license
      - Global commercial cloud only, API in /beta

.PARAMETER TenantId
    The Microsoft Entra tenant ID (GUID). If not provided, it is requested interactively.

.PARAMETER ClientId
    The Application (client) ID used to authenticate. Defaults to the public
    Microsoft Azure PowerShell first-party app, which supports the device code flow.

.PARAMETER AgentId
    One or more Agent Identity object ids to act on. If not provided, they are
    requested interactively. Multiple ids can be comma-separated at the prompt.

.PARAMETER CheckOnly
    When specified, the script only reads and reports the current risk state and
    performs no write action.

.EXAMPLE
    .\Confirm-AgentCompromised.ps1
    Prompts for tenant and agent id, then confirms the agent as compromised.

.EXAMPLE
    .\Confirm-AgentCompromised.ps1 -CheckOnly
    Prompts for tenant and agent id, then only reports the current risk state.

.EXAMPLE
    .\Confirm-AgentCompromised.ps1 -TenantId <guid> -AgentId <guid> -CheckOnly

.NOTES
    Source: https://learn.microsoft.com/en-us/graph/api/riskyagent-confirmcompromised?view=graph-rest-beta
#>

[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$ClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e",
    [string[]]$AgentId,
    [switch]$CheckOnly,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Help: print usage and exit
# ---------------------------------------------------------------------------
if ($Help) {
    Write-Host ""
    Write-Host "Confirm-AgentCompromised.ps1 - Usage" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Marks one or more Microsoft Entra Agent Identities as compromised" -ForegroundColor White
    Write-Host "(Admin confirmed), or verifies their current risk state." -ForegroundColor White
    Write-Host ""
    Write-Host "PARAMETERS:" -ForegroundColor Yellow
    Write-Host "  -TenantId  <guid>   Entra tenant ID. If omitted, you are prompted." -ForegroundColor White
    Write-Host "  -ClientId  <guid>   App (client) ID for auth. Defaults to Azure PowerShell." -ForegroundColor White
    Write-Host "  -AgentId   <guid[]> One or more Agent Identity object ids. If omitted," -ForegroundColor White
    Write-Host "                      you are prompted (comma-separated for multiple)." -ForegroundColor White
    Write-Host "  -CheckOnly          Read-only: report risk state, perform no changes." -ForegroundColor White
    Write-Host "  -Help               Show this help and exit." -ForegroundColor White
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  # Confirm compromised (fully interactive)" -ForegroundColor DarkGray
    Write-Host "  .\Confirm-AgentCompromised.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "  # Verify only, no write action" -ForegroundColor DarkGray
    Write-Host "  .\Confirm-AgentCompromised.ps1 -CheckOnly" -ForegroundColor White
    Write-Host ""
    Write-Host "  # Non-interactive verification" -ForegroundColor DarkGray
    Write-Host "  .\Confirm-AgentCompromised.ps1 -TenantId <guid> -AgentId <guid> -CheckOnly" -ForegroundColor White
    Write-Host ""
    Write-Host "  # Confirm a specific agent without prompts" -ForegroundColor DarkGray
    Write-Host "  .\Confirm-AgentCompromised.ps1 -TenantId <guid> -AgentId <guid>" -ForegroundColor White
    Write-Host ""
    Write-Host "REQUIREMENTS:" -ForegroundColor Yellow
    Write-Host "  - Graph permission IdentityRiskyAgent.ReadWrite.All (admin consented)" -ForegroundColor White
    Write-Host "  - Role: Security Administrator (delegated access)" -ForegroundColor White
    Write-Host "  - Microsoft Entra ID Protection (P2) license" -ForegroundColor White
    Write-Host ""
    Write-Host "For full help run: Get-Help .\Confirm-AgentCompromised.ps1 -Detailed" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ---------------------------------------------------------------------------
# Step 0a: Resolve the Tenant ID
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
if ($CheckOnly) {
    Write-Host " Entra Agent ID - Verify Agent Identity risk state (check-only)" -ForegroundColor Cyan
}
else {
    Write-Host " Entra Agent ID - Confirm Agent Identity compromised" -ForegroundColor Cyan
}
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($TenantId)) {
    $TenantId = Read-Host "Enter the Tenant ID (GUID)"
}

if ([string]::IsNullOrWhiteSpace($TenantId)) {
    Write-Host "No Tenant ID provided. Exiting." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Step 0b: Resolve the Agent Identity ids
# ---------------------------------------------------------------------------
if (-not $AgentId -or $AgentId.Count -eq 0) {
    Write-Host ""
    Write-Host "Enter the object id of the Agent Identity to act on." -ForegroundColor Yellow
    Write-Host "For multiple agents, separate the ids with a comma." -ForegroundColor Yellow
    Write-Host ""
    $agentInput = Read-Host "Agent Identity ID"

    if ([string]::IsNullOrWhiteSpace($agentInput)) {
        Write-Host "No Agent Identity ID provided. Exiting." -ForegroundColor Red
        exit 1
    }

    $AgentId = $agentInput.Split(",")
}

# Normalize into a clean array of ids (trim and drop empties)
$agentIds = $AgentId |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" }

if ($agentIds.Count -eq 0) {
    Write-Host "No valid Agent Identity ID. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host ""
if ($CheckOnly) {
    Write-Host "Agents to verify:" -ForegroundColor Cyan
}
else {
    Write-Host "Agents to confirm as compromised:" -ForegroundColor Cyan
}
$agentIds | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
Write-Host ""

# Confirmation is only required for the write action
if (-not $CheckOnly) {
    $confirm = Read-Host "Confirm? This action sets riskLevel = high (y/n)"
    if ($confirm -notin @("y", "Y", "s", "S")) {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        exit 0
    }
}

$scope = "https://graph.microsoft.com/IdentityRiskyAgent.ReadWrite.All offline_access"

# ---------------------------------------------------------------------------
# Step 1: Request the device code
# ---------------------------------------------------------------------------
$deviceCodeBody = @{
    client_id = $ClientId
    scope     = $scope
}
$dcResponse = Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
    -Body $deviceCodeBody

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host $dcResponse.message -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Step 2: Poll for the token
# ---------------------------------------------------------------------------
$tokenBody = @{
    grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
    client_id   = $ClientId
    device_code = $dcResponse.device_code
}

$token = $null
$maxAttempts = 60
for ($i = 0; $i -lt $maxAttempts; $i++) {
    Start-Sleep -Seconds $dcResponse.interval
    try {
        $tokenResponse = Invoke-RestMethod -Method POST `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Body $tokenBody
        $token = $tokenResponse.access_token
        Write-Host "Token acquired!" -ForegroundColor Green
        break
    }
    catch {
        $err = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($err.error -eq "authorization_pending") {
            Write-Host "." -NoNewline
            continue
        }
        elseif ($err.error -eq "slow_down") {
            Start-Sleep -Seconds 5
            continue
        }
        else {
            Write-Host ""
            Write-Host "Authentication error: $($err.error) - $($err.error_description)" -ForegroundColor Red
            exit 1
        }
    }
}

if (-not $token) {
    Write-Host "Timed out waiting for authentication." -ForegroundColor Red
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

# ---------------------------------------------------------------------------
# Step 3: Confirm compromised (skipped in check-only mode)
# ---------------------------------------------------------------------------
if (-not $CheckOnly) {
    Write-Host ""
    Write-Host "Calling confirmCompromised for $($agentIds.Count) agent(s)..." -ForegroundColor Cyan

    $body = @{ agentIds = @($agentIds) } | ConvertTo-Json

    try {
        $response = Invoke-WebRequest -Method POST `
            -Uri "https://graph.microsoft.com/beta/identityProtection/riskyAgents/confirmCompromised" `
            -Headers $headers `
            -Body $body `
            -UseBasicParsing

        Write-Host ""
        Write-Host "SUCCESS! Agent Identities marked as compromised." -ForegroundColor Green
        Write-Host "HTTP Status: $($response.StatusCode)" -ForegroundColor Green
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errBody = $_.ErrorDetails.Message
        Write-Host ""
        Write-Host "FAILED - HTTP $statusCode" -ForegroundColor Red
        Write-Host $errBody -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host ""
    Write-Host "Check-only mode: no write action performed." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 4: Verify the resulting state (read-only, idempotent)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Verifying risk state..." -ForegroundColor Cyan

$allConfirmed = $true
foreach ($id in $agentIds) {
    try {
        $agent = Invoke-RestMethod -Method GET `
            -Uri "https://graph.microsoft.com/beta/identityProtection/riskyAgents/$id" `
            -Headers $headers

        $isConfirmed = ($agent.riskState -eq "confirmedCompromised")
        $color = if ($isConfirmed) { "Green" } else { "White" }
        if (-not $isConfirmed) { $allConfirmed = $false }

        Write-Host ("  {0} -> riskState={1}, riskLevel={2}" -f `
            $id, $agent.riskState, $agent.riskLevel) -ForegroundColor $color
    }
    catch {
        $allConfirmed = $false
        Write-Host "  $id -> unable to read state (it may still be processing, or the id is not a riskyAgent)." -ForegroundColor DarkYellow
    }
}

Write-Host ""
if ($CheckOnly) {
    if ($allConfirmed) {
        Write-Host "All agents are confirmedCompromised." -ForegroundColor Green
    }
    else {
        Write-Host "One or more agents are NOT confirmedCompromised." -ForegroundColor Yellow
    }
}
Write-Host "Done." -ForegroundColor Green
