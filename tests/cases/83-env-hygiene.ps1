Add-Case -Name '83: GIT_DIR khong con trong moi truong' -Body {
    Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath 'Env:\GIT_DIR') -Message 'GIT_DIR is absent'
    Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath 'Env:\GIT_WORK_TREE') -Message 'GIT_WORK_TREE is absent'
    Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath 'Env:\GIT_INDEX_FILE') -Message 'GIT_INDEX_FILE is absent'
}

Add-Case -Name '83: git chay duoc trong project test' -Body {
    $project = New-TestProject
    $result = Invoke-TestGit -Project $project -Arguments 'rev-parse --abbrev-ref HEAD'
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'git branch lookup succeeds'
    Assert-Match -Pattern 'feature/T1' -Text $result.Output -Message 'project is on feature/T1'
}
