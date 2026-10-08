function Assert-ReviewSummary {
    param([string]$Project, [string]$Output)
    $match = [regex]::Match($Output, 'reviews/(T1-round1-[0-9-]+\.md)')
    if (-not $match.Success) { throw 'review summary path was not printed' }
    $summary = Read-ProjectFile -Project $Project -Path ('reviews/' + $match.Groups[1].Value)
    Assert-Match -Pattern '(?s).+' -Text $summary -Message 'review summary exists'
}

Add-Case -Name '20: dinh dang cu, co HIGH -> 1' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/reviewer-output.md' -Text "## HIGH`n- finding`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/security-output.md' -Text ''
    Write-ProjectFile -Project $project -Path 'tasks/T1/qa-output.md' -Text ''
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-review.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message 'HIGH review exit code'
    Assert-ReviewSummary -Project $project -Output $result.Output
}

Add-Case -Name '20: dinh dang cu, chi MEDIUM/LOW -> 0' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/reviewer-output.md' -Text "## MEDIUM`n- finding`n## LOW`n- finding`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/security-output.md' -Text ''
    Write-ProjectFile -Project $project -Path 'tasks/T1/qa-output.md' -Text ''
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-review.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'MEDIUM/LOW review exit code'
    Assert-ReviewSummary -Project $project -Output $result.Output
}

Add-Case -Name '20: muc trong va "- none" -> 0' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/reviewer-output.md' -Text "## CRITICAL`n- none`n## HIGH`n## MEDIUM`n- none`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/security-output.md' -Text ''
    Write-ProjectFile -Project $project -Path 'tasks/T1/qa-output.md' -Text ''
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-review.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'empty review sections exit code'
    Assert-ReviewSummary -Project $project -Output $result.Output
}

Add-Case -Name '20: thieu bao cao qa -> 2' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/reviewer-output.md' -Text ''
    Write-ProjectFile -Project $project -Path 'tasks/T1/security-output.md' -Text ''
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-review.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 2 -Actual $result.ExitCode -Message 'missing report exit code'
}
