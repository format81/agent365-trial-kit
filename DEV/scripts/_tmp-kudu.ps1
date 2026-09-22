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
  if ($r.Output) { Write-Host "STDOUT:"; Write-Host $r.Output }
  if ($r.Error) { Write-Host "STDERR:"; Write-Host $r.Error }
}

Write-Host "===== venv python version ====="
Invoke-Kudu "antenv/bin/python --version"

Write-Host "`n===== pip list (key pkgs) ====="
Invoke-Kudu "antenv/bin/pip list 2>&1 | grep -Ei 'langchain|fastapi|uvicorn|pydantic|azure-identity|openai'"

Write-Host "`n===== import src.app (real traceback) ====="
Invoke-Kudu "antenv/bin/python -c 'import src.app' 2>&1"
