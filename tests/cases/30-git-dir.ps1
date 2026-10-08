Add-Case -Name '30: hook moi -> 6' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = '.git/hooks/pre-commit'; text = 'hook' },
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'new hook code'
    Assert-Match -Pattern 'A \.git/hooks/pre-commit' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'new hook in log'
}

Add-Case -Name '30: sua hook co san -> 6' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path '.git/hooks/post-checkout' -Text 'old'
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'append'; path = '.git/hooks/post-checkout'; text = 'new' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'modified hook code'
    Assert-Match -Pattern 'M \.git/hooks/post-checkout' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'modified hook in log'
}

Add-Case -Name '30: xoa hook -> 6' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path '.git/hooks/post-checkout' -Text 'old'
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'delete'; path = '.git/hooks/post-checkout' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'deleted hook code'
    Assert-Match -Pattern 'D \.git/hooks/post-checkout' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'deleted hook in log'
}

Add-Case -Name '30: sua .git/config -> 6, khong goi git diff' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'append'; path = '.git/config'; text = "`n[smoke]`n    value = changed`n" },
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'git config code'
    $expectedNotice = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('KEtow7RuZyBsaeG7h3Qga8OqOiB3b3JrZXIgxJHDoyBz4butYSAuZ2l0L2NvbmZpZyBob+G6t2MgLmdpdC9pbmZvIOKAlCBnaXQgZGlmZiBjw7MgdGjhu4MgY2jhuqF5IGzhu4duaCBkbyBj4bqldSBow6xuaCBjaOG7iSDEkeG7i25oLiBYZW0gdGFza3MvVDEvd29ya2VyLmxvZywgbeG7pWMgR0lULURJUi4p'))
    Assert-Equal -Expected $expectedNotice -Actual (Read-ProjectFile -Project $project -Path 'tasks/T1/changed-files.txt').Trim() -Message 'unsafe git changed files notice'
    Assert-NotMatch -Pattern 'src/a\.txt' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/changed-files.txt') -Message 'git diff was skipped'
    Assert-Match -Pattern 'M \.git/config' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'git config in log'
}

Add-Case -Name '30: sua .git/info/exclude -> 6' -Body {
    $project = New-TestProject
    if (-not (Test-Path -LiteralPath (Join-Path $project '.git/info/exclude'))) {
        Write-ProjectFile -Project $project -Path '.git/info/exclude' -Text ''
    }
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'append'; path = '.git/info/exclude'; text = "`n# smoke`n" },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'git info code'
    Assert-Match -Pattern 'M \.git/info/exclude' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'git info in log'
}

Add-Case -Name '30: core.hooksPath -> 6' -Body {
    $project = New-TestProject
    $configResult = Invoke-TestGit -Project $project -Arguments 'config core.hooksPath .githooks'
    Assert-Equal -Expected 0 -Actual $configResult.ExitCode -Message 'set core.hooksPath'
    Write-ProjectFile -Project $project -Path '.githooks/pre-commit' -Text 'old'
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'append'; path = '.githooks/pre-commit'; text = 'new' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'hooksPath code'
    Assert-Match -Pattern 'M \.githooks/pre-commit' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'hooksPath hook in log'
}

Add-Case -Name '30: hook roi qua timeout -> 6' -Body {
    $project = New-TestProject -WorkerOverrides @{ timeout_sec = 5 }
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = '.git/hooks/pre-commit'; text = 'hook' },
            @{ op = 'sleep'; seconds = 60 }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1') -TimeoutSec 120
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'git change must beat timeout'
    Assert-Match -Pattern 'A \.git/hooks/pre-commit' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'timed out hook in log'
}

Add-Case -Name '30: hook va exit 3 -> 6' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = '.git/hooks/pre-commit'; text = 'hook' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 3
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'git change must beat worker exit'
}

Add-Case -Name '30: khong dong .git -> 0' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'clean git directory code'
}
