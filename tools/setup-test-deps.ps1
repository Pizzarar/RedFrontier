# Installs a portable, non-admin Lua 5.4 + luarocks + busted into tools/.tools/ (gitignored).
# Nothing is installed system-wide. A portable mingw (w64devkit) is needed only to compile busted's
# C deps (luasystem, luafilesystem). Pinned versions below; the resolved busted set is written to
# tools/.tools/VERSIONS.txt.
$ErrorActionPreference = 'Stop'
$LuaVer = '5.4.8'; $RocksVer = '3.12.2'; $MingwVer = '2.11.0'
$T  = Join-Path $PSScriptRoot '.tools'
$Dl = Join-Path $T 'dl'
$Mingw = Join-Path $T 'w64devkit'; $LuaDir = Join-Path $T 'lua'; $RocksDir = Join-Path $T 'luarocks'; $Tree = Join-Path $T 'rocks'
New-Item -ItemType Directory -Force $Dl, $LuaDir, $RocksDir, $Tree | Out-Null
function Get-File($url, $name) { $f = Join-Path $Dl $name; if (-not (Test-Path $f)) { Invoke-WebRequest $url -OutFile $f }; $f }

if (-not (Test-Path (Join-Path $Mingw 'bin\gcc.exe'))) {
    $f = Get-File "https://github.com/skeeto/w64devkit/releases/download/v$MingwVer/w64devkit-x64-$MingwVer.7z.exe" 'w64devkit.exe'
    & $f "-o$T" -y | Out-Null   # self-extracting 7z, no install, no admin
}
$env:PATH = "$(Join-Path $Mingw 'bin');$LuaDir;$RocksDir;$env:PATH"

if (-not (Test-Path (Join-Path $LuaDir 'lua.exe'))) {
    $tgz = Get-File "https://www.lua.org/ftp/lua-$LuaVer.tar.gz" 'lua.tar.gz'
    $src = Join-Path $T 'lua-src'; New-Item -ItemType Directory -Force $src | Out-Null
    & tar xzf $tgz -C $src --strip-components=1
    $c = Get-ChildItem (Join-Path $src 'src') -Filter *.c | Where-Object { $_.Name -notin 'lua.c', 'luac.c' } | ForEach-Object FullName
    & gcc -O2 -shared -DLUA_BUILD_AS_DLL -o (Join-Path $LuaDir 'lua54.dll') @c
    & gcc -O2 -o (Join-Path $LuaDir 'lua.exe') (Join-Path $src 'src\lua.c') (Join-Path $LuaDir 'lua54.dll')
    New-Item -ItemType Directory -Force (Join-Path $LuaDir 'include') | Out-Null
    foreach ($h in 'lua.h', 'luaconf.h', 'lualib.h', 'lauxlib.h', 'lua.hpp') { Copy-Item (Join-Path $src "src\$h") (Join-Path $LuaDir 'include') }
}
if (-not (Test-Path (Join-Path $RocksDir 'luarocks.exe'))) {
    $z = Get-File "https://luarocks.org/releases/luarocks-$RocksVer-windows-64.zip" 'luarocks.zip'
    Expand-Archive $z -DestinationPath $T -Force
    $inner = Get-ChildItem $T -Directory -Filter 'luarocks-*' | Select-Object -First 1
    if ($inner) { Get-ChildItem $inner.FullName | Move-Item -Destination $RocksDir -Force; Remove-Item $inner.FullName -Recurse -Force }
}
$fw = { param($p) $p -replace '\', '/' }
@"
rocks_trees = { { name = 'project', root = [[$(& $fw $Tree)]] } }
variables = {
  LUA_DIR = [[$(& $fw $LuaDir)]], LUA_INCDIR = [[$(& $fw $LuaDir)/include]], LUA_LIBDIR = [[$(& $fw $LuaDir)]],
  LUA_BINDIR = [[$(& $fw $LuaDir)]], LUALIB = 'lua54.dll', CC = 'gcc', LD = 'gcc',
}
"@ | Set-Content (Join-Path $T 'luarocks-config.lua')
$env:LUAROCKS_CONFIG = Join-Path $T 'luarocks-config.lua'
& (Join-Path $RocksDir 'luarocks.exe') --lua-version 5.4 install busted
if ($LASTEXITCODE) { throw 'luarocks install busted failed' }
& (Join-Path $RocksDir 'luarocks.exe') --lua-version 5.4 list --porcelain | Set-Content (Join-Path $T 'VERSIONS.txt')
Add-Content (Join-Path $T 'VERSIONS.txt') "lua $LuaVer`nluarocks $RocksVer`nw64devkit $MingwVer"
Write-Host 'Test deps ready.'
