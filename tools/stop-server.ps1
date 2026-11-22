# Stops FXServer (the one in server/artifacts) and the portable MariaDB.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib.ps1')
Get-Process FXServer -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -like "$Server*" } | Stop-Process -Force
if (Test-Path $DbPort) { try { Stop-Db } catch { Write-Host $_ } }
Get-Process mariadbd -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$DbDir*" } | Stop-Process -Force
Write-Host 'Stopped.'
