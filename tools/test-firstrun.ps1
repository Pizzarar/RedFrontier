# Headless tests for first-run helpers (key validation, secrets merge, boot classifier). Uses temp files only.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$fail = 0
function Check($name, $cond) { if ($cond) { Write-Host "PASS $name" } else { Write-Host "FAIL $name"; $script:fail++ } }

Check 'valid key'        (Test-CfxKey 'cfxk_abcdEFGH1234_ijklMNOP5678')
Check 'no prefix'        (-not (Test-CfxKey 'abcdEFGH1234ijklMNOP5678'))
Check 'wrong case pfx'   (-not (Test-CfxKey 'CFXK_abcdEFGH1234ijklMNOP'))
Check 'too short'        (-not (Test-CfxKey 'cfxk_abc'))
Check 'bad charset'      (-not (Test-CfxKey 'cfxk_abcdEFGH1234 ijklMNOP"x'))
Check 'empty/null'       ((-not (Test-CfxKey '')) -and (-not (Test-CfxKey $null)))

$t = Join-Path ([IO.Path]::GetTempPath()) "fh-secrets-$([guid]::NewGuid()).cfg"
try {
    Check 'absent -> null' ($null -eq (Get-SecretsKey $t))
    Set-SecretsKey $t 'cfxk_AAAAAAAAAAAAAAAAAAAA'
    Check 'create' ((Get-SecretsKey $t) -eq 'cfxk_AAAAAAAAAAAAAAAAAAAA')
    [IO.File]::WriteAllText($t, "set mysql_x `"keep`"`nsv_licenseKey `"REPLACE`"`n# note`nsv_licenseKey `"dup`"`n")
    Set-SecretsKey $t 'cfxk_BBBBBBBBBBBBBBBBBBBB'
    $lines = [IO.File]::ReadAllLines($t)
    Check 'replace keeps others' (($lines -contains 'set mysql_x "keep"') -and ($lines -contains '# note') -and ($lines.Count -eq 3))
    Check 'single key line' (@($lines -match 'sv_licenseKey').Count -eq 1 -and (Get-SecretsKey $t) -eq 'cfxk_BBBBBBBBBBBBBBBBBBBB')
    $b = [IO.File]::ReadAllBytes($t)
    Check 'no BOM' (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB))
    [IO.File]::WriteAllText($t, "set a b`n")
    Set-SecretsKey $t 'cfxk_CCCCCCCCCCCCCCCCCCCC'
    Check 'append' ((Get-SecretsKey $t) -eq 'cfxk_CCCCCCCCCCCCCCCCCCCC' -and ([IO.File]::ReadAllLines($t) -contains 'set a b'))
    # first-run end to end against the temp file: no elevation, no server start
    $env:FH_CFX_KEY = 'cfxk_TESTTESTTESTTESTTEST'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'first-run.ps1') -NoElevate -KeyFromEnv -NoStart -SecretsPath $t | Out-Null
    Check 'first-run -KeyFromEnv' ($LASTEXITCODE -eq 0 -and (Get-SecretsKey $t) -eq 'cfxk_TESTTESTTESTTESTTEST')
    $env:FH_CFX_KEY = $null
} finally { Remove-Item $t -ErrorAction SilentlyContinue }

$ok = @('Started resource a', 'Started resource b', 'Database server connection established')
Check 'boot ok'      ((Get-BootState $ok @('a', 'b')) -eq 'ok')
Check 'boot pending' ((Get-BootState $ok @('a', 'b', 'c')) -eq 'pending')
Check 'boot error'   ((Get-BootState ($ok + 'SCRIPT ERROR: x') @('a')) -eq 'error')
Check 'boot license' ((Get-BootState @('Invalid license key') @('a')) -eq 'license')
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
