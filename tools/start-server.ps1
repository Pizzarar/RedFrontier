# Starts MariaDB (if down) then FXServer (no txAdmin). Ctrl+C or stop-server.ps1 to stop.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
if (-not (Test-Path $Fx)) { throw 'Run tools/setup-server.ps1 first' }
Start-Db
New-Item -ItemType Directory -Force $LogDir | Out-Null
$log = Join-Path $LogDir 'fxserver.log'
Write-Host "FXServer starting; log: $log"
Push-Location $Server
try { & $Fx +exec server.cfg 2>&1 | Tee-Object -FilePath $log } finally { Pop-Location }
