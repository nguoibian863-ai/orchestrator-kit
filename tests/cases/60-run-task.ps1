function Set-ProjectChecks {
    param(
        [string]$Project,
        [object[]]$Checks,
        [int]$MaxFixAttempts = -1
    )
    $config = Read-ProjectFile -Project $Project -Path 'orchestrator.config.json' | ConvertFrom-Json
    $config.checks = @($Checks)
    if ($MaxFixAttempts -gt 0) {
        if ($config.PSObject.Properties.Name -contains 'max_fix_attempts') { $config.max_fix_attempts = $MaxFixAttempts }
        else { $config | Add-Member -NotePropertyName max_fix_attempts -NotePropertyValue $MaxFixAttempts }
    }
    Write-ProjectFile -Project $Project -Path 'orchestrator.config.json' -Text (ConvertTo-Json -InputObject $config -Depth 10)
    $add = Invoke-TestGit -Project $Project -Arguments 'add orchestrator.config.json'
    if ($add.ExitCode -ne 0) { throw "config git add failed: $($add.Output)" }
    $commit = Invoke-TestGit -Project $Project -Arguments '-c user.name=smoke -c user.email=smoke@example.invalid commit -m smoke-config'
    if ($commit.ExitCode -ne 0) { throw "config git commit failed: $($commit.Output)" }
    $head = Invoke-TestGit -Project $Project -Arguments 'rev-parse HEAD'
    if ($head.ExitCode -ne 0) { throw "config baseline lookup failed: $($head.Output)" }
    $state = Read-ProjectFile -Project $Project -Path 'state/task-state.json' | ConvertFrom-Json
    $state.tasks.T1.base_commit = $head.Output.Trim()
    if ($MaxFixAttempts -gt 0) { $state.tasks.T1.max_fix_attempts = $MaxFixAttempts }
    Write-ProjectFile -Project $Project -Path 'state/task-state.json' -Text (ConvertTo-Json -InputObject $state -Depth 10)
}

function Set-WorkerSuccessScenario {
    param([string]$Project)
    Set-Scenario -Project $Project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nworker-ok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
}

Add-Case -Name '60: run-task success -> 0 and checked' -Body {
    $project = New-TestProject
    Set-WorkerSuccessScenario -Project $project
    Set-ProjectChecks -Project $project -Checks @(@{ name = 'ok'; command = 'cmd /c exit 0'; timeout_sec = 60 })
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-task.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'run-task success code'
    $state = Read-ProjectFile -Project $project -Path 'state/task-state.json' | ConvertFrom-Json
    Assert-Equal -Expected 'checked' -Actual $state.tasks.T1.status -Message 'checked state'
    Assert-Match -Pattern 'cmd /c exit 0' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/checks.log') -Message 'checks command is logged'
    Assert-NotMatch -Pattern 'cmd /c exit 0' -Text $result.Output -Message 'successful child output is suppressed'
    $checkOutput = Invoke-ProductScript -Project $project -Script 'scripts/run-checks.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $checkOutput.ExitCode -Message 'direct checks success code'
    Assert-Match -Pattern '== ok' -Text $checkOutput.Output -Message 'check name is printed'
    Assert-NotMatch -Pattern '== ok: cmd /c exit 0' -Text $checkOutput.Output -Message 'check command is not printed'
}

Add-Case -Name '60: worker exit 3 -> 3' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{ actions = @(); exit_code = 3 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-task.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 3 -Actual $result.ExitCode -Message 'worker error code is preserved'
    Assert-NotMatch -Pattern '-> run-checks' -Text $result.Output -Message 'checks did not run after worker failure'
}

Add-Case -Name '60: checks FAIL -> 1' -Body {
    $project = New-TestProject
    Set-WorkerSuccessScenario -Project $project
    Set-ProjectChecks -Project $project -Checks @(@{ name = 'fail'; command = 'cmd /c exit 1'; timeout_sec = 60 })
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-task.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message 'checks error code'
    Assert-Match -Pattern 'D.*run-checks.*1' -Text $result.Output -Message 'failed step is identified'
}

Add-Case -Name '60: no checks -> 2' -Body {
    $project = New-TestProject
    Set-WorkerSuccessScenario -Project $project
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-task.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 2 -Actual $result.ExitCode -Message 'missing checks code is preserved'
    Assert-Match -Pattern 'D.*run-checks.*2' -Text $result.Output -Message 'missing checks step is identified'
}

Add-Case -Name '60: -Fix increments attempts' -Body {
    $project = New-TestProject
    Set-WorkerSuccessScenario -Project $project
    Set-ProjectChecks -Project $project -Checks @(@{ name = 'ok'; command = 'cmd /c exit 0'; timeout_sec = 60 })
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-task.ps1' -Arguments @('-TaskId', 'T1', '-Fix')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'fix success code'
    $state = Read-ProjectFile -Project $project -Path 'state/task-state.json' | ConvertFrom-Json
    Assert-Equal -Expected 1 -Actual $state.tasks.T1.fix_attempts -Message 'fix attempt count'
}

Add-Case -Name '60: -Fix exhausted -> 3' -Body {
    $project = New-TestProject
    Set-WorkerSuccessScenario -Project $project
    Set-ProjectChecks -Project $project -Checks @(@{ name = 'ok'; command = 'cmd /c exit 0'; timeout_sec = 60 }) -MaxFixAttempts 1
    $first = Invoke-ProductScript -Project $project -Script 'scripts/run-task.ps1' -Arguments @('-TaskId', 'T1', '-Fix')
    Assert-Equal -Expected 0 -Actual $first.ExitCode -Message 'first fix succeeds'
    $second = Invoke-ProductScript -Project $project -Script 'scripts/run-task.ps1' -Arguments @('-TaskId', 'T1', '-Fix')
    Assert-Equal -Expected 3 -Actual $second.ExitCode -Message 'fix limit code is preserved'
    Assert-NotMatch -Pattern '-> run-worker' -Text $second.Output -Message 'worker did not run after fix limit'
    $state = Read-ProjectFile -Project $project -Path 'state/task-state.json' | ConvertFrom-Json
    Assert-Equal -Expected 'blocked' -Actual $state.tasks.T1.status -Message 'task is blocked at fix limit'
}
Add-Case -Name '60: run-task khong tu cat worker truoc timeout_sec' -Body {
    $project = New-TestProject -WorkerOverrides @{ timeout_sec = 3 }
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'sleep'; seconds = 30 }); exit_code = 0 }
    Set-ProjectChecks -Project $project -Checks @(@{ name = 'ok'; command = 'cmd /c exit 0'; timeout_sec = 60 })
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-task.ps1' -Arguments @('-TaskId', 'T1') -TimeoutSec 120
    $watch.Stop()
    $state = Read-ProjectFile -Project $project -Path 'state/task-state.json' | ConvertFrom-Json
    $taskState = $state.tasks.T1
    $diagnostic = "run-worker timeout code is preserved; state: status=$($taskState.status), branch=$($taskState.branch), fix_attempts=$($taskState.fix_attempts); run-task output: $($result.Output)"
    Assert-Equal -Expected 124 -Actual $result.ExitCode -Message $diagnostic
    $workerLog = Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log'
    Assert-Match -Pattern 'timeout=True' -Text $workerLog -Message 'worker handled its configured timeout'
    if ($watch.Elapsed.TotalSeconds -ge 60) { throw ('run-task did not return before the worker sleep finished ({0:N1}s)' -f $watch.Elapsed.TotalSeconds) }
}
