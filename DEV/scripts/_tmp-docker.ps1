param(
  [string]$App = "app-mairehelpdesk-27362",
  [string]$Rg = "rg-agent365-demo",
  [string]$File = "2026_09_22_lw0sdlwk0002AJ_docker.log"
)
$ErrorActionPreference = "Stop"
$creds = az webapp deployment list-publishing-credentials -n $App -g $Rg `
  --query "{u:publishingUserName, p:publishingPassword}" -o json | ConvertFrom-Json
$pair = "{0}:{1}" -f $creds.u, $creds.p
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$uri = "https://$App.scm.azurewebsites.net/api/vfs/LogFiles/$File"
$h = @{ Authorization = "Basic $b64" }
$c = Invoke-RestMethod -Uri $uri -Headers $h -Method Get
$lines = $c -split "`n"
Write-Host "total lines: $($lines.Count)"
Write-Host "===== lines matching python/traceback/error/uvicorn/module ====="
$lines | Select-String -Pattern "Traceback|Error|Exception|uvicorn|gunicorn|ModuleNotFound|No module|ImportError|RuntimeError|line \d+|Warning: Could not|python" |
  Select-Object -Last 60 | ForEach-Object { $_.Line }
