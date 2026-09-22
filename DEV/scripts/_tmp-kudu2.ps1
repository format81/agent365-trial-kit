param(
  [string]$App = "app-mairehelpdesk-27362",
  [string]$Rg = "rg-agent365-demo"
)
$ErrorActionPreference = "Stop"

$creds = az webapp deployment list-publishing-credentials -n $App -g $Rg `
  --query "{u:publishingUserName, p:publishingPassword}" -o json | ConvertFrom-Json
$pair = "{0}:{1}" -f $creds.u, $creds.p
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$scm = "https://$App.scm.azurewebsites.net/api/command"

function Invoke-Kudu([string]$cmd) {
  $body = @{ command = $cmd; dir = "/home/site/wwwroot" } | ConvertTo-Json
  $r = Invoke-RestMethod -Uri $scm -Method Post -Headers @{ Authorization = "Basic $b64" } `
    -Body $body -ContentType "application/json"
  Write-Host "--- ExitCode: $($r.ExitCode) ---"
  if ($r.Output) { Write-Host $r.Output }
  if ($r.Error) { Write-Host "STDERR:"; Write-Host $r.Error }
}

Write-Host "===== wwwroot listing ====="
Invoke-Kudu "ls -la /home/site/wwwroot"

Write-Host "`n===== find any venv / site-packages ====="
Invoke-Kudu "ls -la /home/site/wwwroot/antenv 2>&1; echo '---'; find /tmp -maxdepth 3 -name 'antenv' -type d 2>/dev/null; echo '---oryx manifest---'; cat /home/site/wwwroot/oryx-manifest.toml 2>&1 | head -40"

Write-Host "`n===== system python + can it import fastapi? ====="
Invoke-Kudu "python --version; python -c 'import fastapi' 2>&1 | head -5"
