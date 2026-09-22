. "$PSScriptRoot\Common.ps1"
$devRoot = (Resolve-Path "$PSScriptRoot\..").Path
$z = Join-Path $env:TEMP "test-fwdslash.zip"
New-DeploymentZip -SourceDir $devRoot -DestinationPath $z `
  -Exclude @(".venv", "__pycache__", "scripts", ".git", "node_modules") `
  -ExcludeFile @(".env") -ExcludeExtension @(".pyc", ".zip")
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($z)
Write-Host "== src entries =="
$zip.Entries | Where-Object { $_.FullName -like "src*" } | ForEach-Object { $_.FullName }
Write-Host "== entries containing backslash (should be 0) =="
($zip.Entries | Where-Object { $_.FullName -like "*\*" } | Measure-Object).Count
$zip.Dispose()
