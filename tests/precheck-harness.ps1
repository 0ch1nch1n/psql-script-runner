$ErrorActionPreference = 'Stop'
$path = $env:IMPF_TEST_RUNNER
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$functionAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-ConnectionPrecheck' }, $true)
# Extract only the function: never run the actual UI or database scripts.
Invoke-Expression $functionAst.Extent.Text
Add-Type 'namespace System.Windows.Forms { public static class Application { public static void DoEvents() {} } }'
$script:messages = [System.Collections.Generic.List[string]]::new()
function Write-RunReport { param([string]$Text = '') $script:messages.Add($Text) }
function Write-RunnerStage { param([string]$Stage) $script:messages.Add($Stage) }
$PsqlExe = $env:IMPF_TEST_MOCK
$DbHost = 'host with spaces'
$DbPort = '5026'
$DbName = 'test_db'
$DbUser = 'test_user'
$env:PGCONNECT_TIMEOUT = '77'
$env:PGPASSWORD = 'mock-only-secret'
$env:PSQL_PAGER = 'inherited-pager'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$env:MOCK_MODE = 'success'
$result = Invoke-ConnectionPrecheck
Assert ($result.Database -eq 'test_db' -and $result.User -eq 'test_user') 'Success result was not parsed.'
Assert ($env:PGCONNECT_TIMEOUT -eq '77' -and $env:PSQL_PAGER -eq 'inherited-pager') 'Parent environment was modified.'
Write-Host 'PASS: success, argument boundaries, child environment and parent preservation'

foreach ($mode in @('auth-fail','invalid','mismatch','flood')) {
    $env:MOCK_MODE = $mode
    $caught = $null
    try { $null = Invoke-ConnectionPrecheck } catch { $caught = $_.Exception.Message }
    Assert (-not [string]::IsNullOrEmpty($caught)) "Expected error in $mode."
    if ($mode -eq 'auth-fail') { Assert ($caught -match 'authentication failed') 'Lost authentication error.' }
    if ($mode -eq 'invalid') { Assert ($caught -match 'could not be parsed') 'Invalid output not rejected.' }
    if ($mode -eq 'mismatch') { Assert ($caught -match 'Database mismatch') 'Database mismatch not rejected.' }
    if ($mode -eq 'flood') { Assert ($caught -match 'exit code 2') 'Concurrent output drain failed.' }
    Write-Host "PASS: $mode"
}

$env:MOCK_MODE = 'hang'
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$caught = $null
try { $null = Invoke-ConnectionPrecheck } catch { $caught = $_.Exception.Message }
$clock.Stop()
Assert ($caught -match 'timed out after 30 seconds') 'Missing timeout failure.'
Assert ($clock.Elapsed.TotalSeconds -ge 30 -and $clock.Elapsed.TotalSeconds -lt 35) 'Timeout was not bounded.'
$mockPid = [int](Get-Content $env:IMPF_TEST_PID)
Assert ($null -eq (Get-Process -Id $mockPid -ErrorAction SilentlyContinue)) 'Timed-out mock process survived.'
Assert (($script:messages -join "`n") -notmatch 'mock-only-secret') 'Password appeared in report.'
Write-Host 'PASS: 30-second deadline, process cleanup, no password in report'
Write-Host 'All simulated checks passed. No database connection was made.'
