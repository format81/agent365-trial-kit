<#
    Common helper functions shared by the Day 10 BYO MCP scripts.
    Dot-source this file:  . "$PSScriptRoot\Common.ps1"
#>

Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-WarnLine {
    param([string]$Message)
    Write-Host "    [!]  $Message" -ForegroundColor Yellow
}

function Write-ErrLine {
    param([string]$Message)
    Write-Host "    [X]  $Message" -ForegroundColor Red
}

function Test-Command {
    <# Returns $true if a command/executable is available on PATH. #>
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Native {
    <#
        Runs an external command, echoes it, and throws on non-zero exit.
        Usage: Invoke-Native az @('account','show')
    #>
    param(
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    Write-Host "    > $File $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($File $($Arguments -join ' ')) with exit code $LASTEXITCODE."
    }
}

function Get-DeployStatePath {
    <# Path to the JSON file that records the last deployment (for cleanup). #>
    return (Join-Path $PSScriptRoot "last-deploy.json")
}

function Save-DeployState {
    param([Parameter(Mandatory)][hashtable]$State)
    $path = Get-DeployStatePath
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $path -Encoding utf8
    Write-Ok "Saved deployment state to $path"
}

function Read-DeployState {
    $path = Get-DeployStatePath
    if (-not (Test-Path $path)) { return $null }
    return Get-Content $path -Raw | ConvertFrom-Json
}
