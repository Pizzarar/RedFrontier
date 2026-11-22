# Idempotent setup: FXServer artifact, portable MariaDB, DB + migrations, secrets.cfg.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

# ---- pins ----
$FxBuild  = '38435-5c3065c261fb3ba82032fee6803f247198fec221'   # FXServer "recommended" at 2026-11-22
$FxUrl    = "https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/$FxBuild/server.zip"
$MariaVer = '11.4.14'
$MariaUrl = "https://archive.mariadb.org/mariadb-$MariaVer/winx64-packages/mariadb-$MariaVer-winx64.zip"
$DbName = 'redfrontier'; $DbUser = 'redfrontier'

New-Item -ItemType Directory -Force $Tmp, $DbDir, $LogDir | Out-Null

function Get-Zip($url, $name) {
    $dir = Join-Path $Tmp ($name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))   # fresh, empty dir
    New-Item -ItemType Directory $dir | Out-Null
    $zip = Join-Path $dir "$name.zip"
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Write-Host ("  sha256 {0}" -f (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower())
    $out = Join-Path $dir 'x'
    Expand-Archive $zip -DestinationPath $out
    $out
}

# ---- FXServer ----
if (Test-Path $Fx) { Write-Host 'FXServer: present' } else {
    $x = Get-Zip $FxUrl 'fxserver'
    New-Item -ItemType Directory -Force (Split-Path $Fx) | Out-Null
    Copy-Item (Join-Path $x '*') (Split-Path $Fx) -Recurse -Force
    Set-Content (Join-Path (Split-Path $Fx) 'BUILD.txt') $FxBuild
    Write-Host "FXServer: installed $FxBuild"
}

# ---- MariaDB ----
if (Get-ChildItem (Join-Path $DbDir 'mariadb') -Directory -ErrorAction SilentlyContinue) { Write-Host 'MariaDB: present' } else {
    $x = Get-Zip $MariaUrl 'mariadb'
    New-Item -ItemType Directory -Force (Join-Path $DbDir 'mariadb') | Out-Null
    Copy-Item (Join-Path $x '*') (Join-Path $DbDir 'mariadb') -Recurse -Force
    Write-Host "MariaDB: installed $MariaVer"
}
$bin = Get-MariaBin

if (-not (Test-Path $DbPort)) {
    $p = 3306
    if (Get-NetTCPConnection -LocalPort 3306 -State Listen -ErrorAction SilentlyContinue) { $p = 33061 }
    Set-Content $DbPort $p
}
$port = Get-DbPort

$wasUp = Test-DbUp
if (-not (Test-Path (Join-Path $DbData 'mysql'))) {
    Write-Host 'MariaDB: initialising datadir'
    & (Join-Path $bin 'mariadb-install-db.exe') "--datadir=$DbData" --password= 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'mariadb-install-db failed' }
}
Start-Db

function Invoke-Sql($sql, $db) {
    $a = @('-uroot', '--protocol=tcp', '-h127.0.0.1', "-P$port", '-N', '-B')
    if ($db) { $a += $db }
    $sql | & (Join-Path $bin 'mariadb.exe') @a
    if ($LASTEXITCODE -ne 0) { throw "SQL failed: $sql" }
}

# ---- db, user, secrets.cfg ----
$secrets = Join-Path $Server 'secrets.cfg'
Invoke-Sql "CREATE DATABASE IF NOT EXISTS ``$DbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
if (-not (Test-Path $secrets)) {
    $pw = -join ((1..24) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    $rc = -join ((1..24) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    foreach ($h in '127.0.0.1', 'localhost') {
        Invoke-Sql "CREATE USER IF NOT EXISTS '$DbUser'@'$h' IDENTIFIED BY '$pw'; ALTER USER '$DbUser'@'$h' IDENTIFIED BY '$pw'; GRANT ALL ON ``$DbName``.* TO '$DbUser'@'$h';"
    }
    Invoke-Sql 'FLUSH PRIVILEGES;'
    $txt = Get-Content (Join-Path $Server 'secrets.example.cfg') -Raw
    $txt = $txt -replace 'mysql://USER:PASSWORD@127\.0\.0\.1:3306/DATABASE', "mysql://${DbUser}:${pw}@127.0.0.1:${port}/$DbName"
    $txt = $txt -replace 'REPLACE_WITH_RCON_PASSWORD', $rc
    Set-Content $secrets $txt -NoNewline
    Write-Host 'secrets.cfg: created (set sv_licenseKey yourself)'
} else { Write-Host 'secrets.cfg: present' }

# ---- migrations ----
Invoke-Sql 'CREATE TABLE IF NOT EXISTS schema_migrations (name VARCHAR(190) PRIMARY KEY, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);' $DbName
$applied = @(Invoke-Sql 'SELECT name FROM schema_migrations;' $DbName)
foreach ($f in Get-ChildItem (Join-Path $Server 'migrations') -Filter '*.sql' | Sort-Object Name) {
    if ($applied -contains $f.Name) { Write-Host "migration: skip $($f.Name)"; continue }
    Write-Host "migration: applying $($f.Name)"
    Get-Content $f.FullName -Raw -Encoding UTF8 | & (Join-Path $bin 'mariadb.exe') -uroot --protocol=tcp -h127.0.0.1 "-P$port" $DbName
    if ($LASTEXITCODE -ne 0) { throw "migration failed: $($f.Name)" }
    Invoke-Sql "INSERT INTO schema_migrations (name) VALUES ('$($f.Name)');" $DbName
}

if (-not $wasUp) { Stop-Db; Write-Host 'MariaDB: stopped (start-server.ps1 starts it)' }
Write-Host 'Setup complete.'
