function Invoke-WaiverReviewProject {
    param([string]$Project)
    $result = Invoke-ProductScript -Project $Project -Script 'scripts/run-review.ps1' -Arguments @('-TaskId', 'T1')
    $summary = ''
    $match = [regex]::Match($result.Output, 'reviews/(T1-round1-[0-9-]+\.md)')
    if ($match.Success) {
        $summary = Read-ProjectFile -Project $Project -Path ('reviews/' + $match.Groups[1].Value)
    }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $result.Output; Summary = $summary }
}

Add-Case -Name '85: waiver khop -> 0' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:HIGH] src/a.ts:42 - so sanh mat khau bang == thay vi hang thoi gian`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/waivers.md' -Text '- [HIGH] so sanh mat khau bang == - Ly do: bao nham, day la code test'
    $review = Invoke-WaiverReviewProject -Project $project
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'matching waiver removes blocking HIGH'
    Assert-Match -Pattern 'Ph\u00e1t hi\u1ec7n \u0111\u01b0\u1ee3c mi\u1ec5n tr\u1eeb' -Text $review.Summary -Message 'waived finding has a dedicated report section'
    Assert-Match -Pattern '\| Orchestrator \| 0 \| 0 \| 0 \| 0 \| 0 \| 1 \|' -Text $review.Summary -Message 'waived count is in the last table column'
}

Add-Case -Name '85: waiver khac muc -> 1' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:HIGH] src/a.ts:42 - so sanh mat khau bang == thay vi hang thoi gian`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/waivers.md' -Text '- [CRITICAL] so sanh mat khau bang == - Ly do: wrong level'
    $review = Invoke-WaiverReviewProject -Project $project
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'waiver with a different level does not match'
}

Add-Case -Name '85: waiver chuoi ngan -> 1' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:HIGH] src/a.ts:42 - so sanh mat khau bang == thay vi hang thoi gian`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/waivers.md' -Text '- [HIGH] abcde - Ly do: short match'
    $review = Invoke-WaiverReviewProject -Project $project
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'short waiver does not match'
    Assert-Match -Pattern '10' -Text $review.Output -Message 'short waiver warning states the minimum length'
}

Add-Case -Name '85: waiver thieu ly do -> 1' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:HIGH] src/a.ts:42 - so sanh mat khau bang == thay vi hang thoi gian`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/waivers.md' -Text '- [HIGH] so sanh mat khau bang =='
    $review = Invoke-WaiverReviewProject -Project $project
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'waiver without reason does not match'
    Assert-Match -Pattern 'thi\u1ebfu l\u00fd do' -Text $review.Output -Message 'missing waiver reason is warned'
}

Add-Case -Name '85: waiver sai khuon -> 1' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:HIGH] src/a.ts:42 - so sanh mat khau bang == thay vi hang thoi gian`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/waivers.md' -Text 'HIGH: abc'
    $review = Invoke-WaiverReviewProject -Project $project
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'malformed waiver does not match'
    Assert-Match -Pattern 'sai khu\u00f4n' -Text $review.Output -Message 'malformed waiver is warned'
}

Add-Case -Name '85: waiver khong khop phat hien nao -> 1' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:HIGH] src/a.ts:42 - so sanh mat khau bang == thay vi hang thoi gian`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/waivers.md' -Text '- [HIGH] unrelated finding substring - Ly do: not applicable'
    $review = Invoke-WaiverReviewProject -Project $project
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'unmatched waiver leaves finding blocking'
    Assert-Match -Pattern 'kh\u00f4ng kh\u1edbp' -Text $review.Output -Message 'unmatched waiver warning is printed'
}

Add-Case -Name '85: mot waiver khop nhieu phat hien -> 0' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:HIGH] src/a.ts:10 - shared finding text in first place`n- [conf:HIGH] src/b.ts:20 - shared finding text in another place`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/waivers.md' -Text '- [HIGH] shared finding text - Ly do: accepted test risk'
    $review = Invoke-WaiverReviewProject -Project $project
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'one waiver can match multiple findings'
    Assert-Match -Pattern '\| Orchestrator \| 0 \| 0 \| 0 \| 0 \| 0 \| 2 \|' -Text $review.Summary -Message 'both findings are counted as waived'
}

Add-Case -Name '85: khong co waivers.md -> 1' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## HIGH`n- [conf:HIGH] src/a.ts:42 - so sanh mat khau bang == thay vi hang thoi gian`n"
    $review = Invoke-WaiverReviewProject -Project $project
    Assert-Equal -Expected 1 -Actual $review.ExitCode -Message 'missing waiver file preserves blocking behavior'
}

Add-Case -Name '85: waiver khong mien tru MEDIUM' -Body {
    $project = New-TestProject
    Write-ProjectFile -Project $project -Path 'tasks/T1/review-output.md' -Text "## MEDIUM`n- [conf:HIGH] src/a.ts:42 - medium note for a test`n"
    Write-ProjectFile -Project $project -Path 'tasks/T1/waivers.md' -Text '- [HIGH] medium note for a test - Ly do: not a HIGH finding'
    $review = Invoke-WaiverReviewProject -Project $project
    Assert-Equal -Expected 0 -Actual $review.ExitCode -Message 'MEDIUM remains nonblocking and is not waived'
    Assert-Match -Pattern '\| Orchestrator \| 0 \| 0 \| 1 \| 0 \| 0 \| 0 \|' -Text $review.Summary -Message 'MEDIUM count stays in its original column'
}
