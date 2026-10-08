function Invoke-ReviewFixture {
    param(
        [string]$Reviewer = '',
        [string]$Security = '',
        [string]$Qa = ''
    )
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/reviewer-output.md' -Text $Reviewer
    Write-ProjectFile -Project $project -Path 'tasks/T1/security-output.md' -Text $Security
    Write-ProjectFile -Project $project -Path 'tasks/T1/qa-output.md' -Text $Qa
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-review.ps1' -Arguments @('-TaskId', 'T1')
    $match = [regex]::Match($result.Output, 'reviews/(T1-round1-[0-9-]+\.md)')
    if (-not $match.Success) { throw 'review summary path was not printed' }
    $summary = Read-ProjectFile -Project $project -Path ('reviews/' + $match.Groups[1].Value)
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $result.Output; Summary = $summary }
}

Add-Case -Name '50: HIGH conf LOW -> 0' -Body {
    $review = Invoke-ReviewFixture -Reviewer "## HIGH`n- [conf:LOW] src/a.ts:10 - issue`n"
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'HIGH conf LOW exit code'
    Assert-Match -Pattern '\[Reviewer\]\[HIGH\] \[conf:LOW\]' -Text $review.Summary -Message 'low confidence finding is listed separately'
    Assert-Match -Pattern 'conf:LOW' -Text $review.Output -Message 'console calls out low confidence findings'
    Assert-Match -Pattern '\| Reviewer \| 0 \| 0 \| 0 \| 0 \| 1 \|' -Text $review.Summary -Message 'reviewer low confidence table row'
}

Add-Case -Name '50: CRITICAL conf MEDIUM -> 1' -Body {
    $review = Invoke-ReviewFixture -Reviewer "## CRITICAL`n- [conf:MEDIUM] src/a.ts:1 - issue`n"
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'CRITICAL conf MEDIUM is blocking'
}

Add-Case -Name '50: HIGH conf HIGH -> 1' -Body {
    $review = Invoke-ReviewFixture -Reviewer "## HIGH`n- [conf:HIGH] src/a.ts:1 - issue`n"
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'HIGH conf HIGH is blocking'
}

Add-Case -Name '50: HIGH missing label -> 1' -Body {
    $review = Invoke-ReviewFixture -Reviewer "## HIGH`n- src/a.ts:1 - issue`n- [conf:INVALID] src/b.ts:2 - issue`n"
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'missing confidence label is blocking'
    Assert-Match -Pattern '\[conf:\.\.\.\]' -Text $review.Output -Message 'console notes missing confidence label'
    Assert-Match -Pattern '\| Reviewer \| 0 \| 2 \| 0 \| 0 \| 0 \|' -Text $review.Summary -Message 'invalid confidence value is treated as missing'
}

Add-Case -Name '50: label at end -> 1' -Body {
    $review = Invoke-ReviewFixture -Reviewer "## HIGH`n- src/a.ts:1 - issue [conf:LOW]`n"
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'confidence label at line end is missing'
}

Add-Case -Name '50: bold label -> 0' -Body {
    $review = Invoke-ReviewFixture -Reviewer "## HIGH`n- **[conf:LOW]** src/a.ts:1 - issue`n"
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'bold confidence label is recognized'
}

Add-Case -Name '50: lowercase confidence label -> 0' -Body {
    $review = Invoke-ReviewFixture -Reviewer "## HIGH`n- [confidence: low] src/a.ts:1 - issue`n"
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'confidence label matching is case insensitive'
}

Add-Case -Name '50: MEDIUM conf LOW -> 0' -Body {
    $review = Invoke-ReviewFixture -Reviewer "## MEDIUM`n- [conf:LOW] src/a.ts:1 - issue`n"
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'MEDIUM finding does not block'
    Assert-Match -Pattern '\| Reviewer \| 0 \| 0 \| 1 \| 0 \| 0 \|' -Text $review.Summary -Message 'MEDIUM low confidence stays in MEDIUM column'
}

Add-Case -Name '50: mixed sources -> 1' -Body {
    $review = Invoke-ReviewFixture -Reviewer "## HIGH`n- [conf:LOW] src/a.ts:1 - issue`n" -Security "## HIGH`n- [conf:HIGH] src/b.ts:2 - issue`n"
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'blocking finding from security source'
    Assert-Match -Pattern '\| Reviewer \| 0 \| 0 \| 0 \| 0 \| 1 \|' -Text $review.Summary -Message 'reviewer source row'
    Assert-Match -Pattern '\| Security Auditor \| 0 \| 1 \| 0 \| 0 \| 0 \|' -Text $review.Summary -Message 'security source row'
}
