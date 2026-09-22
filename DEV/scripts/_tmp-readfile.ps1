param(
  [string]$App = "app-mairehelpdesk-27362",
  [string]$Rg = "rg-agent365-demo",
  [string]$Match = "*uvi.log"
)
$ErrorActionPreference = "Stop"
$tmp = Join-Path $env:TEMP ("maire-" + (Get-Random) + ".zip")
az webapp log download -n $App -g $Rg --log-file $tmp 2>$null | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
$entry = $zip.Entries | Where-Object { $_.FullName -like $Match }
if ($entry) {
  $sr = New-Object System.IO.StreamReader($entry.Open())
  Write-Host "===== $($entry.FullName) ($($entry.Length) bytes) ====="
  Write-Host ($sr.ReadToEnd())
  $sr.Close()
}
else {
  Write-Host "NOT FOUND ($Match). Present .log files:"
  $zip.Entries | Where-Object { $_.FullName -like "*.log" } |
    Select-Object @{n = 'F'; e = { $_.FullName } }, Length | Format-Table -Auto | Out-String | Write-Host
}
$zip.Dispose()
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
