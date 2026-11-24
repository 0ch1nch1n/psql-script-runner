# Interactive Windows smoke check. Never connects to a database or runs SQL.
$ErrorActionPreference = 'Stop'
$script:RunnerVersion = '5.3'
$script:DiagnosticWriter = $null
$runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'psql-Run-Scripts.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Initialize-RunnerDiagnostics', 'Write-RunnerStage', 'Get-RunnerCredential')) {
    $node = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if ($null -eq $node) { throw "Function not found: $name" }
    Invoke-Expression $node.Extent.Text
}
Initialize-RunnerDiagnostics
$credential = $null
try {
    Write-RunnerStage 'PASSWORD_UI_TEST starting; no database operations'
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Write-Host 'Password window test only. Enter any DUMMY password. No database connection will be made.'
    Write-Host ("Local diagnostics: {0}" -f $script:DiagnosticPath)
    $credential = Get-RunnerCredential -UserName 'UI test (dummy password only)'
    Write-RunnerStage 'PASSWORD_UI_TEST function returned; about to write console result'
    if ($null -eq $credential) { Write-Host 'Dialog cancelled successfully.' }
    else { Write-Host 'Dialog returned successfully. Password is not displayed or saved.' }
    Write-RunnerStage 'PASSWORD_UI_TEST console result written'
}
finally {
    if ($null -ne $credential) { $credential.Password.Dispose() }
    Write-RunnerStage 'PASSWORD_UI_TEST cleanup completed'
    $script:DiagnosticWriter.Dispose()
}
