param(
  [string]$App = "app-mairehelpdesk-27362",
  [string]$Rg = "rg-agent365-demo"
)
$ErrorActionPreference = "Stop"
$tmp = Join-Path $env:TEMP "maire-logs.zip"
az webapp log download -n $App -g $Rg --log-file $tmp | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
$entry = $zip.Entries | Where-Object { $_.FullName -like "*app-stderr.log" }
if ($entry) {
  $sr = New-Object System.IO.StreamReader($entry.Open())
  Write-Host "===== app-stderr.log ====="
  Write-Host ($sr.ReadToEnd())
  $sr.Close()
}
else {
  Write-Host "app-stderr.log NOT FOUND. Log files present:"
  $zip.Entries | Where-Object { $_.FullName -like "*.log" } |
    Select-Object FullName, Length | Format-Table -Auto | Out-String | Write-Host
}
$zip.Dispose()
