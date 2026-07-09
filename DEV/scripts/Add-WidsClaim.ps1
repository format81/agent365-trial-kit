<#
.SYNOPSIS
    Adds the 'wids' optional claim to a Microsoft Entra application's access
    tokens. Required by the Agent 365 CLI to detect the Global Administrator role
    and apply tenant-wide (AllPrincipals) OAuth2 grants on the blueprint.

.DESCRIPTION
    The Agent 365 CLI sometimes fails to add this claim automatically. This
    script adds it via Microsoft Graph (az rest PATCH). After running it you must
    sign out and back in so the next token carries the new claim.

    Requires: Application Administrator or Global Administrator.

.PARAMETER AppId
    The application's Application (client) ID. Defaults to the well-known
    "Agent 365 CLI" app resolved from your tenant.

.EXAMPLE
    .\Add-WidsClaim.ps1 -AppId 7aa977bf-7e0c-43c4-b63f-3405b5cfc31e
#>
[CmdletBinding()]
param(
    [string]$AppId
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

if (-not (Test-Command "az")) {
    Write-ErrLine "Azure CLI (az) is required."
    exit 1
}

# Resolve the Agent 365 CLI app by display name if no AppId was provided.
if (-not $AppId) {
    Write-Step "Resolving 'Agent 365 CLI' application"
    $AppId = az ad app list --filter "displayName eq 'Agent 365 CLI'" --query "[0].appId" -o tsv
    if (-not $AppId) { throw "Could not resolve the 'Agent 365 CLI' app. Pass -AppId explicitly." }
    Write-Ok "Resolved AppId: $AppId"
}

Write-Step "Adding 'wids' optional claim to access tokens on app $AppId"

# Resolve the application's object id. Using /applications/{object-id} avoids the
# /applications(appId='...') form whose parentheses break az.cmd on Windows.
$objectId = az ad app show --id $AppId --query id -o tsv
if (-not $objectId) { throw "Could not resolve object id for app $AppId." }

# Write the JSON body to a temp file to avoid shell quoting issues entirely.
$body = '{"optionalClaims":{"accessToken":[{"name":"wids","essential":false,"additionalProperties":[]}]}}'
$bodyFile = Join-Path $env:TEMP "wids-claim.json"
Set-Content -Path $bodyFile -Value $body -Encoding UTF8 -NoNewline

Invoke-Native "az" @(
    "rest",
    "--method", "PATCH",
    "--url", "https://graph.microsoft.com/v1.0/applications/$objectId",
    "--headers", "Content-Type=application/json",
    "--body", "@$bodyFile"
)

Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue

Write-Ok "'wids' optional claim added."
Write-Host ""
Write-Host "    Next steps:" -ForegroundColor DarkGray
Write-Host "      1. Refresh your token so it carries the new claim:" -ForegroundColor DarkGray
Write-Host "           az logout; az login --use-device-code" -ForegroundColor DarkGray
Write-Host "      2. Re-verify:  a365 setup requirements" -ForegroundColor DarkGray
Write-Host "      3. Retry:      .\02-New-AgentBlueprint.ps1" -ForegroundColor DarkGray
