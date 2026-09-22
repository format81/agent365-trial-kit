param(
  [string]$App = "app-mairehelpdesk-27362",
  [string]$Rg = "rg-agent365-demo"
)
$ErrorActionPreference = "Stop"
$creds = az webapp deployment list-publishing-credentials -n $App -g $Rg `
  --query "{u:publishingUserName, p:publishingPassword}" -o json | ConvertFrom-Json
$pair = "{0}:{1}" -f $creds.u, $creds.p
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$base = "https://$App.scm.azurewebsites.net/api/vfs/LogFiles/"
$h = @{ Authorization = "Basic $b64" }

Write-Host "===== /home/LogFiles listing ====="
try {
  $list = Invoke-RestMethod -Uri $base -Headers $h -Method Get
  $list | Select-Object name, size, mtime | Sort-Object mtime | Format-Table -Auto | Out-String | Write-Host
}
catch { Write-Host "list failed: $($_.Exception.Message)" }

foreach ($f in @("uvi.log", "app-stderr.log")) {
  Write-Host "`n===== $f ====="
  try {
    $c = Invoke-RestMethod -Uri ($base + $f) -Headers $h -Method Get
    Write-Host $c
  }
  catch { Write-Host "read failed: $($_.Exception.Message)" }
}
