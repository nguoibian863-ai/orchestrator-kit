Add-Case -Name '10: text co marker va doi file -> 0' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nsmoke-ok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'run-worker success code'
    Assert-Match -Pattern 'smoke-ok' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/output.md') -Message 'output marker content'
    Assert-Equal -Expected 'changed' -Actual (Read-ProjectFile -Project $project -Path 'src/a.txt') -Message 'worker file change'
}

Add-Case -Name '10: text khong marker -> 5' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = 'plain response without markers' }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 5 -Actual $result.ExitCode -Message 'missing marker code'
}

Add-Case -Name '10: text co marker, khong doi file -> 7' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(@{ op = 'stdout'; text = "## OUTPUT_START`nsmoke-ok`n## OUTPUT_END`n" })
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 7 -Actual $result.ExitCode -Message 'no changes code'
}

Add-Case -Name '10: worker exit 3 -> 3' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{ actions = @(); exit_code = 3 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 3 -Actual $result.ExitCode -Message 'worker failure code'
}

Add-Case -Name '10: qua timeout -> 124' -Body {
    $project = New-TestProject -WorkerOverrides @{ timeout_sec = 3 }
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'sleep'; seconds = 60 }); exit_code = 0 }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1') -TimeoutSec 120
    $watch.Stop()
    Assert-Equal -Expected 124 -Actual $result.ExitCode -Message 'worker timeout code'
    if ($watch.Elapsed.TotalSeconds -ge 120) { throw 'run-worker did not return before the harness timeout' }
}

Add-Case -Name '10: sua file trong scripts/ -> 6' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'write'; path = 'scripts/evil.txt'; text = 'forbidden' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nsmoke-ok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'protected path code'
}

Add-Case -Name '10: vi pham do-not-modify.txt -> 6' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/do-not-modify.txt' -Text "src/locked/**`n"
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/locked/a.txt'; text = 'forbidden' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nsmoke-ok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'do-not-modify code'
}

Add-Case -Name '10: -Worker khong ton tai -> 1' -Body {
    $project = New-TestProject
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1', '-Worker', 'missing')
    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message 'unknown worker code'
}

Add-Case -Name '10: prompt rong -> 1' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/prompt.md' -Text ''
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message 'empty prompt code'
}
