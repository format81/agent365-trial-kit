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

function Invoke-Kudu([string]$cmd, [string]$dir = "/home") {
  $body = @{ command = $cmd; dir = $dir } | ConvertTo-Json
  $r = Invoke-RestMethod -Uri $scm -Method Post -Headers @{ Authorization = "Basic $b64" } `
    -Body $body -ContentType "application/json" -TimeoutSec 300
  Write-Host "--- ExitCode: $($r.ExitCode) ---"
  if ($r.Output) { Write-Host $r.Output }
  if ($r.Error) { Write-Host "STDERR:"; Write-Host $r.Error }
}

$script = @'
set -e
rm -rf /tmp/diag && mkdir -p /tmp/diag && cd /tmp/diag
cp /home/site/wwwroot/output.tar.zst .
( tar --zstd -xf output.tar.zst 2>/dev/null || tar -I zstd -xf output.tar.zst 2>/dev/null || (zstd -d output.tar.zst -o output.tar && tar -xf output.tar) )
echo "== top-level =="
ls -la
echo "== has antenv python? =="
ls -la antenv/bin/python* 2>&1 | head
echo "== import src.app =="
./antenv/bin/python -c "import src.app; print('IMPORT OK')" 2>&1
'@
$oneLine = ($script -split "`r?`n" | Where-Object { $_ -ne "" }) -join "; "
Invoke-Kudu $oneLine "/home"
