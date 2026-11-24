# One double-click first run (via first-run.cmd): firewall 30120, Cfx key, start server, print the connect line.
# Idempotent. Switches for headless tests: -NoElevate (skip firewall), -KeyFromEnv ($env:FH_CFX_KEY),
# -SecretsPath (default server/secrets.cfg), -CfgDir (default server/), -NoStart (skip server start). The key is never echoed.
[CmdletBinding()]
param(
    [switch]$NoElevate,
    [switch]$KeyFromEnv,
    [switch]$NoStart,
    [switch]$FirewallOnly,   # internal: the elevated child
    [string]$SecretsPath,
    [string]$CfgDir,         # where admins.cfg/allowlist.cfg live (default server/); tests pass a temp dir
    [int]$TimeoutSec = 120
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
if (-not $SecretsPath) { $SecretsPath = Join-Path $Server 'secrets.cfg' }
$Port = 30120

function Get-MissingFwRules {
    # Check our two named rules first; if both exist we're done.
    $missing = foreach ($proto in 'TCP', 'UDP') {
        $name = "RedFrontier FXServer $proto $Port"
        if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
            [pscustomobject]@{ Proto = $proto; Name = $name }
        }
    }
    if (-not $missing) { return }

    # A named rule is missing: fetch every port filter in ONE CIM query (piping every inbound
    # rule into Get-NetFirewallPortFilter is the slow per-rule association query that hangs on
    # PCs with many rules). Keep only the filters that already open this port, then resolve just
    # those few to their rule to confirm it is an enabled inbound allow rule.
    $filters = Get-NetFirewallPortFilter -All -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -contains "$Port" }
    $result = @()
    foreach ($r in @($missing)) {
        $covered = $filters | Where-Object {
            $_.Protocol -eq $r.Proto -and
            (Get-NetFirewallRule -AssociatedNetFirewallPortFilter $_ -Direction Inbound -Action Allow -Enabled True -ErrorAction SilentlyContinue)
        }
        if (-not $covered) { $result += $r }
    }
    $result
}

if ($FirewallOnly) {
    foreach ($r in @(Get-MissingFwRules)) {
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Protocol $r.Proto -LocalPort $Port -Action Allow -Profile Any | Out-Null
        Write-Host "added firewall rule: $($r.Name)"
    }
    return
}

Write-Host '== RedFrontier first run ==' -ForegroundColor Cyan

# ---- 0. Fresh-PC guard ----
# Starting the server needs the FXServer artifact and MariaDB that setup-server.ps1 installs
# (server/artifacts/FXServer.exe, server/db/mariadb). On a fresh PC stop here with a clear pointer
# instead of asking for the key and failing at start. Skipped with -NoStart (tests / key-only runs).
if (-not $NoStart) {
    $haveFx = Test-Path $Fx
    $haveDb = [bool](Get-ChildItem (Join-Path $DbDir 'mariadb') -Directory -ErrorAction SilentlyContinue)
    if (-not $haveFx -or -not $haveDb) {
        Write-Host ''
        Write-Host 'FXServer and MariaDB are not installed yet (fresh PC).' -ForegroundColor Yellow
        Write-Host 'Run tools/setup-server.ps1 first (downloads FXServer + MariaDB, creates the database and secrets.cfg), then run first-run.cmd again.' -ForegroundColor Yellow
        exit 3
    }
}

# ---- 1. Firewall ----
if ($NoElevate) { Write-Host '[firewall] skipped (-NoElevate)' }
else {
    $missing = @(Get-MissingFwRules)
    if (-not $missing) { Write-Host "[firewall] inbound $Port TCP+UDP already open" }
    else {
        Write-Host "[firewall] missing: $($missing.Name -join ', '). Windows will ask for permission (UAC); please accept."
        try {
            $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-FirewallOnly')
            Start-Process powershell -Verb RunAs -ArgumentList $a -Wait
            $left = @(Get-MissingFwRules)
            if ($left) { Write-Host "[firewall] still missing: $($left.Name -join ', '). Continuing; LAN/Tailscale may still work." -ForegroundColor Yellow }
            else { Write-Host '[firewall] rules added' }
        } catch {
            Write-Host '[firewall] UAC declined or failed; continuing (LAN/Tailscale may still work).' -ForegroundColor Yellow
        }
    }
}

# ---- 2. Cfx key ----
$cfg = Join-Path $Server 'server.cfg'
if ((Test-Path $cfg) -and -not (Select-String -Path $cfg -Pattern '^\s*exec\s+secrets\.cfg' -Quiet)) {
    Write-Host '[key] WARNING: server.cfg does not exec secrets.cfg; the key will not be loaded. Not changing it.' -ForegroundColor Yellow
}
function ConvertFrom-Secure([securestring]$s) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
$existing = Get-SecretsKey $SecretsPath
$need = $true
if ($KeyFromEnv) {
    if (-not (Test-CfxKey $env:FH_CFX_KEY)) { throw 'FH_CFX_KEY missing or not a valid cfxk_ key' }
    Set-SecretsKey $SecretsPath $env:FH_CFX_KEY; $need = $false
    Write-Host '[key] written from FH_CFX_KEY'
} elseif (Test-CfxKey $existing) {
    $ans = Read-Host '[key] a valid key is already in secrets.cfg. Keep existing key? [Y/n]'
    if ($ans -notmatch '^\s*n') { $need = $false; Write-Host '[key] kept' }
}
if ($need) {
    $ok = $false
    for ($i = 1; $i -le 3 -and -not $ok; $i++) {
        $k = (ConvertFrom-Secure (Read-Host "[key] paste your Cfx server key (starts with cfxk_; hidden) [$i/3]" -AsSecureString)).Trim()
        if (Test-CfxKey $k) { Set-SecretsKey $SecretsPath $k; $ok = $true; Write-Host '[key] saved to server/secrets.cfg' }
        else { Write-Host '[key] that does not look like a Cfx key (cfxk_ + letters/digits).' -ForegroundColor Yellow }
        $k = $null
    }
    if (-not $ok) { Write-Host 'No valid key entered; stopping. Run first-run.cmd again.' -ForegroundColor Red; exit 2 }
}

# ---- 3. Access cfgs (admins.cfg / allowlist.cfg, created empty if missing) ----
Initialize-AccessCfgs $(if ($CfgDir) { $CfgDir } else { $Server })

# ---- 4. Start ----
if ($NoStart) { Write-Host '[start] skipped (-NoStart)'; return }
$ip = $null
try { $ip = (& tailscale ip -4 2>$null | Select-Object -First 1) } catch {}
if ($ip -notmatch '^\d+\.\d+\.\d+\.\d+$') { $ip = '100.83.196.251' }
$lan = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -match '^(192\.168|10\.|172\.(1[6-9]|2\d|3[01]))\.' -and $_.InterfaceAlias -notmatch 'vEthernet|Loopback' } |
    Select-Object -ExpandProperty IPAddress)

function Show-Connect($state) {
    Write-Host ''
    Write-Host '==================================================================' -ForegroundColor Green
    if ($state -ne 'ok') { Write-Host "  SERVER STATE: $state (see server/logs/fxserver.log)" -ForegroundColor Yellow }
    Write-Host '  On the Main PC: open RedM, press F8, type:' -ForegroundColor Green
    Write-Host ''
    Write-Host "      connect ${ip}:$Port" -ForegroundColor White
    if ($lan) { Write-Host "  (same network: connect $($lan[0]):$Port)" }
    Write-Host '==================================================================' -ForegroundColor Green
}

if ((Get-Process FXServer -ErrorAction SilentlyContinue) -or (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)) {
    Write-Host '[start] server already running; not starting another.'
    Show-Connect 'ok'; return
}
$logFile = Join-Path $LogDir 'fxserver.log'
New-Item -ItemType Directory -Force $LogDir | Out-Null
Remove-Item $logFile -ErrorAction SilentlyContinue
Write-Host '[start] launching server in its own window (close it or run tools/stop-server.ps1 to stop)...'
$srv = Start-Process powershell -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $PSScriptRoot 'start-server.ps1')`"")
$expected = @(Get-Content $cfg | ForEach-Object { if ($_ -match '^\s*(?:ensure|start)\s+(\S+)') { $Matches[1] } } | Select-Object -Unique)
$state = 'pending'
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline -and $state -eq 'pending') {
    Start-Sleep -Seconds 2
    if ($srv.HasExited) {
        Write-Host "Server window exited early (exit code $($srv.ExitCode)) before the server was ready." -ForegroundColor Red
        Write-Host 'Run tools/setup-server.ps1 if this is a fresh machine, or run tools/start-server.ps1 directly to see the error; also check server/logs/.' -ForegroundColor Red
        $state = 'exited'; break
    }
    if (Test-Path $logFile) {
        $fs = [IO.File]::Open($logFile, 'Open', 'Read', 'ReadWrite,Delete')
        try { $text = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
        $state = Get-BootState (([regex]::Replace($text, '\x1b\[[0-9;]*[A-Za-z]', '')) -split "`r?`n") $expected
    }
}
switch ($state) {
    'license' { Write-Host 'Licence key rejected by Cfx. Check the key/IP at portal.cfx.re and run first-run.cmd again.' -ForegroundColor Red }
    'error'   { Write-Host 'Server booted with errors; see server/logs/fxserver.log.' -ForegroundColor Red }
    'exited'  { }
    'pending' { Write-Host "Server not ready after ${TimeoutSec}s; see server/logs/fxserver.log." -ForegroundColor Yellow }
}
Show-Connect $state
