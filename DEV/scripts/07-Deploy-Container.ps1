<#
.SYNOPSIS
    Builds the LangChain agent as a container image (Azure Container Registry
    build - no local Docker needed) and deploys it to Azure Web App for
    Containers with keyless Managed Identity access to Azure OpenAI.

.DESCRIPTION
    Container-based alternative to 03-Deploy-AndOnboard.ps1 that avoids the Oryx
    zip-deploy pitfalls (Windows backslash paths, venv extraction). The messaging
    endpoint stays on *.azurewebsites.net, so the Agent 365 onboarding flow
    (a365 setup all --messaging-endpoint .../api/messages) works unchanged.

    Flow:
      1. Read a365.config.json (tenant/subscription/resource group/region).
      2. Create an Azure Container Registry (Basic, admin disabled).
      3. 'az acr build' the image from DEV/Dockerfile (server-side build).
      4. Create App Service Plan (Linux) + Web App for Containers.
      5. Enable system-assigned Managed Identity; grant AcrPull on the ACR and
         pull the image with the MI (no admin creds, no secrets).
      6. Set app settings (keyless Azure OpenAI via MI) and grant the data-plane
         role on the Azure OpenAI resource.
      7. Write a state file for 08-Cleanup-Container.ps1 and print the endpoints.

    NOTE: Microsoft Agent 365 is in PREVIEW.

.PARAMETER OpenAIName
    Azure OpenAI (Cognitive Services) account name. Wires keyless access for the
    web app's Managed Identity. Omit (or use -SkipOpenAI) to deploy only the host.

.PARAMETER OpenAIResourceGroup
    Resource group of the Azure OpenAI account. Defaults to the config RG.

.PARAMETER OpenAIDeployment
    Chat model deployment name. Defaults to AZURE_OPENAI_DEPLOYMENT from .env,
    else 'gpt-4o'.

.PARAMETER AcrName
    Existing ACR to reuse. If omitted a new Basic ACR is created.

.PARAMETER ImageTag
    Image tag. Default 'v1'.

.PARAMETER SkipOpenAI
    Deploy the host only (no Azure OpenAI app settings / role assignment).

.PARAMETER DryRun
    Print the plan without creating anything.

.EXAMPLE
    .\07-Deploy-Container.ps1 -OpenAIName demomaire

.EXAMPLE
    .\07-Deploy-Container.ps1 -OpenAIName demomaire -OpenAIResourceGroup rg-ai -OpenAIDeployment gpt-4o
#>
[CmdletBinding()]
param(
    [string]$OpenAIName,
    [string]$OpenAIResourceGroup,
    [string]$OpenAIDeployment,
    [string]$AcrName,
    [string]$ImageTag = "v1",
    [switch]$SkipOpenAI,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

if (-not (Test-Command "az")) {
    Write-ErrLine "Azure CLI (az) not found. Run .\00-Prerequisites.ps1 first."
    exit 1
}

$config = Read-A365Config
if (-not $config) {
    Write-ErrLine "a365.config.json not found. Run .\01-Select-AzureContext.ps1 first."
    exit 1
}

$agentName = $config.agentName
$subId     = $config.subscriptionId
$rg        = $config.resourceGroup
$location  = $config.location
$devRoot   = Get-DevRoot

if (-not $OpenAIResourceGroup) { $OpenAIResourceGroup = $rg }

# Resolve the chat deployment name: param -> .env -> gpt-4o.
if (-not $OpenAIDeployment) {
    $envPath = Join-Path $devRoot ".env"
    if (Test-Path $envPath) {
        $line = Select-String -Path $envPath -Pattern '^\s*AZURE_OPENAI_DEPLOYMENT\s*=' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($line) { $OpenAIDeployment = ($line.Line -split '=', 2)[1].Trim().Trim('"') }
    }
    if (-not $OpenAIDeployment) { $OpenAIDeployment = "gpt-4o" }
}

# Derive resource names (globally-unique where required).
$safeName = ($agentName -replace '[^a-zA-Z0-9]', '').ToLower()
if (-not $safeName) { $safeName = "agent" }
$suffix   = Get-Random -Maximum 99999
if (-not $AcrName) {
    $AcrName = "acr$safeName$suffix"
    if ($AcrName.Length -gt 50) { $AcrName = $AcrName.Substring(0, 50) }
}
$planName = "asp-$safeName-ctr"
$appName  = "app-$safeName-ctr-$suffix"
$imageRepo = "agent365-langchain"
$imageRef  = "$AcrName.azurecr.io/${imageRepo}:$ImageTag"
$messagingEndpoint = "https://$appName.azurewebsites.net/api/messages"

Write-Step "Container deployment plan"
Write-Host "    Agent           : $agentName"
Write-Host "    Subscription    : $subId"
Write-Host "    Resource group  : $rg ($location)"
Write-Host "    ACR             : $AcrName"
Write-Host "    Image           : $imageRef"
Write-Host "    App Service Plan: $planName (Linux, B1)"
Write-Host "    Web App         : $appName"
if ($SkipOpenAI) {
    Write-Host "    Azure OpenAI    : (skipped)"
}
else {
    Write-Host "    Azure OpenAI    : $OpenAIName / $OpenAIResourceGroup  deployment=$OpenAIDeployment"
}
Write-Host "    Messaging URL   : $messagingEndpoint"
Write-Host ""

if ($DryRun) {
    Write-WarnLine "Dry run: no resources created."
    return
}

Invoke-Native "az" @("account", "set", "--subscription", $subId)

# ---------------------------------------------------------------------------
# 1. Container registry + server-side image build
# ---------------------------------------------------------------------------
$acrExists = az acr list --resource-group $rg --query "[?name=='$AcrName'].name | [0]" -o tsv
if (-not $acrExists) {
    Write-Step "Creating Azure Container Registry (Basic, admin disabled)"
    Invoke-Native "az" @(
        "acr", "create", "--name", $AcrName, "--resource-group", $rg,
        "--sku", "Basic", "--admin-enabled", "false", "--only-show-errors"
    )
}
else {
    Write-Ok "Reusing existing ACR '$AcrName'."
}

Write-Step "Building image with ACR Tasks ('az acr build')"
Invoke-Native "az" @(
    "acr", "build", "--registry", $AcrName,
    "--image", "${imageRepo}:$ImageTag", $devRoot
)

# ---------------------------------------------------------------------------
# 2. App Service Plan + Web App for Containers
# ---------------------------------------------------------------------------
Write-Step "Creating App Service Plan (Linux, B1)"
Invoke-Native "az" @(
    "appservice", "plan", "create", "--name", $planName, "--resource-group", $rg,
    "--sku", "B1", "--is-linux", "--only-show-errors"
)

Write-Step "Creating Web App for Containers"
Invoke-Native "az" @(
    "webapp", "create", "--name", $appName, "--resource-group", $rg,
    "--plan", $planName, "--container-image-name", $imageRef, "--only-show-errors"
)

# ---------------------------------------------------------------------------
# 3. Managed Identity + keyless ACR pull (no admin creds / secrets)
# ---------------------------------------------------------------------------
Write-Step "Enabling system-assigned Managed Identity"
Invoke-Native "az" @("webapp", "identity", "assign", "--name", $appName, "--resource-group", $rg, "--only-show-errors")
$principalId = az webapp identity show --name $appName --resource-group $rg --query "principalId" -o tsv
if (-not $principalId) { throw "Failed to read the web app Managed Identity principalId." }

Write-Step "Granting AcrPull to the Managed Identity"
$acrId = az acr show -n $AcrName -g $rg --query "id" -o tsv
Invoke-Native "az" @(
    "role", "assignment", "create", "--assignee-object-id", $principalId,
    "--assignee-principal-type", "ServicePrincipal",
    "--role", "AcrPull", "--scope", $acrId, "--only-show-errors"
)

Write-Step "Pointing the web app at the ACR image using the Managed Identity"
# Set acrUseManagedIdentityCreds via 'az resource update' (avoids passing inline
# JSON to --generic-configurations, which PowerShell mangles by stripping quotes).
Invoke-Native "az" @(
    "resource", "update", "--resource-group", $rg, "--namespace", "Microsoft.Web",
    "--parent", "sites/$appName", "--resource-type", "config", "--name", "web",
    "--set", "properties.acrUseManagedIdentityCreds=true", "--only-show-errors"
)
Invoke-Native "az" @(
    "webapp", "config", "container", "set", "--name", $appName, "--resource-group", $rg,
    "--container-image-name", $imageRef,
    "--container-registry-url", "https://$AcrName.azurecr.io", "--only-show-errors"
)

# ---------------------------------------------------------------------------
# 4. App settings (keyless Azure OpenAI via Managed Identity) + data-plane role
# ---------------------------------------------------------------------------
$settings = @("WEBSITES_PORT=8000")
if (-not $SkipOpenAI -and $OpenAIName) {
    $aoaiEndpoint = az cognitiveservices account show -n $OpenAIName -g $OpenAIResourceGroup --query "properties.endpoint" -o tsv 2>$null
    if (-not $aoaiEndpoint) {
        Write-WarnLine "Could not resolve endpoint for Azure OpenAI '$OpenAIName' in '$OpenAIResourceGroup'. Set AZURE_OPENAI_ENDPOINT manually."
    }
    else {
        $settings += @(
            "AZURE_OPENAI_ENDPOINT=$aoaiEndpoint",
            "AZURE_OPENAI_DEPLOYMENT=$OpenAIDeployment",
            "AZURE_OPENAI_AUTH_MODE=entra",
            # Force Managed Identity: the agent's DefaultAzureCredential excludes MI unless told.
            "AZURE_OPENAI_CREDENTIAL=managed"
        )
    }
}

Write-Step "Applying app settings"
Invoke-Native "az" (@(
    "webapp", "config", "appsettings", "set", "--name", $appName, "--resource-group", $rg,
    "--settings") + $settings + @("--only-show-errors"))

if (-not $SkipOpenAI -and $OpenAIName) {
    Write-Step "Granting 'Cognitive Services OpenAI User' to the Managed Identity"
    $aoaiId = az cognitiveservices account show -n $OpenAIName -g $OpenAIResourceGroup --query "id" -o tsv 2>$null
    if ($aoaiId) {
        Invoke-Native "az" @(
            "role", "assignment", "create", "--assignee-object-id", $principalId,
            "--assignee-principal-type", "ServicePrincipal",
            "--role", "Cognitive Services OpenAI User", "--scope", $aoaiId, "--only-show-errors"
        )
    }
    else {
        Write-WarnLine "Skipped OpenAI role assignment (resource id not resolved)."
    }
}

Write-Step "Restarting the web app to pull the image and apply settings"
Invoke-Native "az" @("webapp", "restart", "--name", $appName, "--resource-group", $rg, "--only-show-errors")

# ---------------------------------------------------------------------------
# 5. State file for cleanup + summary
# ---------------------------------------------------------------------------
$state = [ordered]@{
    subscriptionId = $subId
    resourceGroup  = $rg
    appName        = $appName
    planName       = $planName
    acrName        = $AcrName
    image          = $imageRef
    messagingEndpoint = $messagingEndpoint
    createdUtc     = (Get-Date).ToUniversalTime().ToString("o")
}
$statePath = Join-Path $PSScriptRoot "last-container-deploy.json"
$state | ConvertTo-Json -Depth 5 | Set-Content -Path $statePath -Encoding UTF8

Write-Host ""
Write-Ok "Container deployed."
Write-Host "    App URL          : https://$appName.azurewebsites.net"
Write-Host "    Swagger UI        : https://$appName.azurewebsites.net/docs"
Write-Host "    Health            : https://$appName.azurewebsites.net/health"
Write-Host "    Messaging (A365)  : $messagingEndpoint"
Write-Host "    Cleanup state     : $statePath"
Write-Host ""
Write-Host "    Next (Agent 365 onboarding, same as guida cliente):" -ForegroundColor DarkGray
Write-Host "      a365 setup all --m365 --messaging-endpoint $messagingEndpoint" -ForegroundColor DarkGray
Write-Host "      a365 setup permissions bot ; a365 publish" -ForegroundColor DarkGray
