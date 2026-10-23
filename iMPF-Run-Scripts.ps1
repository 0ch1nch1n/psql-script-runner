# PostgreSQL multi-script runner logic.
# Configure the connection variables in the matching CMD launcher.


$ErrorActionPreference = 'Stop'

$PsqlExe = $env:PG_PSQL_EXE
$DbHost  = $env:PG_HOST
$DbPort  = $env:PG_PORT
$DbName  = $env:PG_DATABASE
$DbUser  = $env:PG_USERNAME
$ConfiguredPassword = $env:PG_PASSWORD

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:RunReportWriter = $null
$script:RunReportPath = $null
$script:RunReportFinalized = $false
$script:RunStartedAt = Get-Date

function Show-RunnerMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Title = 'PostgreSQL Multi-Script Runner',
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    )
}

function Write-RunReport {
    param([string]$Text = '')

    if ($null -ne $script:RunReportWriter) {
        $script:RunReportWriter.WriteLine($Text)
    }
}

function Initialize-RunReport {
    param([Parameter(Mandatory = $true)][string]$Path)

    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    $script:RunReportWriter = New-Object System.IO.StreamWriter($Path, $false, $utf8WithBom)
    $script:RunReportWriter.AutoFlush = $true
    $script:RunReportPath = $Path

    Write-RunReport ('=' * 78)
    Write-RunReport 'POSTGRESQL MULTI-SCRIPT EXECUTION REPORT'
    Write-RunReport ('=' * 78)
    Write-RunReport ("Run started:       {0}" -f $script:RunStartedAt.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-RunReport ("Runner file:       {0}" -f $env:PG_RUNNER_SELF)
    Write-RunReport ("Report file:       {0}" -f $Path)
    Write-RunReport ("Configured target: {0}:{1} / database={2} / user={3}" -f $DbHost, $DbPort, $DbName, $DbUser)
    Write-RunReport 'Password:          not recorded'
}

function Complete-RunReport {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$Details = ''
    )

    if ($null -eq $script:RunReportWriter -or $script:RunReportFinalized) {
        return
    }

    $finishedAt = Get-Date
    $duration = [Math]::Round(($finishedAt - $script:RunStartedAt).TotalSeconds, 2)
    Write-RunReport ''
    Write-RunReport ('=' * 78)
    Write-RunReport ("FINAL STATUS: {0}" -f $Status)
    if (-not [string]::IsNullOrWhiteSpace($Details)) {
        Write-RunReport ("Details:      {0}" -f $Details)
    }
    Write-RunReport ("Run finished: {0}" -f $finishedAt.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-RunReport ("Duration:     {0} seconds" -f $duration)
    Write-RunReport ('=' * 78)
    $script:RunReportFinalized = $true
}

function New-ScriptFileDialog {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$InitialDirectory,
        [bool]$Multiselect = $false
    )

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = 'SQL scripts (*.sql;*.txt)|*.sql;*.txt|SQL files (*.sql)|*.sql|Text files (*.txt)|*.txt|All files (*.*)|*.*'
    $dialog.InitialDirectory = $InitialDirectory
    $dialog.Multiselect = $Multiselect
    $dialog.CheckFileExists = $true
    $dialog.RestoreDirectory = $true
    return $dialog
}

function Select-BackupScript {
    param([Parameter(Mandatory = $true)][string]$InitialDirectory)

    $dialog = New-ScriptFileDialog -Title 'Step 1: select the BACKUP SQL script' -InitialDirectory $InitialDirectory
    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return $null
        }
        return $dialog.FileName
    }
    finally {
        $dialog.Dispose()
    }
}

function Select-CustomerScripts {
    param([Parameter(Mandatory = $true)][string]$InitialDirectory)

    $dialog = New-ScriptFileDialog -Title 'Step 2: select one or more CUSTOMER scripts (Ctrl/Shift for multiple)' -InitialDirectory $InitialDirectory -Multiselect $true
    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        foreach ($fileName in $dialog.FileNames) {
            Write-Output $fileName
        }
    }
    finally {
        $dialog.Dispose()
    }
}

function Edit-ScriptExecutionOrder {
    param(
        [Parameter(Mandatory = $true)][string[]]$InitialScripts,
        [Parameter(Mandatory = $true)][string]$InitialDirectory
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Arrange customer-script execution order'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(940, 560)
    $form.MinimumSize = New-Object System.Drawing.Size(760, 420)
    $form.MaximizeBox = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Scripts execute from top to bottom after the backup. Select a row, then use Move Up or Move Down.'
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(14, 15)
    $form.Controls.Add($label)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(15, 42)
    $list.Size = New-Object System.Drawing.Size(740, 420)
    $list.Anchor = 'Top,Bottom,Left,Right'
    $list.HorizontalScrollbar = $true
    $list.SelectionMode = 'One'
    foreach ($script in $InitialScripts) {
        [void]$list.Items.Add([IO.Path]::GetFullPath($script))
    }
    $form.Controls.Add($list)

    $addButton = New-Object System.Windows.Forms.Button
    $addButton.Text = 'Add scripts...'
    $addButton.Location = New-Object System.Drawing.Point(775, 42)
    $addButton.Size = New-Object System.Drawing.Size(130, 34)
    $addButton.Anchor = 'Top,Right'
    $addButton.Add_Click({
        $addDialog = New-ScriptFileDialog -Title 'Add customer scripts' -InitialDirectory $InitialDirectory -Multiselect $true
        try {
            if ($addDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                foreach ($fileName in $addDialog.FileNames) {
                    $fullName = [IO.Path]::GetFullPath($fileName)
                    if (-not $list.Items.Contains($fullName)) {
                        [void]$list.Items.Add($fullName)
                    }
                }
            }
        }
        finally {
            $addDialog.Dispose()
        }
    })
    $form.Controls.Add($addButton)

    $upButton = New-Object System.Windows.Forms.Button
    $upButton.Text = 'Move Up'
    $upButton.Location = New-Object System.Drawing.Point(775, 90)
    $upButton.Size = New-Object System.Drawing.Size(130, 34)
    $upButton.Anchor = 'Top,Right'
    $upButton.Add_Click({
        $index = $list.SelectedIndex
        if ($index -gt 0) {
            $item = $list.Items[$index]
            $list.Items.RemoveAt($index)
            $list.Items.Insert($index - 1, $item)
            $list.SelectedIndex = $index - 1
        }
    })
    $form.Controls.Add($upButton)

    $downButton = New-Object System.Windows.Forms.Button
    $downButton.Text = 'Move Down'
    $downButton.Location = New-Object System.Drawing.Point(775, 138)
    $downButton.Size = New-Object System.Drawing.Size(130, 34)
    $downButton.Anchor = 'Top,Right'
    $downButton.Add_Click({
        $index = $list.SelectedIndex
        if ($index -ge 0 -and $index -lt ($list.Items.Count - 1)) {
            $item = $list.Items[$index]
            $list.Items.RemoveAt($index)
            $list.Items.Insert($index + 1, $item)
            $list.SelectedIndex = $index + 1
        }
    })
    $form.Controls.Add($downButton)

    $removeButton = New-Object System.Windows.Forms.Button
    $removeButton.Text = 'Remove'
    $removeButton.Location = New-Object System.Drawing.Point(775, 186)
    $removeButton.Size = New-Object System.Drawing.Size(130, 34)
    $removeButton.Anchor = 'Top,Right'
    $removeButton.Add_Click({
        $index = $list.SelectedIndex
        if ($index -ge 0) {
            $list.Items.RemoveAt($index)
            if ($list.Items.Count -gt 0) {
                $list.SelectedIndex = [Math]::Min($index, $list.Items.Count - 1)
            }
        }
    })
    $form.Controls.Add($removeButton)

    $runButton = New-Object System.Windows.Forms.Button
    $runButton.Text = 'Use this order'
    $runButton.Location = New-Object System.Drawing.Point(775, 380)
    $runButton.Size = New-Object System.Drawing.Size(130, 38)
    $runButton.Anchor = 'Bottom,Right'
    $runButton.Add_Click({
        if ($list.Items.Count -eq 0) {
            Show-RunnerMessage -Text 'Add at least one customer script.' -Title 'No customer scripts' -Icon Warning
            return
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($runButton)
    $form.AcceptButton = $runButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Cancel'
    $cancelButton.Location = New-Object System.Drawing.Point(775, 430)
    $cancelButton.Size = New-Object System.Drawing.Size(130, 34)
    $cancelButton.Anchor = 'Bottom,Right'
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    try {
        if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        foreach ($item in $list.Items) {
            Write-Output ([string]$item)
        }
    }
    finally {
        $form.Dispose()
    }
}

function Invoke-ConnectionPrecheck {
    $marker = '__PG_RUNNER_PREFLIGHT__'
    $query = "SELECT '$marker|' || current_database() || '|' || current_user || '|' || COALESCE(inet_server_addr()::text, 'local') || '|' || COALESCE(inet_server_port()::text, 'local') || '|' || current_setting('server_version');"
    $arguments = @(
        '-X'
        '-w'
        '-P', 'pager=off'
        '-h', $DbHost
        '-p', $DbPort
        '-U', $DbUser
        '-d', $DbName
        '-v', 'ON_ERROR_STOP=1'
        '-A'
        '-t'
        '-q'
        '-c', $query
    )

    Write-Host ''
    Write-Host 'Running read-only connection precheck...' -ForegroundColor Cyan
    Write-RunReport ''
    Write-RunReport '[CONNECTION PRECHECK]'
    Write-RunReport ("Started: {0}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))

    # Keep the timeout on the read-only precheck, not on business scripts.
    $timeoutSeconds = 30
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $PsqlExe
    # ProcessStartInfo.Arguments uses Windows native argument quoting (.NET 4.x).
    $startInfo.Arguments = (($arguments | ForEach-Object {
        $quoted = [regex]::Replace([string]$_, '(\\*)"', '$1$1\"')
        $quoted = [regex]::Replace($quoted, '(\\+)$', '$1$1')
        '"' + $quoted + '"'
    }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['PGCONNECT_TIMEOUT'] = '10'
    # Prevent an unexpected inherited pager from delaying this one-row query.
    $startInfo.EnvironmentVariables['PSQL_PAGER'] = ''
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $nextProgress = 5
    Write-RunReport 'Limits: connect=10 seconds per address; total precheck=30 seconds.'
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Could not start psql for the connection precheck.' }
        $process.StandardInput.Close()
        # Drain both pipes concurrently, even if psql produces many error lines.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        while (-not ($process.HasExited -and $stdoutTask.IsCompleted -and $stderrTask.IsCompleted)) {
            if ($timer.Elapsed.TotalSeconds -ge $timeoutSeconds) {
                Write-RunReport 'Result: TIMEOUT (30 seconds). No selected SQL script was started.'
                throw 'Connection precheck timed out after 30 seconds. No selected SQL script was started. Check network/VPN, DNS, database reachability and authentication; then retry.'
            }
            if ($timer.Elapsed.TotalSeconds -ge $nextProgress) {
                $progressText = 'Connection precheck still running ({0}s / 30s)...' -f [int]$timer.Elapsed.TotalSeconds
                Write-Host $progressText -ForegroundColor Yellow
                Write-RunReport $progressText
                $nextProgress += 5
            }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        $exitCode = $process.ExitCode
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $output = @(($stdout + "`n" + $stderr) -split '\r?\n' | Where-Object { $_.Length -gt 0 })
    }
    finally {
        $timer.Stop()
        if ($started -and -not $process.HasExited) {
            $process.Kill()
            [void]$process.WaitForExit(2000)
        }
        $process.Dispose()
    }

    foreach ($line in $output) {
        Write-RunReport ("psql: {0}" -f $line)
    }
    Write-RunReport ("Exit code: {0}" -f $exitCode)

    if ($exitCode -ne 0) {
        $detail = ($output -join "`r`n")
        throw "Connection precheck failed with exit code $exitCode.`r`n`r`n$detail"
    }

    $resultLine = $null
    foreach ($line in $output) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("$marker|")) {
            $resultLine = $trimmed
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($resultLine)) {
        throw 'Connection succeeded, but the precheck result could not be parsed.'
    }

    $parts = $resultLine.Split('|')
    if ($parts.Count -lt 6) {
        throw "Connection precheck returned an unexpected result:`r`n$resultLine"
    }

    $result = [pscustomobject]@{
        Database = $parts[1]
        User = $parts[2]
        ServerAddress = $parts[3]
        ServerPort = $parts[4]
        ServerVersion = $parts[5]
        ExitCode = [int]$exitCode
    }

    Write-RunReport 'Result: SUCCESS'
    Write-RunReport ("Actual database: {0}" -f $result.Database)
    Write-RunReport ("Actual user:     {0}" -f $result.User)
    Write-RunReport ("Server address:  {0}" -f $result.ServerAddress)
    Write-RunReport ("Server port:     {0}" -f $result.ServerPort)
    Write-RunReport ("Server version:  {0}" -f $result.ServerVersion)

    if (-not [string]::Equals($result.Database, $DbName, [StringComparison]::Ordinal)) {
        throw "Database mismatch. Configured: $DbName; actual: $($result.Database)"
    }
    if (-not [string]::Equals($result.User, $DbUser, [StringComparison]::Ordinal)) {
        throw "Database user mismatch. Configured: $DbUser; actual: $($result.User)"
    }

    return $result
}

function Invoke-PsqlScript {
    param(
        [Parameter(Mandatory = $true)][string]$SqlPath,
        [Parameter(Mandatory = $true)][string]$StepName
    )

    $fullSqlPath = [IO.Path]::GetFullPath($SqlPath)
    $logPath = [IO.Path]::ChangeExtension($fullSqlPath, '.log')
    $startedAt = Get-Date
    $arguments = @(
        '-X'
        '-h', $DbHost
        '-p', $DbPort
        '-U', $DbUser
        '-d', $DbName
        '-v', 'ON_ERROR_STOP=1'
        '-1'
        '-a'
        '-f', $fullSqlPath
    )

    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host ("{0}: {1}" -f $StepName, $fullSqlPath) -ForegroundColor Cyan
    Write-Host ("Target: {0}:{1} / {2} / {3}" -f $DbHost, $DbPort, $DbName, $DbUser) -ForegroundColor Cyan
    Write-Host ("Log: {0}" -f $logPath) -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan

    Write-RunReport ''
    Write-RunReport ("[SCRIPT] {0}" -f $StepName)
    Write-RunReport ("Path:       {0}" -f $fullSqlPath)
    Write-RunReport ("Log:        {0}" -f $logPath)
    Write-RunReport ("Started:    {0}" -f $startedAt.ToString('yyyy-MM-dd HH:mm:ss'))

    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
    $logWriter = New-Object System.IO.StreamWriter($logPath, $false, $utf8WithBom)
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $PsqlExe @arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            Write-Host $line
            $logWriter.WriteLine($line)
        }
        $exitCode = $LASTEXITCODE
        $finishedAt = Get-Date
        $summary = "[{0}] Runner exit code: {1}" -f $finishedAt.ToString('yyyy-MM-dd HH:mm:ss'), $exitCode
        $logWriter.WriteLine('')
        $logWriter.WriteLine($summary)
        Write-Host ''
        Write-Host $summary
    }
    finally {
        $logWriter.Dispose()
        $ErrorActionPreference = $savedPreference
    }

    $duration = [Math]::Round(($finishedAt - $startedAt).TotalSeconds, 2)
    $status = if ($exitCode -eq 0) { 'SUCCESS' } else { 'FAILED' }
    Write-RunReport ("Finished:   {0}" -f $finishedAt.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-RunReport ("Duration:   {0} seconds" -f $duration)
    Write-RunReport ("Exit code:  {0}" -f $exitCode)
    Write-RunReport ("Status:     {0}" -f $status)

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Status = $status
        ScriptPath = $fullSqlPath
        LogPath = $logPath
        StartedAt = $startedAt
        FinishedAt = $finishedAt
        DurationSeconds = $duration
    }
}

$passwordSetByRunner = $false

try {
    $requiredSettings = [ordered]@{
        PG_PSQL_EXE = $PsqlExe
        PG_HOST = $DbHost
        PG_PORT = $DbPort
        PG_DATABASE = $DbName
        PG_USERNAME = $DbUser
    }
    foreach ($setting in $requiredSettings.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$setting.Value)) {
            throw "Required setting $($setting.Key) is empty. Edit it at the top of this CMD file."
        }
    }
    if ($DbPort -notmatch '^\d+$' -or [int]$DbPort -lt 1 -or [int]$DbPort -gt 65535) {
        throw "PG_PORT must be a number from 1 to 65535. Current value: $DbPort"
    }
    if (-not (Test-Path -LiteralPath $PsqlExe -PathType Leaf)) {
        throw "psql.exe was not found:`r`n$PsqlExe`r`n`r`nEdit PG_PSQL_EXE at the top of this CMD file."
    }

    $startDirectory = Split-Path -Parent $env:PG_RUNNER_SELF
    $backupSql = Select-BackupScript -InitialDirectory $startDirectory
    if ([string]::IsNullOrWhiteSpace($backupSql)) {
        exit 2
    }

    $selectedScripts = @(Select-CustomerScripts -InitialDirectory (Split-Path -Parent $backupSql))
    if ($selectedScripts.Count -eq 0) {
        exit 2
    }
    $customerScripts = @(Edit-ScriptExecutionOrder -InitialScripts $selectedScripts -InitialDirectory (Split-Path -Parent $backupSql))
    if ($customerScripts.Count -eq 0) {
        exit 2
    }

    $allScripts = @($backupSql) + $customerScripts
    $seenScripts = @{}
    $seenLogs = @{}
    foreach ($scriptPath in $allScripts) {
        $fullPath = [IO.Path]::GetFullPath($scriptPath)
        $scriptKey = $fullPath.ToLowerInvariant()
        $logPath = [IO.Path]::ChangeExtension($fullPath, '.log')
        $logKey = $logPath.ToLowerInvariant()
        if ($seenScripts.ContainsKey($scriptKey)) {
            throw "The same script was selected more than once:`r`n$fullPath"
        }
        if ($seenLogs.ContainsKey($logKey)) {
            throw "Two scripts would use the same log file:`r`n$logPath`r`n`r`nRename one script and try again."
        }
        $seenScripts[$scriptKey] = $true
        $seenLogs[$logKey] = $true
    }

    $reportDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($backupSql))
    $reportName = 'PostgreSQL_Run_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
    $reportPath = Join-Path $reportDirectory $reportName
    Initialize-RunReport -Path $reportPath
    Write-RunReport ''
    Write-RunReport '[PLANNED EXECUTION ORDER]'
    Write-RunReport ("1. BACKUP   {0}" -f $backupSql)
    for ($i = 0; $i -lt $customerScripts.Count; $i++) {
        Write-RunReport ("{0}. CUSTOMER {1}" -f ($i + 2), $customerScripts[$i])
    }

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPassword)) {
        $env:PGPASSWORD = $ConfiguredPassword
        $passwordSetByRunner = $true
    }
    elseif ([string]::IsNullOrWhiteSpace($env:PGPASSWORD)) {
        $credential = Get-Credential -UserName $DbUser -Message "Enter the PostgreSQL password for $DbUser. The password is kept only for this CMD process."
        if ($null -eq $credential) {
            Complete-RunReport -Status 'CANCELLED' -Details 'Password entry was cancelled.'
            exit 2
        }
        $env:PGPASSWORD = $credential.GetNetworkCredential().Password
        $passwordSetByRunner = $true
    }

    $precheck = Invoke-ConnectionPrecheck

    $orderLines = New-Object System.Collections.Generic.List[string]
    [void]$orderLines.Add("  1. BACKUP   $backupSql")
    for ($i = 0; $i -lt $customerScripts.Count; $i++) {
        [void]$orderLines.Add(("  {0}. CUSTOMER {1}" -f ($i + 2), $customerScripts[$i]))
    }
    $orderText = $orderLines -join "`r`n"
    $passwordMode = if ([string]::IsNullOrWhiteSpace($ConfiguredPassword)) { 'secure prompt or existing environment' } else { 'PG_PASSWORD from CMD' }
    $confirmation = @"
Connection precheck: SUCCESS
Actual database: $($precheck.Database)
Actual user:     $($precheck.User)
Server address:  $($precheck.ServerAddress)
Server port:     $($precheck.ServerPort)
Server version:  $($precheck.ServerVersion)

Configured endpoint:
  $DbHost`:$DbPort
Password source:
  $passwordMode

Execution order:
$orderText

Run report:
  $reportPath

Existing same-name script logs will be overwritten.
Execution stops immediately if any script fails.

Continue?
"@

    $answer = [System.Windows.Forms.MessageBox]::Show(
        $confirmation,
        'Precheck passed - confirm database execution',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        Complete-RunReport -Status 'CANCELLED' -Details 'Precheck passed, but the user declined final execution confirmation.'
        exit 2
    }

    Write-RunReport ''
    Write-RunReport '[USER CONFIRMATION]'
    Write-RunReport ("Confirmed: {0}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))

    $backupResult = Invoke-PsqlScript -SqlPath $backupSql -StepName 'STEP 1 - BACKUP'
    if ($backupResult.ExitCode -ne 0) {
        Complete-RunReport -Status 'FAILED' -Details "Backup failed. No customer script was executed. Exit code: $($backupResult.ExitCode)"
        Show-RunnerMessage -Text "Backup SQL failed with exit code $($backupResult.ExitCode).`r`n`r`nNo customer script was executed.`r`n`r`nScript log:`r`n$($backupResult.LogPath)`r`n`r`nRun report:`r`n$reportPath" -Title 'Backup failed' -Icon Error
        exit $backupResult.ExitCode
    }

    for ($i = 0; $i -lt $customerScripts.Count; $i++) {
        $stepNumber = $i + 2
        $scriptPath = $customerScripts[$i]
        $scriptResult = Invoke-PsqlScript -SqlPath $scriptPath -StepName ("STEP {0} - CUSTOMER SQL" -f $stepNumber)
        if ($scriptResult.ExitCode -ne 0) {
            $remaining = $customerScripts.Count - $i - 1
            Complete-RunReport -Status 'FAILED' -Details "Step $stepNumber failed. Remaining customer scripts not executed: $remaining. Exit code: $($scriptResult.ExitCode)"
            Show-RunnerMessage -Text "Script step $stepNumber failed with exit code $($scriptResult.ExitCode).`r`n`r`nRemaining scripts not executed: $remaining`r`n`r`nScript log:`r`n$($scriptResult.LogPath)`r`n`r`nRun report:`r`n$reportPath" -Title 'Customer SQL failed' -Icon Error
            exit $scriptResult.ExitCode
        }
    }

    Complete-RunReport -Status 'SUCCESS' -Details "Backup scripts: 1; customer scripts: $($customerScripts.Count); total scripts: $($allScripts.Count)"
    Show-RunnerMessage -Text "All scripts completed successfully.`r`n`r`nBackup scripts: 1`r`nCustomer scripts: $($customerScripts.Count)`r`nTotal scripts: $($allScripts.Count)`r`n`r`nRun report:`r`n$reportPath" -Title 'Execution completed'
    exit 0
}
catch {
    $message = $_.Exception.Message
    Complete-RunReport -Status 'FAILED' -Details $message
    Write-Host ''
    Write-Host "ERROR: $message" -ForegroundColor Red
    $reportText = if ([string]::IsNullOrWhiteSpace($script:RunReportPath)) { '' } else { "`r`n`r`nRun report:`r`n$($script:RunReportPath)" }
    Show-RunnerMessage -Text ($message + $reportText) -Title 'Runner error' -Icon Error
    exit 1
}
finally {
    if (-not $script:RunReportFinalized -and $null -ne $script:RunReportWriter) {
        Complete-RunReport -Status 'ABORTED' -Details 'The runner ended before a final status was recorded.'
    }
    if ($null -ne $script:RunReportWriter) {
        $script:RunReportWriter.Dispose()
        $script:RunReportWriter = $null
    }
    if ($passwordSetByRunner) {
        Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
    }
}

