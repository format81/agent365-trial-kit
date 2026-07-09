<#
.SYNOPSIS
    Provisions Azure resources, deploys the LangChain agent to Azure App Service,
    and onboards it to Microsoft Agent 365 so it becomes a first-class tenant
    citizen. The registration progress is shown live in the shell.

.DESCRIPTION
    End-to-end flow (uses the real Agent 365 CLI + Azure CLI):
      1. Reads a365.config.json (tenant, subscription, resource group, region).
      2. 'a365 setup all' -> creates the Entra Agent ID blueprint, configures
         permissions, creates the Agent Identity, and REGISTERS the agent via the
         Agent 365 registration API. You watch this happen in the terminal.
      3. Provisions an App Service Plan + Web App (Linux, Python).
      4. Deploys the agent code (zip deploy) and sets the startup command.
      5. Registers the messaging endpoint with the blueprint (post-deploy step).

    NOTE: Microsoft Agent 365 is in PREVIEW. Command surface may change; run
    'a365 setup all -h' to confirm options for your CLI version.

    Roles: Azure Contributor + Agent ID Developer (Global Administrator needed for
    OAuth2 admin consent; otherwise the CLI prints the GA hand-off steps).

.PARAMETER AuthMode
    Agent identity grant type: obo (default), s2s, or both.

.PARAMETER SkipInfra
    Skip Azure App Service provisioning/deploy (only run Agent 365 onboarding).

.PARAMETER SkipOnboard
    Skip Agent 365 onboarding (only provision/deploy to Azure).

.PARAMETER DryRun
    Preview Agent 365 CLI actions with --dry-run.

.PARAMETER SkipBotPermissions
    Skip 'a365 setup permissions bot' (Observability + Power Platform grants).

.PARAMETER ConfigureMcpPermissions
    Also run 'a365 setup permissions mcp' (only needed when the agent uses MCP /
    Work IQ tools declared in ToolingManifest.json).

.PARAMETER OpenAIName
    Azure OpenAI resource name. If omitted, the App Service app settings and the
    Managed Identity role assignment for keyless auth are skipped.

.PARAMETER OpenAIResourceGroup
    Resource group of the Azure OpenAI resource. Defaults to the config resource
    group.

.EXAMPLE
    .\03-Deploy-AndOnboard.ps1

.EXAMPLE
    .\03-Deploy-AndOnboard.ps1 -AuthMode both
#>
[CmdletBinding()]
param(
    [ValidateSet("obo", "s2s", "both")]
    [string]$AuthMode = "obo",
    [switch]$SkipInfra,
    [switch]$SkipOnboard,
    [switch]$SkipBotPermissions,
    [switch]$SkipPublish,
    [switch]$ConfigureMcpPermissions,
    [string]$OpenAIName,
    [string]$OpenAIResourceGroup,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

$config = Read-A365Config
if (-not $config) {
    Write-ErrLine "a365.config.json not found. Run .\01-Select-AzureContext.ps1 first."
    exit 1
}

$agentName = $config.agentName
$tenantId  = $config.tenantId
$subId     = $config.subscriptionId
$rg        = $config.resourceGroup
$location  = $config.location
$devRoot   = Get-DevRoot

Write-Step "Onboarding plan"
Write-Host "    Agent          : $agentName"
Write-Host "    Tenant         : $tenantId"
Write-Host "    Subscription   : $subId"
Write-Host "    Resource group : $rg ($location)"
Write-Host "    Auth mode      : $AuthMode"
Write-Host ""

# Flow (fully automated):
#   1. Provision Azure App Service + deploy the agent code (Oryx build ON).
#   2. Configure app settings + Managed Identity keyless Azure OpenAI access.
#   3. Onboard/register in Agent 365 with the KNOWN messaging endpoint (no prompts).
#   4. Configure Observability/Power Platform (and optionally MCP) permissions.
# Registration happens AFTER deploy so the messaging endpoint already exists and
# the CLI never defers it.

$messagingEndpoint = $null
$webAppName = $null

# ---------------------------------------------------------------------------
# Step 1: Provision Azure App Service and deploy the agent code
# ---------------------------------------------------------------------------
if (-not $SkipInfra) {
    if (-not (Test-Command "az")) {
        Write-ErrLine "Azure CLI (az) not found. Run .\00-Prerequisites.ps1 first."
        exit 1
    }

    $safeName   = ($agentName -replace '[^a-zA-Z0-9]', '').ToLower()
    if (-not $safeName) { $safeName = "agent" }
    $planName   = "asp-$safeName"
    $webAppName = "app-$safeName-$((Get-Random -Maximum 99999))"

    Invoke-Native "az" @("account", "set", "--subscription", $subId)

    if ($DryRun) {
        Write-WarnLine "Dry run: would create plan '$planName' and web app '$webAppName', then deploy."
        $messagingEndpoint = "https://$webAppName.azurewebsites.net/api/messages"
    }
    else {
        Write-Step "Creating App Service Plan (Linux)"
        Invoke-Native "az" @(
            "appservice", "plan", "create",
            "--name", $planName,
            "--resource-group", $rg,
            "--sku", "B1", "--is-linux", "--only-show-errors"
        )

        Write-Step "Creating Web App (Python 3.11)"
        Invoke-Native "az" @(
            "webapp", "create",
            "--name", $webAppName,
            "--resource-group", $rg,
            "--plan", $planName,
            "--runtime", "PYTHON:3.11", "--only-show-errors"
        )

        # Enable Oryx build so 'pip install -r requirements.txt' runs on deploy.
        Write-Step "Enabling build during deployment (Oryx)"
        Invoke-Native "az" @(
            "webapp", "config", "appsettings", "set",
            "--name", $webAppName, "--resource-group", $rg,
            "--settings", "SCM_DO_BUILD_DURING_DEPLOYMENT=true", "ENABLE_ORYX_BUILD=true",
            "--only-show-errors"
        )

        Write-Step "Configuring startup command"
        Invoke-Native "az" @(
            "webapp", "config", "set",
            "--name", $webAppName,
            "--resource-group", $rg,
            "--startup-file", "python -m uvicorn src.app:app --host 0.0.0.0 --port 8000",
            "--only-show-errors"
        )

        Write-Step "Deploying agent code (zip deploy)"
        $zipPath = Join-Path $env:TEMP "agent365-deploy-$safeName.zip"
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

        # Package the deployable files (exclude local/venv artifacts).
        $items = Get-ChildItem -Path $devRoot -Force |
            Where-Object { $_.Name -notin @(".venv", "__pycache__", ".env", "scripts") }
        Compress-Archive -Path $items.FullName -DestinationPath $zipPath -Force

        Invoke-Native "az" @(
            "webapp", "deploy",
            "--name", $webAppName,
            "--resource-group", $rg,
            "--src-path", $zipPath,
            "--type", "zip", "--only-show-errors"
        )

        $messagingEndpoint = "https://$webAppName.azurewebsites.net/api/messages"
        Write-Ok "Deployed. Messaging endpoint: $messagingEndpoint"

        # -------------------------------------------------------------------
        # Step 2: App settings + Managed Identity keyless Azure OpenAI access
        # -------------------------------------------------------------------
        $envPath = Join-Path $devRoot ".env"
        $aoaiEndpoint = $null
        $aoaiDeployment = $null
        if (Test-Path $envPath) {
            foreach ($line in Get-Content $envPath) {
                if ($line -match '^\s*AZURE_OPENAI_ENDPOINT\s*=\s*(.+)$')   { $aoaiEndpoint   = $Matches[1].Trim() }
                if ($line -match '^\s*AZURE_OPENAI_DEPLOYMENT\s*=\s*(.+)$') { $aoaiDeployment = $Matches[1].Trim() }
            }
        }

        Write-Step "Setting App Service application settings (keyless auth)"
        $settings = @(
            "AZURE_OPENAI_AUTH_MODE=entra",
            "AZURE_OPENAI_CREDENTIAL=managed"
        )
        if ($aoaiEndpoint)   { $settings += "AZURE_OPENAI_ENDPOINT=$aoaiEndpoint" }
        if ($aoaiDeployment) { $settings += "AZURE_OPENAI_DEPLOYMENT=$aoaiDeployment" }

        Invoke-Native "az" (@(
            "webapp", "config", "appsettings", "set",
            "--name", $webAppName, "--resource-group", $rg,
            "--settings") + $settings + @("--only-show-errors"))
        Write-Ok "Application settings applied."

        if ($OpenAIName) {
            if (-not $OpenAIResourceGroup) { $OpenAIResourceGroup = $rg }
            Write-Step "Granting keyless Azure OpenAI access to the Web App Managed Identity"
            & (Join-Path $PSScriptRoot "05-Grant-OpenAIAccess.ps1") `
                -OpenAIName $OpenAIName `
                -OpenAIResourceGroup $OpenAIResourceGroup `
                -WebAppName $webAppName
        }
        else {
            Write-WarnLine "OpenAIName not provided: skipped Managed Identity role assignment."
            Write-Host "    Grant it later with:" -ForegroundColor DarkGray
            Write-Host "      .\scripts\05-Grant-OpenAIAccess.ps1 -OpenAIName <name> -OpenAIResourceGroup <rg> -WebAppName $webAppName" -ForegroundColor DarkGray
        }

        Invoke-Native "az" @("webapp", "restart", "--name", $webAppName, "--resource-group", $rg, "--only-show-errors")
        Write-Ok "Web App restarted. Public URL: https://$webAppName.azurewebsites.net"
    }
}
else {
    Write-WarnLine "Skipping Azure provisioning/deploy (-SkipInfra)."
    # Reuse an endpoint already recorded in config, if any.
    if ($config.PSObject.Properties.Name -contains "messagingEndpoint" -and $config.messagingEndpoint) {
        $messagingEndpoint = $config.messagingEndpoint
    }
}

# ---------------------------------------------------------------------------
# Step 3: Onboard + REGISTER in Agent 365 (blueprint + identity + registration)
#         Runs AFTER deploy so the messaging endpoint already exists.
# ---------------------------------------------------------------------------
if (-not $SkipOnboard) {
    if (-not (Test-Command "a365")) {
        Write-ErrLine "Agent 365 CLI (a365) not found. Run .\00-Prerequisites.ps1 -Install first."
        exit 1
    }

    Write-Step "Registering the agent in Agent 365 (a365 setup all)"
    Write-Host "    blueprint -> permissions -> agent identity -> registration." -ForegroundColor DarkGray

    $setupArgs = @("setup", "all", "--authmode", $AuthMode, "--m365", "--verbose")
    if ($messagingEndpoint) { $setupArgs += @("--messaging-endpoint", $messagingEndpoint) }
    if ($DryRun) { $setupArgs += "--dry-run" }

    Push-Location $devRoot
    try {
        if ($DryRun) {
            Invoke-Native "a365" $setupArgs
        }
        else {
            # Pipe 'y' to auto-accept the Observability S2S app-role prompt.
            "y" | & a365 @setupArgs
            if ($LASTEXITCODE -ne 0) {
                Write-WarnLine "a365 setup all returned $LASTEXITCODE. If it reports insufficient privileges, run 'az logout; az login --use-device-code' and retry."
            }
        }
    }
    finally {
        Pop-Location
    }

    Write-Ok "Agent 365 registration finished."

    # -----------------------------------------------------------------------
    # Step 4: Configure blueprint permission grants (Observability / MCP)
    # -----------------------------------------------------------------------
    if (-not $DryRun) {
        Push-Location $devRoot
        try {
            if (-not $SkipBotPermissions) {
                Write-Step "a365 setup permissions bot (Observability + Power Platform)"
                "y" | & a365 @("setup", "permissions", "bot")
                if ($LASTEXITCODE -ne 0) {
                    Write-WarnLine "'a365 setup permissions bot' returned $LASTEXITCODE."
                }
                else { Write-Ok "Bot/Observability permissions configured." }
            }

            if ($ConfigureMcpPermissions) {
                Write-Step "a365 setup permissions mcp (Work IQ tools)"
                & a365 @("setup", "permissions", "mcp")
                if ($LASTEXITCODE -ne 0) {
                    Write-WarnLine "'a365 setup permissions mcp' returned $LASTEXITCODE. Ensure ToolingManifest.json lists your MCP servers."
                }
                else { Write-Ok "MCP permissions configured." }
            }
        }
        finally {
            Pop-Location
        }
    }
}
else {
    Write-WarnLine "Skipping Agent 365 onboarding (-SkipOnboard)."
}

# ---------------------------------------------------------------------------
# Step 5: Publish - package the manifest for the Microsoft 365 admin center
#         Creates manifest/manifest.json + manifest/manifest.zip. The zip must
#         then be uploaded by a Global Admin (Agents > Upload custom agent),
#         which makes the agent appear in the registry and lets you create the
#         agent identity instance.
# ---------------------------------------------------------------------------
if (-not $SkipOnboard -and -not $SkipPublish -and -not $DryRun) {
    Push-Location $devRoot
    try {
        Write-Step "a365 publish (package manifest for the admin center)"
        # Feed empty stdin so the CLI never blocks on an interactive prompt.
        "" | & a365 publish
        if ($LASTEXITCODE -ne 0) {
            Write-WarnLine "a365 publish returned $LASTEXITCODE. Review the manifest under .\manifest and re-run."
        }
        else {
            $zip = Join-Path $devRoot "manifest\manifest.zip"
            if (Test-Path $zip) {
                Write-Ok "manifest.zip created: $zip"
                Write-Host "    Final step (Global Admin): upload it at" -ForegroundColor DarkGray
                Write-Host "      https://admin.microsoft.com  ->  Agents  ->  All agents  ->  Upload custom agent" -ForegroundColor DarkGray
                Write-Host "    After upload (5-10 min) the agent appears in the registry and you can create the agent identity instance." -ForegroundColor DarkGray
            }
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host ""
Write-Ok "Done. Your LangChain agent is deployed and onboarded to Agent 365 (PREVIEW)."
if ($webAppName) { Write-Host "    Public URL: https://$webAppName.azurewebsites.net" -ForegroundColor DarkGray }
Write-Host "    Verify the blueprint/identity in the Entra admin center and (after 'a365 publish') the M365 admin center." -ForegroundColor DarkGray
