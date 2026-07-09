<#
.SYNOPSIS
    Checks (and optionally installs) the prerequisites for developing and
    onboarding a LangChain agent to Microsoft Agent 365.

.DESCRIPTION
    Verifies:
      - Python 3.10+
      - Azure CLI (az)
      - .NET SDK 8.0+ (required by the Agent 365 CLI)
      - Agent 365 CLI (a365)  -> NuGet: Microsoft.Agents.A365.DevTools.Cli

    Use -Install to attempt automatic installation of the Agent 365 CLI and the
    Python dependencies.

    NOTE: Microsoft Agent 365 is in PREVIEW.

.EXAMPLE
    .\00-Prerequisites.ps1

.EXAMPLE
    .\00-Prerequisites.ps1 -Install
#>
[CmdletBinding()]
param(
    [switch]$Install
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\Common.ps1"

Write-Step "Checking prerequisites for Agent 365 development (PREVIEW)"

$allOk = $true

# --- Python ---
if (Test-Command "python") {
    $pyVersion = (python --version) 2>&1
    Write-Ok "Python found: $pyVersion"
}
else {
    $allOk = $false
    Write-ErrLine "Python not found. Install Python 3.10+ from https://www.python.org/downloads/"
}

# --- Azure CLI ---
if (Test-Command "az") {
    Write-Ok "Azure CLI found."
}
else {
    $allOk = $false
    Write-ErrLine "Azure CLI not found. Install from https://learn.microsoft.com/cli/azure/install-azure-cli"
}

# --- .NET SDK (needed for the Agent 365 CLI global tool) ---
if (Test-Command "dotnet") {
    $dotnetVersion = (dotnet --version) 2>&1
    Write-Ok ".NET SDK found: $dotnetVersion"
}
else {
    $allOk = $false
    Write-ErrLine ".NET SDK 8.0+ not found. Install from https://learn.microsoft.com/dotnet/core/install/"
}

# --- Agent 365 CLI ---
if (Test-Command "a365") {
    Write-Ok "Agent 365 CLI (a365) found."
}
else {
    Write-WarnLine "Agent 365 CLI (a365) not found."
    if ($Install -and (Test-Command "dotnet")) {
        Write-Step "Installing Agent 365 CLI (dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli)"
        Invoke-Native "dotnet" @("tool", "install", "--global", "Microsoft.Agents.A365.DevTools.Cli")
        Write-Ok "Agent 365 CLI installed. Restart the shell if 'a365' is not yet on PATH."
    }
    else {
        Write-WarnLine "Run with -Install (and .NET present) to install it, or run:"
        Write-Host "        dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli" -ForegroundColor DarkGray
    }
}

# --- Python dependencies ---
if ($Install -and (Test-Command "python")) {
    Write-Step "Installing Python dependencies (requirements.txt)"
    $req = Join-Path (Get-DevRoot) "requirements.txt"
    Invoke-Native "python" @("-m", "pip", "install", "-r", $req)
    Write-Ok "Python dependencies installed."
}

Write-Host ""
if ($allOk) {
    Write-Ok "Core prerequisites satisfied. Next: .\01-Select-AzureContext.ps1"
}
else {
    Write-ErrLine "One or more prerequisites are missing. Install them and re-run."
    exit 1
}
