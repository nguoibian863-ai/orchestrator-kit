function Get-ResumeScenarioText {
    param([string]$Session, [string]$Content = 'changed')
    return "session id: $Session`n## OUTPUT_START`nworker-ok`n## OUTPUT_END`n"
}

function Set-ResumeSuccessScenario {
    param([string]$Project, [string]$Session = '', [string]$Content = 'changed')
    $text = "## OUTPUT_START`nworker-ok`n## OUTPUT_END`n"
    if ($Session) { $text = Get-ResumeScenarioText -Session $Session -Content $Content }
    Set-Scenario -Project $Project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = $Content },
            @{ op = 'stdout'; text = $text }
        )
        exit_code = 0
    }
}

$sessionId = '11111111-2222-3333-4444-555555555555'
$fakeWorker = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\fixtures\fake-worker.ps1')).Path
$resumeArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $fakeWorker, '-Scenario', 'tasks/{task_id}/scenario.json', '-Echo', '{session}')
$configPath = Join-Path $PSScriptRoot '..\..\templates\orchestrator\files\orchestrator.config.json'
$productConfig = Get-Content -Raw -Encoding UTF8 (Resolve-Path -LiteralPath $configPath).Path | ConvertFrom-Json

Add-Case -Name '66: codex resume_args co co truoc resume' -Body {
    $argsList = @($productConfig.workers.codex.resume_args)
    $resumeIndex = [Array]::IndexOf($argsList, 'resume')
    if ($resumeIndex -lt 0) { throw 'codex resume_args are missing resume' }
    $flagIndexes = @()
    for ($i = 0; $i -lt $argsList.Count; $i++) {
        if ([string]$argsList[$i] -like '--*') { $flagIndexes += $i }
    }
    if (@($flagIndexes | Where-Object { $_ -ge $resumeIndex }).Count -gt 0) {
        throw 'codex flags must come before resume'
    }
    if ($resumeIndex + 1 -ge $argsList.Count -or $argsList[$resumeIndex + 1] -ne '{session}') {
        throw 'codex session must immediately follow resume'
    }
}

Add-Case -Name '66: agy resume_args co --conversation lien truoc {session}' -Body {
    $argsList = @($productConfig.workers.agy.resume_args)
    $sessionIndex = [Array]::IndexOf($argsList, '{session}')
    if ($sessionIndex -lt 1 -or $argsList[$sessionIndex - 1] -ne '--conversation') {
        throw 'agy --conversation must immediately precede session'
    }
}

Add-Case -Name '66: text save session id from stdout' -Body {
    $project = New-TestProject
    Set-ResumeSuccessScenario -Project $project -Session $sessionId
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'text worker success code'
    $state = Read-ProjectFile -Project $project -Path 'state/task-state.json' | ConvertFrom-Json
    Assert-Equal -Expected $sessionId -Actual $state.tasks.T1.worker_session -Message 'session saved from stdout'
    Assert-Equal -Expected 'fake' -Actual $state.tasks.T1.worker_name -Message 'worker name saved'
}

Add-Case -Name '66: resume uses resume_args' -Body {
    $project = New-TestProject -WorkerOverrides @{ resume_args = $resumeArgs }
    Set-ProjectChecks -Project $project -Checks @(@{ name = 'ok'; command = 'cmd /c exit 0'; timeout_sec = 60 })
    Set-ResumeSuccessScenario -Project $project -Session $sessionId
    $first = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $first.ExitCode -Message 'first run success code'
    Set-ResumeSuccessScenario -Project $project -Content 'changed-again'
    $second = Invoke-ProductScript -Project $project -Script 'scripts/run-task.ps1' -Arguments @('-TaskId', 'T1', '-Fix')
    Assert-Equal -Expected 0 -Actual $second.ExitCode -Message 'resumed run success code'
    Assert-Match -Pattern 'echo:11111111-2222-3333-4444-555555555555' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'resume args received session'
}

Add-Case -Name '66: no session runs a new session' -Body {
    $project = New-TestProject -WorkerOverrides @{ resume_args = $resumeArgs }
    Set-ResumeSuccessScenario -Project $project
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1', '-Resume')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'new session success code'
    Assert-NotMatch -Pattern 'echo:' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'resume args were not used'
}

Add-Case -Name '66: different worker runs a new session' -Body {
    $project = New-TestProject -WorkerOverrides @{ resume_args = $resumeArgs }
    Set-ResumeSuccessScenario -Project $project -Session $sessionId
    $first = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $first.ExitCode -Message 'first run success code'
    $state = Read-ProjectFile -Project $project -Path 'state/task-state.json' | ConvertFrom-Json
    $state.tasks.T1.worker_name = 'other'
    Write-ProjectFile -Project $project -Path 'state/task-state.json' -Text (ConvertTo-Json -InputObject $state -Depth 10)
    Set-ResumeSuccessScenario -Project $project -Content 'changed-again'
    $second = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1', '-Resume')
    Assert-Equal -Expected 0 -Actual $second.ExitCode -Message 'fallback run success code'
    Assert-NotMatch -Pattern 'echo:' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'resume args were not used for another worker'
}

Add-Case -Name '66: missing resume_args runs a new session' -Body {
    $project = New-TestProject
    Set-ResumeSuccessScenario -Project $project -Session $sessionId
    $first = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $first.ExitCode -Message 'first run success code'
    Set-ResumeSuccessScenario -Project $project -Content 'changed-again'
    $second = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1', '-Resume')
    Assert-Equal -Expected 0 -Actual $second.ExitCode -Message 'fallback run success code'
    Assert-NotMatch -Pattern 'echo:' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'missing resume args were not used'
}

Add-Case -Name '66: metrics appends one valid row per call' -Body {
    $project = New-TestProject
    Set-ResumeSuccessScenario -Project $project -Content 'changed-one'
    $first = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $first.ExitCode -Message 'first metrics run success code'
    Set-ResumeSuccessScenario -Project $project -Content 'changed-two'
    $second = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $second.ExitCode -Message 'second metrics run success code'
    $lines = @((Read-ProjectFile -Project $project -Path 'tasks/T1/metrics.jsonl') -split "`r?`n" | Where-Object { $_ -ne '' })
    Assert-Equal -Expected 2 -Actual $lines.Count -Message 'two metrics rows appended'
    foreach ($line in $lines) {
        $metric = $line | ConvertFrom-Json
        Assert-Equal -Expected 'T1' -Actual $metric.task -Message 'metrics task field'
        Assert-Equal -Expected 'fake' -Actual $metric.worker -Message 'metrics worker field'
        if ($metric.exit -isnot [ValueType] -or $metric.exit -is [bool]) { throw 'metrics exit must be numeric' }
    }
}

Add-Case -Name '66: metrics are written when worker fails' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{ actions = @(); exit_code = 3 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 3 -Actual $result.ExitCode -Message 'worker error code'
    $lines = @((Read-ProjectFile -Project $project -Path 'tasks/T1/metrics.jsonl') -split "`r?`n" | Where-Object { $_ -ne '' })
    Assert-Equal -Expected 1 -Actual $lines.Count -Message 'failed run metrics row count'
    $metric = $lines[0] | ConvertFrom-Json
    Assert-Equal -Expected 3 -Actual $metric.exit -Message 'failed run metrics exit'
}
