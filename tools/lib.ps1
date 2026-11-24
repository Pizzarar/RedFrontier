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

# ---- first-run helpers (pure; tested by tools/test-firstrun.ps1) ----
function Test-CfxKey([string]$Key) { [bool]($Key -cmatch '^cfxk_[A-Za-z0-9_]{16,80}$') }

# Returns the sv_licenseKey value in a secrets.cfg, or $null if absent.
function Get-SecretsKey([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    foreach ($l in [IO.File]::ReadAllLines($Path)) { if ($l -match '^\s*sv_licenseKey\s+"([^"]*)"') { return $Matches[1] } }
    $null
}
# Sets sv_licenseKey in the file, preserving every other line. UTF-8 without BOM.
function Set-SecretsKey([string]$Path, [string]$Key) {
    $lines = @(); if (Test-Path $Path) { $lines = @([IO.File]::ReadAllLines($Path)) }
    $new = "sv_licenseKey `"$Key`""; $done = $false
    $out = foreach ($l in $lines) {
        if ($l -match '^\s*sv_licenseKey\b') { if (-not $done) { $new; $done = $true } } else { $l }
    }
    $out = @($out); if (-not $done) { $out += $new }
    [IO.File]::WriteAllText($Path, (($out -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
}
# Creates server/admins.cfg and server/allowlist.cfg (gitignored) with a comment header when missing, so server.cfg's
# `exec` never errors. Never touches an existing file. Called by first-run.ps1 and start-server.ps1.
function Initialize-AccessCfgs([string]$Dir = $Server) {
    $headers = @{
        'admins.cfg'    = "# Owner admin (gitignored). fh_core auto-admin appends the first joiner here:`n#   add_principal identifier.license:<hash> group.admin`n# Delete the line and restart to revoke.`n"
        'allowlist.cfg' = "# Friend allowlist (gitignored). fh_allow <license> appends here; or add by hand:`n#   add_principal identifier.license:<hash> group.fh_allowlist`n# Delete a line and restart to revoke.`n"
    }
    foreach ($n in 'admins.cfg', 'allowlist.cfg') {
        $p = Join-Path $Dir $n
        if (-not (Test-Path $p)) {
            [IO.File]::WriteAllText($p, $headers[$n], (New-Object Text.UTF8Encoding $false))
            Write-Host "[access] created $n"
        }
    }
}
# Picks the host's NordVPN Meshnet IP from Get-NetIPAddress-shaped objects: a 100.64.0.0/10 address on a NordLynx/Meshnet
# adapter (a stale Tailscale 100.x adapter is ignored). Falls back to Media-Host's known Meshnet IP.
function Get-MeshnetIp($Addresses, [string]$Fallback = '100.102.50.11') {
    if (-not $Addresses) { return $Fallback }
    $m = @($Addresses | Where-Object {
        $_ -and $_.IPAddress -match '^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.' -and $_.InterfaceAlias -match 'NordLynx|Meshnet'
    } | Select-Object -ExpandProperty IPAddress)
    if ($m) { return $m[0] }
    return $Fallback
}

# Classifies boot-log lines: 'license' | 'error' | 'ok' | 'pending'. Shared by boot-check and first-run.
$script:BootErrPat = 'SCRIPT ERROR|Couldn''t start resource|Couldn''t find resource|Failed to load|ECONNREFUSED|Unable to establish connection|Access denied for user'
function Get-BootState([string[]]$Lines, [string[]]$Expected) {
    if ($Lines | Where-Object { $_ -match 'license key|svadhesive.*(Error|Fatal)' -and $_ -match 'Error|Fatal|Invalid|invalid' }) { return 'license' }
    if ($Lines | Where-Object { $_ -match $script:BootErrPat }) { return 'error' }
    $started = @($Lines | ForEach-Object { if ($_ -match 'Started resource (\S+)') { $Matches[1] } })
    $missing = @($Expected | Where-Object { $_ -notin $started })
    $dbOk = [bool]($Lines | Where-Object { $_ -match 'Database server connection established' -or ($_ -match 'oxmysql' -and $_ -match 'connection established') })
    if (-not $missing -and $dbOk) { return 'ok' }
    'pending'
}
