function Set-ReviewMode {
    param([string]$Project, [object]$Mode)
    $config = (Read-ProjectFile -Project $Project -Path 'orchestrator.config.json') | ConvertFrom-Json
    $config | Add-Member -MemberType NoteProperty -Name mode -Value $Mode -Force
    Write-ProjectFile -Project $Project -Path 'orchestrator.config.json' -Text (ConvertTo-Json -InputObject $config -Depth 10)
}

function Invoke-ReviewModeProject {
    param([string]$Project)
    $result = Invoke-ProductScript -Project $Project -Script 'scripts/run-review.ps1' -Arguments @('-TaskId', 'T1')
    $summary = ''
    $match = [regex]::Match($result.Output, 'reviews/(T1-round1-[0-9-]+\.md)')
    if ($match.Success) {
        $summary = Read-ProjectFile -Project $Project -Path ('reviews/' + $match.Groups[1].Value)
    }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $result.Output; Summary = $summary }
}

Add-Case -Name '70: mac dinh lean doc review-output.md -> 0' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text ''
    $review = Invoke-ReviewModeProject -Project $project
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'default mode uses single report'
    Assert-Match -Pattern 'lean' -Text $review.Output -Message 'lean mode is printed'
    Assert-Match -Pattern '\| Orchestrator \|' -Text $review.Summary -Message 'single report source row'
}

Add-Case -Name '70: lean co HIGH -> 1' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:HIGH] src/a.ts:1 - issue`n"
    $review = Invoke-ReviewModeProject -Project $project
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'lean HIGH finding blocks'
}

Add-Case -Name '70: lean thieu review-output.md -> 2' -Body {
    $project = New-TestProject
    Set-ReviewMode -Project $project -Mode 'lean'
    Write-ProjectFile -Project $project -Path 'tasks/T1/reviewer-output.md' -Text ''
    Write-ProjectFile -Project $project -Path 'tasks/T1/security-output.md' -Text ''
    Write-ProjectFile -Project $project -Path 'tasks/T1/qa-output.md' -Text ''
    $review = Invoke-ReviewModeProject -Project $project
    Assert-Equal -Expected 2 -Actual $review.ExitCode -Message 'explicit lean requires single report'
    Assert-Match -Pattern 'tasks/T1/review-output\.md' -Text $review.Output -Message 'missing single report path is printed'
}

Add-Case -Name '70: full doc 3 file -> 0' -Body {
    $project = New-TestProject
    Set-ReviewMode -Project $project -Mode 'full'
    Write-ProjectFile -Project $project -Path 'tasks/T1/reviewer-output.md' -Text ''
    Write-ProjectFile -Project $project -Path 'tasks/T1/security-output.md' -Text ''
    Write-ProjectFile -Project $project -Path 'tasks/T1/qa-output.md' -Text ''
    $review = Invoke-ReviewModeProject -Project $project
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'full mode reads three reports'
    Assert-Match -Pattern '\| QA \|' -Text $review.Summary -Message 'full QA source row'
}

Add-Case -Name '70: full thieu qa -> 2' -Body {
    $project = New-TestProject
    Set-ReviewMode -Project $project -Mode 'full'
    Write-ProjectFile -Project $project -Path 'tasks/T1/reviewer-output.md' -Text ''
    Write-ProjectFile -Project $project -Path 'tasks/T1/security-output.md' -Text ''
    $review = Invoke-ReviewModeProject -Project $project
    Assert-Equal -Expected 2 -Actual $review.ExitCode -Message 'full mode requires QA report'
    Assert-Match -Pattern 'tasks/T1/qa-output\.md' -Text $review.Output -Message 'missing QA path is printed'
}

Add-Case -Name '70: mode khong hop le -> 1' -Body {
    $project = New-TestProject
    Set-ReviewMode -Project $project -Mode 'xyz'
    $review = Invoke-ReviewModeProject -Project $project
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'invalid mode is rejected'
    Assert-Match -Pattern "mode.*xyz.*lean, full" -Text $review.Output -Message 'invalid mode error lists accepted values'
}

Add-Case -Name '70: lean conf LOW khong chan -> 0' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:LOW] src/a.ts:1 - issue`n"
    $review = Invoke-ReviewModeProject -Project $project
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'lean low confidence finding does not block'
    Assert-Match -Pattern '\| Orchestrator \| 0 \| 0 \| 0 \| 0 \| 1 \|' -Text $review.Summary -Message 'lean low confidence row is counted'
}
