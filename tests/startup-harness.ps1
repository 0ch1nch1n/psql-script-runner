# Simulate modal outcomes around the actual top-level startup flow. No DB or GUI.
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $env:IMPF_TEST_RUNNER -Raw
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Initialize-RunnerDiagnostics', 'Write-RunnerStage', 'Write-RunReport', 'Initialize-RunReport', 'Complete-RunReport')) {
    $node = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    Invoke-Expression $node.Extent.Text
}
Add-Type @'
namespace System.Windows.Forms {
    public enum DialogResult { Yes, No }
    public enum MessageBoxButtons { YesNo }
    public enum MessageBoxIcon { Warning }
    public enum MessageBoxDefaultButton { Button2 }
    public static class MessageBox {
        public static DialogResult Show(string text, string title, MessageBoxButtons b,
            MessageBoxIcon i, MessageBoxDefaultButton d) {
            return System.Environment.GetEnvironmentVariable("IMPF_FLOW_CASE") == "confirm"
                ? DialogResult.Yes : DialogResult.No;
        }
    }
}
'@
$script:RunnerVersion = '5.2'
$script:DiagnosticWriter = $null
$script:RunReportWriter = $null
$script:RunReportFinalized = $false
$script:RunStartedAt = Get-Date
$env:LOCALAPPDATA = $env:IMPF_FLOW_ROOT
Initialize-RunnerDiagnostics
Write-RunnerStage 'START simulated modal outcomes; real top-level control flow'
$DbHost = 'mock-host'
$DbPort = '5432'
$DbName = 'mock-db'
$DbUser = 'mock-user'
$PsqlExe = $env:IMPF_TEST_MOCK
$ConfiguredPassword = ''
$env:PG_RUNNER_SELF = $env:IMPF_TEST_RUNNER
Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
function Select-BackupScript { return (Join-Path $env:IMPF_FLOW_ROOT 'backup.sql') }
function Select-CustomerScripts { return (Join-Path $env:IMPF_FLOW_ROOT 'customer.sql') }
function Edit-ScriptExecutionOrder { param($InitialScripts, $InitialDirectory) return $InitialScripts }
function Get-RunnerCredential {
    Write-RunnerStage 'PASSWORD_DIALOG simulated return'
    if ($env:IMPF_FLOW_CASE -eq 'cancel') { return $null }
    $secret = ConvertTo-SecureString 'fake-password-with-no-real-access' -AsPlainText -Force
    return (New-Object System.Management.Automation.PSCredential('mock-user', $secret))
}
function Invoke-ConnectionPrecheck {
    Write-RunnerStage 'PRECHECK simulated process result'
    if ($env:PGPASSWORD -ne 'fake-password-with-no-real-access') { throw 'Password handoff failed.' }
    if ($env:IMPF_FLOW_CASE -eq 'precheck-fail') { throw 'Simulated connection failure.' }
    return [pscustomobject]@{ Database=$DbName; User=$DbUser; ServerAddress='127.0.0.1'; ServerPort='5432'; ServerVersion='mock' }
}
function Invoke-PsqlScript {
    param($SqlPath, $StepName)
    # A marker replaces execution; never run psql or read the selected SQL.
    Add-Content -LiteralPath (Join-Path $env:IMPF_FLOW_ROOT 'executed.txt') -Value $StepName
    return [pscustomobject]@{ ExitCode=0 }
}
function Show-RunnerMessage { param($Text, $Title, $Icon) }
$start = $source.IndexOf('$passwordSetByRunner = $false')
if ($start -lt 0) { throw 'Main startup block was not found.' }
Invoke-Expression $source.Substring($start)
