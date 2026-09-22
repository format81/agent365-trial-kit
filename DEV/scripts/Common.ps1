<#
    Common helper functions shared by the Agent 365 trial scripts.
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
    <#
        Returns $true if a command/executable is available on PATH.
    #>
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-DevRoot {
    <#
        Absolute path to the DEV folder (parent of the scripts folder).
    #>
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-ConfigPath {
    return (Join-Path (Get-DevRoot) "a365.config.json")
}

function Read-A365Config {
    <#
        Loads a365.config.json as a PSCustomObject, or $null if it doesn't exist.
    #>
    $path = Get-ConfigPath
    if (-not (Test-Path $path)) { return $null }
    return Get-Content $path -Raw | ConvertFrom-Json
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

function Read-Selection {
    <#
        Prompts for a numeric index and validates it against a collection.
        Re-prompts until a valid 0-based index is entered. Returns the index.
    #>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][int]$Count
    )
    while ($true) {
        $raw = Read-Host $Prompt
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 0 -and $n -lt $Count) {
            return $n
        }
        Write-WarnLine "Enter a number between 0 and $($Count - 1)."
    }
}

function New-DeploymentZip {
    <#
        Creates a zip whose entry names use forward slashes so the archive
        extracts correctly on Linux / Azure App Service (Oryx). Windows'
        Compress-Archive writes backslash separators, which Linux treats as
        literal filename characters - so 'src\app.py' never becomes the 'src'
        package and the app dies with ModuleNotFoundError: No module named 'src'.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string[]]$Exclude = @(),
        [string[]]$ExcludeFile = @(),
        [string[]]$ExcludeExtension = @()
    )
    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

    $rootFull = (Resolve-Path $SourceDir).Path.TrimEnd('\', '/')
    if (Test-Path $DestinationPath) { Remove-Item $DestinationPath -Force }

    $fs = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create)
    $archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem -Path $SourceDir -Recurse -File -Force | ForEach-Object {
            $rel = $_.FullName.Substring($rootFull.Length + 1)
            $segments = $rel -split '[\\/]'
            if ($segments | Where-Object { $Exclude -contains $_ }) { return }
            if ($ExcludeFile -contains $_.Name) { return }
            if ($ExcludeExtension -contains $_.Extension) { return }
            $entryName = ($segments -join '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $entryName) | Out-Null
        }
    }
    finally {
        $archive.Dispose()
        $fs.Dispose()
    }
}
