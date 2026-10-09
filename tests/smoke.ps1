param(
    [string]$Filter = '*',
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$script:Cases = New-Object System.Collections.ArrayList
$script:ProjectIndex = 0
$script:SmokeRoot = $null
$script:GitConfigFile = $null
$script:LastProductOutput = ''
$script:StartedAt = [DateTime]::UtcNow
$script:PowerShellExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false
foreach ($name in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE')) {
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}

function Add-Case {
    param([string]$Name, [scriptblock]$Body)
    [void]$script:Cases.Add([pscustomobject]@{ Name = $Name; Body = $Body })
}

function ConvertTo-ProcessArgument {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $slashes++
            continue
        }
        if ($character -eq [char]34) {
            if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
            [void]$builder.Append('\"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Stop-TestProcessTree {
    param([int]$ProcessId)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'taskkill.exe'
    $psi.Arguments = "/T /F /PID $ProcessId"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $killer = [Diagnostics.Process]::Start($psi)
    [void]$killer.StandardOutput.ReadToEndAsync()
    [void]$killer.StandardError.ReadToEndAsync()
    [void]$killer.WaitForExit(15000)
}

function Invoke-TestProcess {
    param(
        [string]$FileName,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutSec = 180
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join ' ')
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:Utf8NoBom
    $psi.StandardErrorEncoding = $script:Utf8NoBom
    foreach ($name in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE')) {
        [void]$psi.EnvironmentVariables.Remove($name)
    }
    if ($script:GitConfigFile -and (Test-Path -LiteralPath $script:GitConfigFile)) {
        $psi.EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] = '1'
        $psi.EnvironmentVariables['GIT_CONFIG_GLOBAL'] = $script:GitConfigFile
    }

    $process = [Diagnostics.Process]::Start($psi)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $finished = $process.WaitForExit([int]([Math]::Max(1, $TimeoutSec) * 1000))
    if ($finished) {
        $process.WaitForExit()
    } else {
        Stop-TestProcessTree $process.Id
        [void]$process.WaitForExit(10000)
    }
    $stdout = if ($stdoutTask.Wait(10000)) { $stdoutTask.Result } else { '' }
    $stderr = if ($stderrTask.Wait(10000)) { $stderrTask.Result } else { '' }
    $exitCode = if ($finished) { $process.ExitCode } else { 124 }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $stdout + $stderr
        StdOut = $stdout
        StdErr = $stderr
        TimedOut = (-not $finished)
    }
}

function Invoke-ProductScript {
    param(
        [string]$Project,
        [string]$Script,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 180
    )
    $scriptPath = Join-Path $Project $Script
    $processArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $Arguments
    $result = Invoke-TestProcess -FileName $script:PowerShellExe -Arguments $processArguments -WorkingDirectory $Project -TimeoutSec $TimeoutSec
    $script:LastProductOutput = $result.Output
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $result.Output }
}

function Invoke-TestGit {
    param([string]$Project, [string]$Arguments)
    $gitArguments = @('-C', $Project) + @($Arguments.Trim() -split '\s+')
    $result = Invoke-TestProcess -FileName 'git' -Arguments $gitArguments -WorkingDirectory $Project -TimeoutSec 60
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $result.Output }
}

function Write-ProjectFile {
    param([string]$Project, [string]$Path, [string]$Text)
    $fullPath = Join-Path $Project $Path
    $parent = Split-Path -Parent $fullPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    [IO.File]::WriteAllText($fullPath, $Text, $script:Utf8NoBom)
}

function Read-ProjectFile {
    param([string]$Project, [string]$Path)
    $fullPath = Join-Path $Project $Path
    if (-not (Test-Path -LiteralPath $fullPath)) { return '' }
    return [IO.File]::ReadAllText($fullPath, $script:Utf8NoBom)
}

function Assert-Equal {
    param([object]$Expected, [object]$Actual, [string]$Message)
    $equal = $false
    if ($null -eq $Expected -and $null -eq $Actual) {
        $equal = $true
    } elseif ($null -ne $Expected -and $null -ne $Actual) {
        $expectedNumber = [decimal]0
        $actualNumber = [decimal]0
        $numberStyles = [Globalization.NumberStyles]::Float
        $culture = [Globalization.CultureInfo]::InvariantCulture
        $expectedIsNumber = [decimal]::TryParse([string]$Expected, $numberStyles, $culture, [ref]$expectedNumber)
        $actualIsNumber = [decimal]::TryParse([string]$Actual, $numberStyles, $culture, [ref]$actualNumber)
        if ($expectedIsNumber -and $actualIsNumber) {
            $equal = ($expectedNumber -eq $actualNumber)
        } elseif ($Expected -is [bool] -and $Actual -is [bool]) {
            $equal = ($Expected -eq $Actual)
        } else {
            $equal = [object]::Equals($Expected, $Actual)
        }
    }

    if (-not $equal) {
        $expectedType = if ($null -eq $Expected) { '<null>' } else { $Expected.GetType().FullName }
        $actualType = if ($null -eq $Actual) { '<null>' } else { $Actual.GetType().FullName }
        $expectedDisplay = if ($null -eq $Expected) { '<null>' } else { [string]$Expected }
        $actualDisplay = if ($null -eq $Actual) { '<null>' } else { [string]$Actual }
        throw "assert equal failed: $Message | expected $expectedDisplay ($expectedType), got $actualDisplay ($actualType)"
    }
}

function Assert-Match {
    param([string]$Pattern, [string]$Text, [string]$Message)
    if (-not [regex]::IsMatch([string]$Text, $Pattern)) {
        throw "assert match failed: $Message | pattern '$Pattern'"
    }
}

function Assert-NotMatch {
    param([string]$Pattern, [string]$Text, [string]$Message)
    if ([regex]::IsMatch([string]$Text, $Pattern)) {
        throw "assert not match failed: $Message | pattern '$Pattern'"
    }
}

function Set-Scenario {
    param([string]$Project, [hashtable]$Scenario)
    $json = ConvertTo-Json -InputObject $Scenario -Depth 6
    Write-ProjectFile -Project $Project -Path 'tasks/T1/scenario.json' -Text $json
}

function New-TestProject {
    param(
        [hashtable]$WorkerOverrides = @{},
        [string[]]$Protected = $null
    )
    $script:ProjectIndex++
    $projectName = 'p{0:D2}' -f $script:ProjectIndex
    $project = Join-Path $script:SmokeRoot $projectName
    [void](New-Item -ItemType Directory -Force -Path $project)

    $sourceScripts = Join-Path $PSScriptRoot '..\templates\orchestrator\files\scripts'
    $sourceScripts = (Resolve-Path -LiteralPath $sourceScripts).Path
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $project 'scripts'))
    Copy-Item -Path (Join-Path $sourceScripts '*') -Destination (Join-Path $project 'scripts') -Recurse -Force

    Write-ProjectFile -Project $project -Path '.gitignore' -Text "state/`ntasks/`nreviews/`n"
    Write-ProjectFile -Project $project -Path 'src/.gitkeep' -Text ''
    Write-ProjectFile -Project $project -Path 'state/task-state.json' -Text '{"tasks":{}}'
    Write-ProjectFile -Project $project -Path 'state/workflow-state.json' -Text '{"feature":null,"current_phase":null,"tasks":[],"blocked_tasks":[],"started_at":null}'
    if ($null -eq $Protected) { $Protected = @('.claude/', 'scripts/', 'orchestrator.config.json') }

    $worker = @{
        command = 'powershell'
        args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'fixtures/fake-worker.ps1'), '-Scenario', 'tasks/{task_id}/scenario.json')
        stdin_prompt = $false
        timeout_sec = 60
        env = @{}
    }
    foreach ($key in $WorkerOverrides.Keys) { $worker[$key] = $WorkerOverrides[$key] }
    $config = @{
        worker = 'fake'
        workers = @{ fake = $worker }
        checks = @()
        git = @{ branch_prefix = 'feature/'; protected_branches = @('main', 'master', 'develop') }
        scope = @{
            always_protected = $Protected
            ignored = @('tasks/', 'reviews/', 'state/')
        }
    }
    Write-ProjectFile -Project $project -Path 'orchestrator.config.json' -Text (ConvertTo-Json -InputObject $config -Depth 10)

    $gitInit = Invoke-TestGit -Project $project -Arguments 'init'
    if ($gitInit.ExitCode -ne 0) { throw "git init failed: $($gitInit.Output)" }
    $gitAdd = Invoke-TestGit -Project $project -Arguments 'add -A'
    if ($gitAdd.ExitCode -ne 0) { throw "git add failed: $($gitAdd.Output)" }
    $gitCommit = Invoke-TestGit -Project $project -Arguments '-c commit.gpgsign=false -c user.name=smoke -c user.email=smoke@example.invalid commit -m init'
    if ($gitCommit.ExitCode -ne 0) { throw "git commit failed: $($gitCommit.Output)" }

    $start = Invoke-ProductScript -Project $project -Script 'scripts/start-task.ps1' -Arguments @('-TaskId', 'T1')
    if ($start.ExitCode -ne 0) { throw "start-task failed with exit $($start.ExitCode): $($start.Output)" }
    Write-ProjectFile -Project $project -Path 'tasks/T1/prompt.md' -Text 'smoke prompt'
    return $project
}

function Test-PathIsWithin {
    param([string]$Path, [string]$Root)
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function New-SmokeRoot {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $tempRoot = [IO.Path]::GetFullPath($env:TEMP)
    $candidateRoot = Join-Path $tempRoot 'oks-placeholder'
    if (Test-PathIsWithin -Path $candidateRoot -Root $repoRoot) {
        throw 'TEMP resolves inside the repository.'
    }
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $suffix = ''
        for ($i = 0; $i -lt 6; $i++) {
            $n = Get-Random -Minimum 0 -Maximum 36
            if ($n -lt 10) { $suffix += [string]$n }
            else { $suffix += [char](97 + $n - 10) }
        }
        $path = Join-Path $tempRoot ('oks-' + $suffix)
        if (-not (Test-Path -LiteralPath $path)) {
            [void](New-Item -ItemType Directory -Path $path -ErrorAction Stop)
            return $path
        }
    }
    throw 'Could not allocate a unique temporary directory.'
}

function Remove-SmokeRoot {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -lt 4) { Start-Sleep -Milliseconds 500 }
        }
    }
    Write-Warning "Could not remove temporary directory: $Path"
}

function Write-FailureTail {
    param([string]$Output, [int]$MaxLines = 15)
    $lines = @($Output -split "[\r\n]+")
    $lines = @($lines | Where-Object { $_ -ne '' })
    if ($env:SMOKE_FULL_OUTPUT -ne '1' -and $lines.Count -gt $MaxLines) {
        $lines = @($lines | Select-Object -Last $MaxLines)
    }
    foreach ($line in $lines) { Write-Host "      $line" }
}

$passed = 0
$failed = 0
$environmentError = $null
try {
    if ([string]::IsNullOrWhiteSpace($env:TEMP)) { throw 'TEMP is not set.' }
    $sourceScripts = Join-Path $PSScriptRoot '..\templates\orchestrator\files\scripts'
    if (-not (Test-Path -LiteralPath $sourceScripts -PathType Container)) { throw 'Product scripts directory is missing.' }
    $gitVersion = Invoke-TestProcess -FileName 'git' -Arguments @('--version') -WorkingDirectory $PSScriptRoot -TimeoutSec 15
    if ($gitVersion.ExitCode -ne 0) { throw 'git --version failed.' }
    $script:SmokeRoot = New-SmokeRoot
    $script:GitConfigFile = Join-Path $script:SmokeRoot 'empty-git-config'
    [IO.File]::WriteAllText($script:GitConfigFile, '', $script:Utf8NoBom)
    $caseFiles = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'cases') -Filter '*.ps1' -File | Sort-Object Name
    foreach ($caseFile in $caseFiles) { . $caseFile.FullName }

    foreach ($testCase in @($script:Cases | Where-Object { $_.Name -like $Filter })) {
        $script:LastProductOutput = ''
        try {
            & $testCase.Body
            $passed++
            Write-Host "PASS  $($testCase.Name)"
        } catch {
            $failed++
            $reason = $_.Exception.Message -replace '[\r\n]+', ' '
            Write-Host "FAIL  $($testCase.Name) | $reason"
            if ($script:LastProductOutput) { Write-FailureTail $script:LastProductOutput }
        }
    }
} catch {
    $environmentError = $_.Exception.Message -replace '[\r\n]+', ' '
    Write-Host "Smoke environment error: $environmentError"
} finally {
    if ($Keep -and $script:SmokeRoot) {
        Write-Host "Kept: $script:SmokeRoot"
    } elseif ($script:SmokeRoot) {
        Remove-SmokeRoot $script:SmokeRoot
    }
}

$elapsed = ([DateTime]::UtcNow - $script:StartedAt).TotalSeconds.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
Write-Host "Smoke: $passed passed, $failed failed (${elapsed}s)"
if ($environmentError) { exit 2 }
if ($failed -gt 0) { exit 1 }
exit 0
