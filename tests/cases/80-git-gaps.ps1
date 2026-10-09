function Set-TestTaskBase {
    param([string]$Project)
    $add = Invoke-TestGit -Project $Project -Arguments 'add -A'
    if ($add.ExitCode -ne 0) { throw "git add failed: $($add.Output)" }
    $commit = Invoke-TestGit -Project $Project -Arguments '-c commit.gpgsign=false -c user.name=smoke -c user.email=smoke@example.invalid commit -m scope'
    if ($commit.ExitCode -ne 0) { throw "git commit failed: $($commit.Output)" }
    $head = Invoke-TestGit -Project $Project -Arguments 'rev-parse HEAD'
    if ($head.ExitCode -ne 0) { throw "git rev-parse failed: $($head.Output)" }
    $state = Read-ProjectFile -Project $Project -Path 'state/task-state.json' | ConvertFrom-Json
    $state.tasks.T1.base_commit = $head.Output.Trim()
    Write-ProjectFile -Project $Project -Path 'state/task-state.json' -Text (ConvertTo-Json -InputObject $state -Depth 10)
}

Add-Case -Name '80: sua .gitignore -> 6' -Body {
    $project = New-TestProject
    $config = Read-ProjectFile -Project $project -Path 'orchestrator.config.json' | ConvertFrom-Json
    $config.scope | Add-Member -NotePropertyName watched_external -NotePropertyValue @() -Force
    Write-ProjectFile -Project $project -Path 'orchestrator.config.json' -Text (ConvertTo-Json -InputObject $config -Depth 10)
    Set-TestTaskBase -Project $project
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'append'; path = '.gitignore'; text = "`nsrc/secret/**`n" },
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'gitignore change code'
    Assert-Match -Pattern '\.gitignore \(gitignore\)' -Text $result.Output -Message 'gitignore change label'
    Assert-NotMatch -Pattern 'src/a\.txt' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/changed-files.txt') -Message 'gitignore change skips listing'
}

Add-Case -Name '80: tao .gitignore moi trong thu muc con -> 6' -Body {
    $project = New-TestProject
    $config = Read-ProjectFile -Project $project -Path 'orchestrator.config.json' | ConvertFrom-Json
    $config.scope | Add-Member -NotePropertyName watched_external -NotePropertyValue @() -Force
    Write-ProjectFile -Project $project -Path 'orchestrator.config.json' -Text (ConvertTo-Json -InputObject $config -Depth 10)
    Set-TestTaskBase -Project $project
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/.gitignore'; text = "secret/**`n" },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'new nested gitignore code'
    Assert-Match -Pattern 'src/\.gitignore \(gitignore\)' -Text $result.Output -Message 'new nested gitignore path'
}

Add-Case -Name '80: sua HEAD -> 6' -Body {
    $project = New-TestProject
    $config = Read-ProjectFile -Project $project -Path 'orchestrator.config.json' | ConvertFrom-Json
    $config.scope | Add-Member -NotePropertyName watched_external -NotePropertyValue @() -Force
    Write-ProjectFile -Project $project -Path 'orchestrator.config.json' -Text (ConvertTo-Json -InputObject $config -Depth 10)
    Set-TestTaskBase -Project $project
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'append'; path = '.git/HEAD'; text = "`n" },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'HEAD change code'
    Assert-Match -Pattern '\.git/HEAD \(refs\)' -Text $result.Output -Message 'HEAD refs label'
}

Add-Case -Name '80: sua ref nhanh -> 6' -Body {
    $project = New-TestProject
    $config = Read-ProjectFile -Project $project -Path 'orchestrator.config.json' | ConvertFrom-Json
    $config.scope | Add-Member -NotePropertyName watched_external -NotePropertyValue @() -Force
    Write-ProjectFile -Project $project -Path 'orchestrator.config.json' -Text (ConvertTo-Json -InputObject $config -Depth 10)
    Set-TestTaskBase -Project $project
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'append'; path = '.git/refs/heads/feature/T1'; text = "`n" },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'branch ref change code'
    Assert-Match -Pattern '\(refs\)' -Text $result.Output -Message 'branch ref label'
}

Add-Case -Name '80: sua file watched_external -> 6' -Body {
    $project = New-TestProject
    $config = Read-ProjectFile -Project $project -Path 'orchestrator.config.json' | ConvertFrom-Json
    $config.scope | Add-Member -NotePropertyName watched_external -NotePropertyValue @('ext/conf.json') -Force
    Write-ProjectFile -Project $project -Path 'orchestrator.config.json' -Text (ConvertTo-Json -InputObject $config -Depth 10)
    Write-ProjectFile -Project $project -Path 'ext/conf.json' -Text '{"enabled":false}'
    Set-TestTaskBase -Project $project
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'append'; path = 'ext/conf.json'; text = "`n" },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'external file change code'
    Assert-Match -Pattern 'ext/conf\.json \(external\)' -Text $result.Output -Message 'external file label'
}

Add-Case -Name '80: watched_external rong -> 0' -Body {
    $project = New-TestProject
    $config = Read-ProjectFile -Project $project -Path 'orchestrator.config.json' | ConvertFrom-Json
    $config.scope | Add-Member -NotePropertyName watched_external -NotePropertyValue @() -Force
    Write-ProjectFile -Project $project -Path 'orchestrator.config.json' -Text (ConvertTo-Json -InputObject $config -Depth 10)
    Set-TestTaskBase -Project $project
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'empty external watch code'
}

Add-Case -Name '80: khong dong gi -> 0' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'unchanged watched roots code'
}
