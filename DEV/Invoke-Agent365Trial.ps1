<#
.SYNOPSIS
    Top-level menu that guides you through developing a LangChain agent and
    onboarding it to Microsoft Agent 365 (PREVIEW).

.DESCRIPTION
    A thin, discoverable wrapper over the numbered scripts in .\scripts. Run it
    with no parameters for an interactive menu, or jump straight to a step with
    -Step.

.PARAMETER Step
    Jump directly to a step: prereqs | context | grant-openai | blueprint | deploy | run-local | cleanup

.EXAMPLE
    .\Invoke-Agent365Trial.ps1

.EXAMPLE
    .\Invoke-Agent365Trial.ps1 -Step blueprint
#>
[CmdletBinding()]
param(
    [ValidateSet("prereqs", "context", "grant-openai", "blueprint", "deploy", "run-local", "cleanup")]
    [string]$Step
)

$ErrorActionPreference = "Stop"
$scripts = Join-Path $PSScriptRoot "scripts"

function Invoke-Prereqs   { & (Join-Path $scripts "00-Prerequisites.ps1") -Install }
function Invoke-Context   { & (Join-Path $scripts "01-Select-AzureContext.ps1") }
function Invoke-GrantOpenAI {
    $name = Read-Host "Azure OpenAI resource name"
    & (Join-Path $scripts "05-Grant-OpenAIAccess.ps1") -OpenAIName $name -GrantUser
}
function Invoke-Blueprint { & (Join-Path $scripts "02-New-AgentBlueprint.ps1") }
function Invoke-Deploy    { & (Join-Path $scripts "03-Deploy-AndOnboard.ps1") }
function Invoke-Cleanup   { & (Join-Path $scripts "04-Cleanup.ps1") -DeleteAppService }

function Invoke-RunLocal {
    Write-Host "Starting the agent locally on http://localhost:8000 ..." -ForegroundColor Cyan
    Push-Location $PSScriptRoot
    try {
        python -m uvicorn src.app:app --reload --port 8000
    }
    finally {
        Pop-Location
    }
}

if ($Step) {
    switch ($Step) {
        "prereqs"      { Invoke-Prereqs }
        "context"      { Invoke-Context }
        "grant-openai" { Invoke-GrantOpenAI }
        "blueprint"    { Invoke-Blueprint }
        "deploy"       { Invoke-Deploy }
        "run-local"    { Invoke-RunLocal }
        "cleanup"      { Invoke-Cleanup }
    }
    return
}

while ($true) {
    Write-Host ""
    Write-Host "================ Agent 365 Trial (PREVIEW) ================" -ForegroundColor Cyan
    Write-Host "  1. Check / install prerequisites"
    Write-Host "  2. Select Azure tenant, subscription, resource group"
    Write-Host "  3. Grant keyless Azure OpenAI access (Entra ID role)"
    Write-Host "  4. Create Entra Agent ID blueprint ONLY (explicit)"
    Write-Host "  5. Deploy to App Service + onboard/register in Agent 365"
    Write-Host "  6. Run the agent locally (dev loop)"
    Write-Host "  7. Clean up (Agent 365 + App Service resources)"
    Write-Host "  q. Quit"
    Write-Host "==========================================================" -ForegroundColor Cyan
    $choice = Read-Host "Select"

    switch ($choice) {
        "1" { Invoke-Prereqs }
        "2" { Invoke-Context }
        "3" { Invoke-GrantOpenAI }
        "4" { Invoke-Blueprint }
        "5" { Invoke-Deploy }
        "6" { Invoke-RunLocal }
        "7" { Invoke-Cleanup }
        "q" { return }
        default { Write-Host "Invalid choice." -ForegroundColor Yellow }
    }
}
