<#
.SYNOPSIS
    Builds the PRISM Employee Directory MCP server image in Azure Container
    Registry and deploys it to Azure Container Apps, giving you a public HTTPS
    endpoint you can register with Microsoft Agent 365 as a BYO MCP server.

.DESCRIPTION
    End-to-end, works for anyone with an Azure subscription. No local Node.js,
    Docker, or TypeScript toolchain required - the image is built from source
    remotely with 'az acr build' using the multi-stage Dockerfile.

    Steps performed:
      1. Verifies the Azure CLI + containerapp extension, and (optionally) sets
         the subscription.
      2. Registers the required resource providers (Microsoft.App,
         Microsoft.OperationalInsights, Microsoft.ContainerRegistry).
      3. Creates the resource group (if missing).
      4. Creates an ACR (Basic, admin-enabled) with a globally-unique name.
      5. Builds and pushes the image with 'az acr build'.
      6. Creates a Container Apps environment.
      7. Creates the Container App with external ingress on port 3000.
      8. Prints the public MCP endpoint and saves state for cleanup.

    NOTE: The deployed server is NoAuth and contains only fictional demo data.

.PARAMETER ResourceGroup
    Resource group to create/use. Default: rg-prism-mcp.

.PARAMETER Location
    Azure region. Default: westeurope.

.PARAMETER AcrName
    Azure Container Registry name (5-50 alphanumerics, globally unique). If
    omitted, a unique name like 'acrprismmcp<random>' is generated.

.PARAMETER EnvName
    Container Apps environment name. Default: cae-prism-mcp.

.PARAMETER AppName
    Container App name. Default: ca-prism-employee-mcp.

.PARAMETER ImageTag
    Image tag to build/deploy. Default: v1.

.PARAMETER SubscriptionId
    Azure subscription to target. If omitted, uses the current 'az' context.

.EXAMPLE
    ./Deploy-McpToAca.ps1

.EXAMPLE
    ./Deploy-McpToAca.ps1 -ResourceGroup rg-demo -Location swedencentral -SubscriptionId <sub-guid>
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg-prism-mcp",
    [string]$Location = "westeurope",
    [string]$AcrName,
    [string]$EnvName = "cae-prism-mcp",
    [string]$AppName = "ca-prism-employee-mcp",
    [string]$ImageTag = "v1",
    [string]$SubscriptionId
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

# Source folder that holds the Dockerfile + app (../prism-employee-mcp).
$AppSource = (Resolve-Path (Join-Path $PSScriptRoot "..\prism-employee-mcp")).Path
$ImageName = "prism-employee-mcp"

Write-Step "Prerequisites"
if (-not (Test-Command "az")) {
    throw "Azure CLI (az) not found. Install it: https://learn.microsoft.com/cli/azure/install-azure-cli"
}
Write-Ok "Azure CLI found."

# Make sure the containerapp extension is present (idempotent).
Write-Host "    > az extension add --name containerapp --upgrade --only-show-errors" -ForegroundColor DarkGray
az extension add --name containerapp --upgrade --only-show-errors | Out-Null
Write-Ok "containerapp extension ready."

# Confirm we are logged in.
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-WarnLine "Not logged in. Launching 'az login'..."
    Invoke-Native "az" @("login")
    $account = az account show | ConvertFrom-Json
}
if ($SubscriptionId) {
    Invoke-Native "az" @("account", "set", "--subscription", $SubscriptionId)
    $account = az account show | ConvertFrom-Json
}
$SubscriptionId = $account.id
Write-Ok "Subscription: $($account.name) ($SubscriptionId)"

# Generate a unique ACR name if not supplied.
if (-not $AcrName) {
    $suffix = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $AcrName = "acrprismmcp$suffix"
}
$AcrName = $AcrName.ToLower()
Write-Ok "ACR name: $AcrName"

# ---------------------------------------------------------------------------
# 1. Resource providers (safe to run repeatedly)
# ---------------------------------------------------------------------------
Write-Step "Registering resource providers"
foreach ($rp in @("Microsoft.App", "Microsoft.OperationalInsights", "Microsoft.ContainerRegistry")) {
    Invoke-Native "az" @("provider", "register", "--namespace", $rp, "--wait")
    Write-Ok "$rp registered."
}

# ---------------------------------------------------------------------------
# 2. Resource group
# ---------------------------------------------------------------------------
Write-Step "Resource group '$ResourceGroup' in $Location"
$rgExists = az group exists --name $ResourceGroup | ConvertFrom-Json
if (-not $rgExists) {
    Invoke-Native "az" @("group", "create", "--name", $ResourceGroup, "--location", $Location)
    Write-Ok "Created resource group."
}
else {
    Write-Ok "Resource group already exists."
}

# ---------------------------------------------------------------------------
# 3. Azure Container Registry
# ---------------------------------------------------------------------------
Write-Step "Azure Container Registry '$AcrName'"
$acrExists = az acr show --name $AcrName --resource-group $ResourceGroup 2>$null
if (-not $acrExists) {
    Invoke-Native "az" @("acr", "create", "--name", $AcrName, "--resource-group", $ResourceGroup,
        "--sku", "Basic", "--admin-enabled", "true", "--location", $Location)
    Write-Ok "Created ACR."
}
else {
    Invoke-Native "az" @("acr", "update", "--name", $AcrName, "--admin-enabled", "true")
    Write-Ok "ACR already exists (admin enabled)."
}

# ---------------------------------------------------------------------------
# 4. Build + push the image from source (remote build - no local Docker)
# ---------------------------------------------------------------------------
Write-Step "Building image ${ImageName}:${ImageTag} from $AppSource"
Push-Location $AppSource
try {
    Invoke-Native "az" @("acr", "build", "--registry", $AcrName,
        "--image", "${ImageName}:${ImageTag}", ".")
    Write-Ok "Image built and pushed."
}
finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# 5. Container Apps environment
# ---------------------------------------------------------------------------
Write-Step "Container Apps environment '$EnvName'"
$envExists = az containerapp env show --name $EnvName --resource-group $ResourceGroup 2>$null
if (-not $envExists) {
    Invoke-Native "az" @("containerapp", "env", "create", "--name", $EnvName,
        "--resource-group", $ResourceGroup, "--location", $Location)
    Write-Ok "Created environment."
}
else {
    Write-Ok "Environment already exists."
}

# ---------------------------------------------------------------------------
# 6. Container App
# ---------------------------------------------------------------------------
$loginServer = "$AcrName.azurecr.io"
$image = "$loginServer/${ImageName}:${ImageTag}"

Write-Step "Container App '$AppName'"
$appExists = az containerapp show --name $AppName --resource-group $ResourceGroup 2>$null
if (-not $appExists) {
    Invoke-Native "az" @("containerapp", "create", "--name", $AppName,
        "--resource-group", $ResourceGroup, "--environment", $EnvName,
        "--image", $image, "--target-port", "3000", "--ingress", "external",
        "--registry-server", $loginServer,
        "--min-replicas", "1", "--max-replicas", "3",
        "--cpu", "0.5", "--memory", "1.0Gi")
    Write-Ok "Created Container App."
}
else {
    Invoke-Native "az" @("containerapp", "update", "--name", $AppName,
        "--resource-group", $ResourceGroup, "--image", $image)
    Write-Ok "Updated Container App to new image."
}

# ---------------------------------------------------------------------------
# 7. Output + save state
# ---------------------------------------------------------------------------
$fqdn = az containerapp show --name $AppName --resource-group $ResourceGroup `
    --query properties.configuration.ingress.fqdn -o tsv
$mcpUrl = "https://$fqdn/mcp"

Save-DeployState @{
    subscriptionId = $SubscriptionId
    resourceGroup  = $ResourceGroup
    location       = $Location
    acrName        = $AcrName
    envName        = $EnvName
    appName        = $AppName
    imageTag       = $ImageTag
    fqdn           = $fqdn
    mcpUrl         = $mcpUrl
    deployedAt     = (Get-Date).ToString("o")
}

Write-Host ""
Write-Step "Deployment complete"
Write-Host "    Health : https://$fqdn/health" -ForegroundColor Green
Write-Host "    MCP    : $mcpUrl" -ForegroundColor Green
Write-Host ""
Write-Host "    Quick check:" -ForegroundColor DarkGray
Write-Host "      curl https://$fqdn/health" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    Register with Agent 365 (NoAuth):" -ForegroundColor DarkGray
Write-Host "      a365 develop-mcp register-external-mcp-server ``" -ForegroundColor DarkGray
Write-Host "        --server-name `"PRISM-EmployeeDirectory`" ``" -ForegroundColor DarkGray
Write-Host "        --server-url `"$mcpUrl`" ``" -ForegroundColor DarkGray
Write-Host "        --publisher `"Prism Industries`" ``" -ForegroundColor DarkGray
Write-Host "        --description `"Internal employee lookup service for Prism agents`" ``" -ForegroundColor DarkGray
Write-Host "        --auth-type `"NoAuth`" ``" -ForegroundColor DarkGray
Write-Host "        --tools `"get_employee,list_by_department`"" -ForegroundColor DarkGray
