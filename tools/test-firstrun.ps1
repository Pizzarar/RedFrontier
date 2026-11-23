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
$cd = Join-Path ([IO.Path]::GetTempPath()) "fh-access-$([guid]::NewGuid())"
New-Item -ItemType Directory -Force $cd | Out-Null
try {
    # access cfgs: created with a comment-only header when missing; existing files are never touched
    Initialize-AccessCfgs $cd *>&1 | Out-Null
    $adm = Join-Path $cd 'admins.cfg'; $alw = Join-Path $cd 'allowlist.cfg'
    Check 'access cfgs created' ((Test-Path $adm) -and (Test-Path $alw))
    $onlyComments = { param($p) -not (@([IO.File]::ReadAllLines($p)) | Where-Object { $_ -notmatch '^\s*(#|$)' }) }
    Check 'access cfgs comment-only' ((& $onlyComments $adm) -and (& $onlyComments $alw))
    $ab = [IO.File]::ReadAllBytes($adm)
    Check 'access cfg no BOM' (-not ($ab[0] -eq 0xEF -and $ab[1] -eq 0xBB))
    [IO.File]::WriteAllText($alw, "add_principal identifier.license:abc group.fh_allowlist`n")
    Initialize-AccessCfgs $cd *>&1 | Out-Null
    Check 'access cfg kept' ([IO.File]::ReadAllText($alw) -eq "add_principal identifier.license:abc group.fh_allowlist`n")
    Remove-Item $adm, $alw

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
    [IO.File]::WriteAllText($t, "set a b`r`nsv_licenseKey `"OLD`"`r`n# n`r`n")
    Set-SecretsKey $t 'cfxk_DDDDDDDDDDDDDDDDDDDD'
    $cl = [IO.File]::ReadAllLines($t)
    Check 'CRLF merge' ((Get-SecretsKey $t) -eq 'cfxk_DDDDDDDDDDDDDDDDDDDD' -and ($cl -contains 'set a b') -and ($cl -contains '# n') -and $cl.Count -eq 3)
    # first-run end to end against the temp file: no elevation, no server start
    $env:FH_CFX_KEY = 'cfxk_TESTTESTTESTTESTTEST'
    $frOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'first-run.ps1') -NoElevate -KeyFromEnv -NoStart -SecretsPath $t -CfgDir $cd *>&1 | Out-String
    $code = $LASTEXITCODE
    Check 'no key in output' (-not $frOut.Contains('cfxk_TESTTESTTESTTESTTEST'))
    Check 'first-run -KeyFromEnv' ($code -eq 0 -and (Get-SecretsKey $t) -eq 'cfxk_TESTTESTTESTTESTTEST')
    Check 'first-run creates access cfgs' ((Test-Path (Join-Path $cd 'admins.cfg')) -and (Test-Path (Join-Path $cd 'allowlist.cfg')))
    $env:FH_CFX_KEY = $null
} finally { Remove-Item $t -ErrorAction SilentlyContinue; Remove-Item $cd -Recurse -Force -ErrorAction SilentlyContinue }

$ok = @('Started resource a', 'Started resource b', 'Database server connection established')
Check 'boot ok'      ((Get-BootState $ok @('a', 'b')) -eq 'ok')
Check 'boot pending' ((Get-BootState $ok @('a', 'b', 'c')) -eq 'pending')
Check 'boot error'   ((Get-BootState ($ok + 'SCRIPT ERROR: x') @('a')) -eq 'error')
Check 'boot license' ((Get-BootState @('Invalid license key') @('a')) -eq 'license')
if ($fail) { Write-Host "$fail FAILED"; exit 1 } else { Write-Host 'ALL PASS' }
