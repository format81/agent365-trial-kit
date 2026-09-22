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

$inner = "cd /tmp && rm -rf diag && mkdir diag && cd diag && " +
  "cp /home/site/wwwroot/output.tar.zst . && " +
  "(tar --zstd -xf output.tar.zst 2>/dev/null || tar -I zstd -xf output.tar.zst) && " +
  "echo '== ls ==' && ls -la && " +
  "echo '== python ==' && ls -la antenv/bin/python* 2>&1 | head -3 && " +
  "echo '== import ==' && ./antenv/bin/python -c 'import src.app; print(chr(73)+chr(75))' 2>&1"

$cmd = "bash -c " + '"' + ($inner -replace '"', '\"') + '"'
$body = @{ command = $cmd; dir = "/home" } | ConvertTo-Json
$r = Invoke-RestMethod -Uri $scm -Method Post -Headers @{ Authorization = "Basic $b64" } `
  -Body $body -ContentType "application/json" -TimeoutSec 300
Write-Host "--- ExitCode: $($r.ExitCode) ---"
if ($r.Output) { Write-Host $r.Output }
if ($r.Error) { Write-Host "STDERR:"; Write-Host $r.Error }
