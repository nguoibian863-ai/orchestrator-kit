Add-Case -Name '82: khong phai git repo -> 1 va bao loi git' -Body {
    $project = New-TestProject
    Remove-Item -LiteralPath (Join-Path $project '.git') -Recurse -Force
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message 'missing git repo code'
    Assert-Match -Pattern 'rev-parse' -Text $result.Output -Message 'git branch failure includes command'
}

Add-Case -Name '82: dang o nhanh khac -> 1' -Body {
    $project = New-TestProject
    $checkout = Invoke-TestGit -Project $project -Arguments 'checkout -q -b other-branch'
    Assert-Equal -Expected 0 -Actual $checkout.ExitCode -Message 'checkout other branch'
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message 'wrong branch code'
}