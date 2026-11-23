# Headless boot check: start DB + FXServer, tail the log, classify, always clean up.
#
# Exit codes: 0 = all `ensure`d resources started, no errors, oxmysql connected
#             1 = resource/script error (or timeout before everything started); offending lines printed
#             2 = licence key missing/invalid (see OWNER-STEPS.md)
#             3 = a server is already running (port 30120 in use or FXServer.exe running); nothing touched
#
# Worktrees: git worktrees have no gitignored server/artifacts, server/db or server/secrets.cfg.
# Chosen approach: the -ServerRoot parameter (no junctions). It names a checkout whose server/ holds
# artifacts/, db/ and secrets.cfg; it defaults to this repo, falling back to the primary checkout
# (parent of `git rev-parse --git-common-dir`) when this one lacks artifacts. FXServer still runs with
# THIS checkout's server/ as cwd (so its resources and server.cfg are what is tested); only the
# `exec secrets.cfg` line is rewritten, in a temp cfg, to point at the ServerRoot's secrets.cfg.
# The licence key is never printed or copied.
[CmdletBinding()]
param(
    [string]$ServerRoot,
    [int]$TimeoutSec = 90,
    [string]$Cfg,                  # default: server/server.cfg of this checkout
    [string[]]$ExtraEnsure = @(),  # extra resources appended as `ensure`
    [string]$ReplayLog             # classify an existing log file; starts nothing (tests the classifier)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

if (-not $ServerRoot) {
    $ServerRoot = $Root
    if (-not (Test-Path (Join-Path $Root 'server\artifacts\FXServer.exe'))) {
        $common = (& git -C $Root rev-parse --path-format=absolute --git-common-dir 2>$null)
        if ($common) { $ServerRoot = Split-Path $common -Parent }
    }
}
$SrvRootServer = Join-Path $ServerRoot 'server'
$script:Fx     = Join-Path $SrvRootServer 'artifacts\FXServer.exe'
$script:DbDir  = Join-Path $SrvRootServer 'db'
$script:DbData = Join-Path $DbDir 'data'
$script:DbPort = Join-Path $DbDir 'port.txt'
$secrets       = Join-Path $SrvRootServer 'secrets.cfg'
if (-not $Cfg) { $Cfg = Join-Path $Server 'server.cfg' }

$FxPort = 30120
function Test-FxBusy {
    if (Get-Process FXServer -ErrorAction SilentlyContinue) { return $true }
    if (Get-NetTCPConnection -LocalPort $FxPort -ErrorAction SilentlyContinue) { return $true }
    if (Get-NetUDPEndpoint -LocalPort $FxPort -ErrorAction SilentlyContinue) { return $true }
    $false
}
function Remove-Ansi([string]$s) { [regex]::Replace($s, '\x1b\[[0-9;]*[A-Za-z]', '') }
function Read-Shared([string]$path) {
    if (-not (Test-Path $path)) { return '' }
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite,Delete')
    try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}

if (-not $ReplayLog -and (Test-FxBusy)) { Write-Host 'server already running (FXServer.exe or port 30120 in use); not touching it.'; exit 3 }
if (-not $ReplayLog -and -not (Test-Path $Fx))      { Write-Host "FXServer not found at $Fx. Run tools/setup-server.ps1 or pass -ServerRoot."; exit 1 }
if (-not $ReplayLog -and -not (Test-Path $secrets)) { Write-Host "No secrets.cfg at $secrets - licence key missing. See OWNER-STEPS.md."; exit 2 }

# Expected resources come from the ensure lines (not hardcoded).
$cfgLines = Get-Content $Cfg
$expected = @($cfgLines | ForEach-Object { if ($_ -match '^\s*(?:ensure|start)\s+(\S+)') { $Matches[1] } }) + $ExtraEnsure | Select-Object -Unique
$tmpCfg = Join-Path $Server '.boot-check.cfg'
$secretsFwd = $secrets -replace '\\', '/'
$out = $cfgLines | ForEach-Object { if ($_ -match '^\s*exec\s+secrets\.cfg') { "exec `"$secretsFwd`"" } else { $_ } }
$out += $ExtraEnsure | ForEach-Object { "ensure $_" }
Set-Content -Path $tmpCfg -Value $out

New-Item -ItemType Directory -Force $LogDir | Out-Null
$log = Join-Path $LogDir 'boot-check.log'
$err = Join-Path $LogDir 'boot-check.err.log'
if ($ReplayLog) { $log = $ReplayLog; $err = Join-Path $LogDir 'boot-check.none.log' }
else { Remove-Item $log, $err -ErrorAction SilentlyContinue }

$dbStarted = $false; $proc = $null; $code = 1
try {
    if (-not $ReplayLog -and -not (Test-DbUp)) { Start-Db; $dbStarted = $true }
    if (-not $ReplayLog) { $proc = Start-Process -FilePath $Fx -ArgumentList @('+exec', '.boot-check.cfg') -WorkingDirectory $Server `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $err }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $errPat = $script:BootErrPat
    $verdict = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 1000
        $text = Remove-Ansi ((Read-Shared $log) + "`n" + (Read-Shared $err))
        $lines = $text -split "`r?`n"
        $state = Get-BootState $lines $expected
        if ($state -eq 'license') { $verdict = 'license'; break }
        if ($state -eq 'error') { Start-Sleep -Seconds 2; $verdict = 'error'; break }
        if ($state -eq 'ok') { $verdict = 'ok'; break }
        if ($ReplayLog -or $proc.HasExited) { $verdict = 'exited'; break }
    }
    $text = Remove-Ansi ((Read-Shared $log) + "`n" + (Read-Shared $err))
    $lines = $text -split "`r?`n"
    switch ($verdict) {
        'license' {
            $lines | Where-Object { $_ -match 'license key|svadhesive' } | Select-Object -First 6 | ForEach-Object { Write-Host $_ }
            Write-Host 'LICENCE KEY missing/invalid. Generate a key and put it in server/secrets.cfg: see OWNER-STEPS.md.'
            $code = 2
        }
        'ok' { Write-Host "BOOT OK: $($expected.Count) resources started ($($expected -join ', ')); oxmysql connected."; $code = 0 }
        default {
            Write-Host "BOOT FAILED ($(if ($verdict) { $verdict } else { "timeout after ${TimeoutSec}s" })). Offending lines:"
            $hit = @($lines | Where-Object { $_ -match $errPat })
            if ($hit) { $hit | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" } }
            $started = @($lines | ForEach-Object { if ($_ -match 'Started resource (\S+)') { $Matches[1] } })
            $missing = @($expected | Where-Object { $_ -notin $started })
            if ($missing) { Write-Host "  not started: $($missing -join ', ')" }
            if (-not $hit -and -not $missing) { Write-Host '  (all resources started but no oxmysql DB connection line seen)' }
            $code = 1
        }
    }
} finally {
    if ($proc -and -not $proc.HasExited) { & taskkill /PID $proc.Id /T /F 2>&1 | Out-Null }
    if ($dbStarted) {
        try { Stop-Db } catch { Write-Host $_ }
        Get-Process mariadbd -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$DbDir*" } | Stop-Process -Force
    }
    Remove-Item $tmpCfg -ErrorAction SilentlyContinue
}
exit $code
