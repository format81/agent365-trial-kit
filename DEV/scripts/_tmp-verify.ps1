param(
  [string]$App = "app-mairehelpdesk-27362",
  [string]$Rg = "rg-agent365-demo"
)
$ErrorActionPreference = "Continue"
Write-Host "== latest deployment =="
az webapp log deployment show -n $App -g $Rg --query "[0].{status:status, message:message}" -o json 2>$null
Write-Host "== app state =="
az webapp show -n $App -g $Rg --query "state" -o tsv
Write-Host "== HTTP /health =="
try {
  $r = Invoke-WebRequest -Uri "https://$App.azurewebsites.net/health" -TimeoutSec 60 -UseBasicParsing
  Write-Host "Status: $($r.StatusCode)"
  Write-Host $r.Content
}
catch {
  Write-Host "health failed: $($_.Exception.Message)"
  if ($_.Exception.Response) { Write-Host "HTTP $([int]$_.Exception.Response.StatusCode)" }
}
