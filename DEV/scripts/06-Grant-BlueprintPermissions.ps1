<#
.SYNOPSIS
    Grants the delegated Microsoft Graph permission AgentIdentityBlueprint.ReadWrite.All
    to the Agent 365 client app, admin-consents it, then (optionally) re-runs
    'a365 setup blueprint' to configure the blueprint's inheritable permissions.

.DESCRIPTION
    During 'a365 setup blueprint' you may see:

        OAuth2 permission grant failed ... Authorization_RequestDenied:
        Insufficient privileges ... Ensure you have AgentIdentityBlueprint.ReadWrite.All
        permission consented on your client app.

    That means the client app used by the CLI lacks the delegated permission
    needed to write the blueprint's inheritable permissions, so agent instances
    would inherit no Microsoft Graph access. This script fixes that by:

      1. Resolving the AgentIdentityBlueprint.ReadWrite.All scope id from the
         Microsoft Graph service principal.
      2. Adding it as a delegated permission on the client app.
      3. Granting tenant-wide admin consent.
      4. (default) Re-running 'a365 setup blueprint' to apply inheritable perms.

    Requires: Global Administrator (or Privileged Role + Application Admin) to
    grant admin consent.

    NOTE: Microsoft Agent 365 is in PREVIEW.

.PARAMETER ClientAppId
    Application (client) ID of the Agent 365 CLI app. Defaults to the well-known
    "Agent 365 CLI" app resolved from your tenant.

.PARAMETER SkipBlueprintRerun
    Only grant + consent the permission; do not re-run 'a365 setup blueprint'.

.EXAMPLE
    .\06-Grant-BlueprintPermissions.ps1

.EXAMPLE
    .\06-Grant-BlueprintPermissions.ps1 -ClientAppId 7aa977bf-7e0c-43c4-b63f-3405b5cfc31e
#>
[CmdletBinding()]
param(
    [string]$ClientAppId,
    [switch]$SkipBlueprintRerun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

if (-not (Test-Command "az")) {
    Write-ErrLine "Azure CLI (az) is required. Run .\00-Prerequisites.ps1 first."
    exit 1
}

$graphAppId = "00000003-0000-0000-c000-000000000000"   # Microsoft Graph
$permissionName = "AgentIdentityBlueprint.ReadWrite.All"

# ---------------------------------------------------------------------------
# Resolve the client app
# ---------------------------------------------------------------------------
if (-not $ClientAppId) {
    Write-Step "Resolving 'Agent 365 CLI' application"
    $ClientAppId = az ad app list --filter "displayName eq 'Agent 365 CLI'" --query "[0].appId" -o tsv
    if (-not $ClientAppId) { throw "Could not resolve the 'Agent 365 CLI' app. Pass -ClientAppId explicitly." }
    Write-Ok "Client AppId: $ClientAppId"
}

# ---------------------------------------------------------------------------
# Resolve the delegated scope id from the Microsoft Graph service principal
# ---------------------------------------------------------------------------
Write-Step "Resolving '$permissionName' delegated scope id from Microsoft Graph"
$scopeId = az ad sp show --id $graphAppId `
    --query "oauth2PermissionScopes[?value=='$permissionName'].id | [0]" -o tsv
if (-not $scopeId) {
    throw "Could not find delegated scope '$permissionName' on Microsoft Graph. It may not exist in this tenant/cloud."
}
Write-Ok "Scope id: $scopeId"

# ---------------------------------------------------------------------------
# Add the delegated permission to the client app
# ---------------------------------------------------------------------------
Write-Step "Adding delegated permission to the client app"
Invoke-Native "az" @(
    "ad", "app", "permission", "add",
    "--id", $ClientAppId,
    "--api", $graphAppId,
    "--api-permissions", "$scopeId=Scope",
    "--only-show-errors"
)
Write-Ok "Permission added (pending admin consent)."

# ---------------------------------------------------------------------------
# Grant tenant-wide admin consent
# ---------------------------------------------------------------------------
Write-Step "Granting admin consent (requires Global Administrator)"
# Admin consent can briefly 404/racing right after 'permission add'; retry a bit.
$granted = $false
for ($i = 0; $i -lt 5; $i++) {
    try {
        Invoke-Native "az" @("ad", "app", "permission", "admin-consent", "--id", $ClientAppId)
        $granted = $true
        break
    }
    catch {
        Write-WarnLine "Admin consent not applied yet (attempt $($i + 1)/5). Waiting for propagation..."
        Start-Sleep -Seconds 10
    }
}
if (-not $granted) {
    Write-ErrLine "Admin consent did not complete. You can grant it in the portal:"
    Write-Host "  https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$ClientAppId" -ForegroundColor DarkGray
    exit 1
}
Write-Ok "Admin consent granted for $permissionName."

# ---------------------------------------------------------------------------
# Re-run 'a365 setup blueprint' to apply inheritable permissions
# ---------------------------------------------------------------------------
if ($SkipBlueprintRerun) {
    Write-WarnLine "Skipping blueprint re-run (-SkipBlueprintRerun)."
    Write-Host "    Run it yourself when ready:  a365 setup blueprint" -ForegroundColor DarkGray
    return
}

if (-not (Test-Command "a365")) {
    Write-WarnLine "Agent 365 CLI (a365) not found. Re-run 'a365 setup blueprint' after installing it."
    return
}

Write-Step "Re-running 'a365 setup blueprint' to configure inheritable permissions"
Write-Host "    Sign out/in first so your token reflects the new consent, if prompted." -ForegroundColor DarkGray
Push-Location (Get-DevRoot)
try {
    & a365 @("setup", "blueprint")
    if ($LASTEXITCODE -ne 0) {
        Write-WarnLine "a365 setup blueprint returned exit code $LASTEXITCODE. If it still reports insufficient privileges, run 'az logout; az login --use-device-code' and retry."
    }
    else {
        Write-Ok "Blueprint inheritable permissions configured."
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Ok "Done."
Write-Host "    Verify with:  a365 query-entra inheritance" -ForegroundColor DarkGray
