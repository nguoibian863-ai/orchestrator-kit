Add-Case -Name '81: bo qua .gitignore trong thu muc ignored' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/zz/.gitignore' -Text "old`n"
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'append'; path = 'tasks/zz/.gitignore'; text = "new`n" },
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nsmoke-ok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'ignored gitignore change code'
    Assert-Equal -Expected "old`nnew`n" -Actual (Read-ProjectFile -Project $project -Path 'tasks/zz/.gitignore') -Message 'ignored gitignore was appended'
    Assert-Equal -Expected 'changed' -Actual (Read-ProjectFile -Project $project -Path 'src/a.txt') -Message 'regular file was changed'
}

Add-Case -Name '81: van bat .gitignore ngoai thu muc ignored' -Body {
    $project = New-TestProject
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/.gitignore'; text = "secret/**`n" },
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "## OUTPUT_START`nsmoke-ok`n## OUTPUT_END`n" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 6 -Actual $result.ExitCode -Message 'non-ignored gitignore change code'
    Assert-Match -Pattern 'src/\.gitignore' -Text $result.Output -Message 'new gitignore path is reported'
}
