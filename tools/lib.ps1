# Shared helpers (dot-sourced by setup/start/stop). Paths are relative to the repo.
$script:Root    = Split-Path $PSScriptRoot -Parent
$script:Server  = Join-Path $Root 'server'
$script:DbDir   = Join-Path $Server 'db'
$script:DbData  = Join-Path $DbDir 'data'
$script:DbPort  = Join-Path $DbDir 'port.txt'
$script:Tmp     = Join-Path $PSScriptRoot '.tmp'
$script:Fx      = Join-Path $Server 'artifacts\FXServer.exe'
$script:LogDir  = Join-Path $Server 'logs'

function Get-MariaBin {
    $d = Get-ChildItem (Join-Path $DbDir 'mariadb') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $d) { throw 'MariaDB not installed; run tools/setup-server.ps1' }
    Join-Path $d.FullName 'bin'
}
function Get-DbPort { [int](Get-Content $DbPort -ErrorAction Stop | Select-Object -First 1) }
function Test-DbUp {
    $p = Get-DbPort
    $c = New-Object Net.Sockets.TcpClient
    try { $c.Connect('127.0.0.1', $p); $true } catch { $false } finally { $c.Close() }
}
function Start-Db {
    if (Test-DbUp) { return }
    $bin = Get-MariaBin
    New-Item -ItemType Directory -Force $LogDir | Out-Null
    $port = Get-DbPort
    $dbArgs = @("--datadir=$DbData", "--port=$port", '--bind-address=127.0.0.1', '--console', '--skip-name-resolve')
    Start-Process -FilePath (Join-Path $bin 'mariadbd.exe') -ArgumentList $dbArgs -WindowStyle Hidden `
        -RedirectStandardError (Join-Path $LogDir 'mariadb.log') | Out-Null
    for ($i = 0; $i -lt 60; $i++) { if (Test-DbUp) { return }; Start-Sleep -Milliseconds 500 }
    throw 'MariaDB did not come up; see server/logs/mariadb.log'
}
function Stop-Db {
    $bin = Get-MariaBin
    if (Test-DbUp) {
        & (Join-Path $bin 'mariadb-admin.exe') -uroot --protocol=tcp '-h127.0.0.1' "-P$(Get-DbPort)" shutdown 2>&1 | Out-Null
        for ($i = 0; $i -lt 40 -and (Test-DbUp); $i++) { Start-Sleep -Milliseconds 500 }
    }
}
