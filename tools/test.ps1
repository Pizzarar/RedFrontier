# Runs the pure-Lua specs in spec/ under embedded Lua 5.4 via Python lupa (tools/run-specs.py).
# Needs: pip install lupa (2.x). Extra args go to run-specs.py (spec paths, or --syntax <dir>...).
# The specs stay runner-agnostic: `busted` from the repo root (.busted) runs the same files.
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Push-Location $Root
try {
    & python (Join-Path $PSScriptRoot 'run-specs.py') @args
    exit $LASTEXITCODE
} finally { Pop-Location }
