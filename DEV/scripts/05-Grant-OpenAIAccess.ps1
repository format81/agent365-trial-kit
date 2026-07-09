<#
.SYNOPSIS
    Grants the data-plane role "Cognitive Services OpenAI User" on an Azure
    OpenAI resource so keyless (Microsoft Entra ID) authentication works.

.DESCRIPTION
    When API keys are disabled by policy, the agent authenticates to Azure OpenAI
    with Entra ID tokens (DefaultAzureCredential). That requires the calling
    identity to hold the "Cognitive Services OpenAI User" role on the resource.

    This script assigns that role to:
      - your signed-in user (for local dev with 'az login'), and/or
      - an Azure App Service system-assigned Managed Identity (for the deployed
        agent), enabling it automatically if needed.

    NOTE: Assigning roles requires Owner or User Access Administrator on the
    Azure OpenAI resource (or its resource group / subscription).

.PARAMETER OpenAIName
    Name of the Azure OpenAI (Cognitive Services) account.

.PARAMETER OpenAIResourceGroup
    Resource group of the Azure OpenAI account. If omitted, uses the resource
    group from a365.config.json.

.PARAMETER GrantUser
    Assign the role to the currently signed-in user (default when neither
    -GrantUser nor -WebAppName is specified).

.PARAMETER WebAppName
    Also assign the role to this Web App's system-assigned Managed Identity
    (enables the identity if it isn't already on).

.EXAMPLE
    .\05-Grant-OpenAIAccess.ps1 -OpenAIName my-aoai -OpenAIResourceGroup rg-ai

.EXAMPLE
    .\05-Grant-OpenAIAccess.ps1 -OpenAIName my-aoai -GrantUser -WebAppName app-agent-12345
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OpenAIName,
    [string]$OpenAIResourceGroup,
    [switch]$GrantUser,
    [string]$WebAppName
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

if (-not (Test-Command "az")) {
    Write-ErrLine "Azure CLI (az) is required. Run .\00-Prerequisites.ps1 first."
    exit 1
}

# Default: if nothing selected, grant to the signed-in user.
if (-not $GrantUser -and -not $WebAppName) { $GrantUser = $true }

# Resolve resource group from config when not provided.
$config = Read-A365Config
if (-not $OpenAIResourceGroup -and $config) { $OpenAIResourceGroup = $config.resourceGroup }
if (-not $OpenAIResourceGroup) {
    Write-ErrLine "No resource group provided and none found in a365.config.json."
    exit 1
}

$roleName = "Cognitive Services OpenAI User"

Write-Step "Resolving Azure OpenAI resource scope"
$scope = az cognitiveservices account show `
    --name $OpenAIName `
    --resource-group $OpenAIResourceGroup `
    --query id -o tsv
if (-not $scope) { throw "Could not resolve Azure OpenAI resource '$OpenAIName' in '$OpenAIResourceGroup'." }
Write-Ok "Scope: $scope"

function Grant-Role {
    param([string]$AssigneeObjectId, [string]$Label)
    Write-Step "Assigning '$roleName' to $Label"
    # Idempotent: az returns the existing assignment if it already exists.
    Invoke-Native "az" @(
        "role", "assignment", "create",
        "--assignee-object-id", $AssigneeObjectId,
        "--assignee-principal-type", "ServicePrincipal",
        "--role", $roleName,
        "--scope", $scope,
        "--only-show-errors"
    )
    Write-Ok "Role assigned to $Label."
}

# ---------------------------------------------------------------------------
# 1) Signed-in user (local dev)
# ---------------------------------------------------------------------------
if ($GrantUser) {
    Write-Step "Assigning '$roleName' to the signed-in user"
    $userId = az ad signed-in-user show --query id -o tsv
    if (-not $userId) { throw "Could not resolve the signed-in user. Run 'az login'." }
    Invoke-Native "az" @(
        "role", "assignment", "create",
        "--assignee-object-id", $userId,
        "--assignee-principal-type", "User",
        "--role", $roleName,
        "--scope", $scope,
        "--only-show-errors"
    )
    Write-Ok "Role assigned to signed-in user ($userId)."
}

# ---------------------------------------------------------------------------
# 2) App Service Managed Identity (deployed agent)
# ---------------------------------------------------------------------------
if ($WebAppName) {
    if (-not $config) { throw "a365.config.json required to resolve the Web App resource group." }
    $appRg = $config.resourceGroup

    Write-Step "Ensuring system-assigned Managed Identity on '$WebAppName'"
    $principalId = az webapp identity show --name $WebAppName --resource-group $appRg --query principalId -o tsv
    if (-not $principalId) {
        Invoke-Native "az" @("webapp", "identity", "assign", "--name", $WebAppName, "--resource-group", $appRg, "--only-show-errors")
        $principalId = az webapp identity show --name $WebAppName --resource-group $appRg --query principalId -o tsv
    }
    if (-not $principalId) { throw "Could not enable/resolve the Managed Identity for '$WebAppName'." }
    Write-Ok "Managed Identity principalId: $principalId"

    Grant-Role -AssigneeObjectId $principalId -Label "Web App Managed Identity ($WebAppName)"
}

Write-Host ""
Write-Ok "Done. Keyless Entra ID auth to Azure OpenAI should now work."
Write-Host "    Role propagation can take a minute. Then run the agent (menu option 5)." -ForegroundColor DarkGray
