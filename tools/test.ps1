# Runs the pure-Lua busted specs in spec/. Uses a busted on PATH if present, otherwise the portable
# toolchain in tools/.tools (installed on first run by tools/setup-test-deps.ps1). Extra args go to busted.
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$T = Join-Path $PSScriptRoot '.tools'
$lua = Join-Path $T 'lua\lua.exe'
$tree = Join-Path $T 'rocks'
$cmd = Get-Command busted -ErrorAction SilentlyContinue
if (-not $cmd -and -not (Test-Path (Join-Path $tree 'bin\busted'))) {
    & (Join-Path $PSScriptRoot 'setup-test-deps.ps1')
}
Push-Location $Root
try {
    if ($cmd) { & busted @args }
    else {
        $env:PATH = "$(Join-Path $T 'lua');$(Join-Path $T 'w64devkit\bin');$env:PATH"
        $env:LUA_PATH  = "$((Join-Path $tree 'share\lua\5.4') -replace '\','/')/?.lua;$((Join-Path $tree 'share\lua\5.4') -replace '\','/')/?/init.lua;;"
        $env:LUA_CPATH = "$((Join-Path $tree 'lib\lua\5.4') -replace '\','/')/?.dll;;"
        & $lua (Join-Path $tree 'bin\busted') @args
    }
    exit $LASTEXITCODE
} finally { Pop-Location }
