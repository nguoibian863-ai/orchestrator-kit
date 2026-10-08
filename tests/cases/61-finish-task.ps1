function Set-ReviewReports {
    param([string]$Project, [string]$ReviewerText = '')
    $name = Invoke-TestGit -Project $Project -Arguments 'config user.name smoke'
    if ($name.ExitCode -ne 0) { throw "git user.name setup failed: $($name.Output)" }
    $email = Invoke-TestGit -Project $Project -Arguments 'config user.email smoke@example.invalid'
    if ($email.ExitCode -ne 0) { throw "git user.email setup failed: $($email.Output)" }
    Write-ProjectFile -Project $Project -Path 'tasks/T1/reviewer-output.md' -Text $ReviewerText
    Write-ProjectFile -Project $Project -Path 'tasks/T1/security-output.md' -Text ''
    Write-ProjectFile -Project $Project -Path 'tasks/T1/qa-output.md' -Text ''
}

function Add-TrackedTaskChange {
    param([string]$Project)
    Write-ProjectFile -Project $Project -Path 'src/a.txt' -Text 'task change'
}

Add-Case -Name '61: review passes -> 0 and commit' -Body {
    $project = New-TestProject
    Add-TrackedTaskChange -Project $project
    Set-ReviewReports -Project $project
    $result = Invoke-ProductScript -Project $project -Script 'scripts/finish-task.ps1' -Arguments @('-TaskId', 'T1', '-Message', 'smoke change')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'finish-task success code'
    $log = Invoke-TestGit -Project $project -Arguments 'log -1 --pretty=%s'
    Assert-Match -Pattern '\[worker\] T1:' -Text $log.Output -Message 'commit subject'
    $state = Read-ProjectFile -Project $project -Path 'state/task-state.json' | ConvertFrom-Json
    Assert-Equal -Expected 'approved' -Actual $state.tasks.T1.status -Message 'approved state'
}

Add-Case -Name '61: HIGH remains -> 1 without commit' -Body {
    $project = New-TestProject
    Add-TrackedTaskChange -Project $project
    Set-ReviewReports -Project $project -ReviewerText "## HIGH`n- finding`n"
    $before = Invoke-TestGit -Project $project -Arguments 'rev-list --count HEAD'
    $result = Invoke-ProductScript -Project $project -Script 'scripts/finish-task.ps1' -Arguments @('-TaskId', 'T1', '-Message', 'smoke change')
    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message 'blocking review code'
    $after = Invoke-TestGit -Project $project -Arguments 'rev-list --count HEAD'
    Assert-Equal -Expected $before.Output.Trim() -Actual $after.Output.Trim() -Message 'commit count unchanged'
    $state = Read-ProjectFile -Project $project -Path 'state/task-state.json' | ConvertFrom-Json
    Assert-NotMatch -Pattern '"status"\s*:\s*"approved"' -Text (ConvertTo-Json -InputObject $state.tasks.T1) -Message 'task is not approved'
}

Add-Case -Name '61: missing report -> 2' -Body {
    $project = New-TestProject
    Set-ReviewReports -Project $project
    Remove-Item -LiteralPath (Join-Path $project 'tasks/T1/qa-output.md') -Force
    $result = Invoke-ProductScript -Project $project -Script 'scripts/finish-task.ps1' -Arguments @('-TaskId', 'T1', '-Message', 'smoke change')
    Assert-Equal -Expected 2 -Actual $result.ExitCode -Message 'missing review report code'
}
