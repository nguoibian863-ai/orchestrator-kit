function New-AgyEnvelope {
    param(
        [string]$Response = "## OUTPUT_START`nagy-ok`n## OUTPUT_END`n",
        [string]$Status = 'SUCCESS',
        [object[]]$Denied = $null,
        [switch]$IncludeDenied
    )
    $envelope = [ordered]@{
        conversation_id = 'smoke-conv'
        status = $Status
        response = $Response
        duration_seconds = 3.3
        num_turns = 1
        usage = @{ total = 7 }
    }
    if ($IncludeDenied) { $envelope.denied_actions = @($Denied) }
    return ConvertTo-Json -InputObject $envelope -Compress -Depth 8
}

Add-Case -Name '40: envelope SUCCESS co marker -> 0' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = (New-AgyEnvelope) }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'agy success code'
    $log = Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log'
    Assert-Match -Pattern 'conversation_id: smoke-conv' -Text $log -Message 'conversation id in log'
    Assert-Match -Pattern 'status: SUCCESS' -Text $log -Message 'status in log'
}

Add-Case -Name '40: dong rac truoc JSON -> 0' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = "diagnostic line`n$(New-AgyEnvelope)" }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'envelope after noise code'
}

Add-Case -Name '40: denied + response rong -> 8' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    $envelope = New-AgyEnvelope -Response '' -Denied @(@{ action = 'command'; display_name = 'RunCommand' }) -IncludeDenied
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'stdout'; text = $envelope }); exit_code = 0 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 8 -Actual $result.ExitCode -Message 'denied without response code'
    Assert-Match -Pattern 'RunCommand' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'denied action in log'
}

Add-Case -Name '40: denied + co response va marker -> 0' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    $response = "## OUTPUT_START`nanswer`n## OUTPUT_END`n"
    $envelope = New-AgyEnvelope -Response $response -Denied @(@{ action = 'command'; display_name = 'RunCommand' }) -IncludeDenied
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = $envelope }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'denied with response code'
    Assert-Match -Pattern 'RunCommand' -Text $result.Output -Message 'denied warning in output'
}

Add-Case -Name '40: response rong, khong denied -> 9' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'stdout'; text = (New-AgyEnvelope -Response '') }); exit_code = 0 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 9 -Actual $result.ExitCode -Message 'empty response without denied code'
    Assert-Match -Pattern 'denied_actions: \[\]' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'missing denied_actions logs empty array'
}

Add-Case -Name '40: stdout rong -> 9' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'stdout'; text = "  `n`t" }); exit_code = 0 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 9 -Actual $result.ExitCode -Message 'empty stdout code'
}

Add-Case -Name '40: status ERROR -> 10' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'stdout'; text = (New-AgyEnvelope -Status 'ERROR') }); exit_code = 0 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 10 -Actual $result.ExitCode -Message 'ERROR status code'
}

Add-Case -Name '40: status CANCELED -> 10' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'stdout'; text = (New-AgyEnvelope -Status 'CANCELED') }); exit_code = 0 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 10 -Actual $result.ExitCode -Message 'CANCELED status code'
}

Add-Case -Name '40: khong phai JSON -> 11' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'stdout'; text = 'plain text response' }); exit_code = 0 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 11 -Actual $result.ExitCode -Message 'not JSON code'
}

Add-Case -Name '40: SUCCESS khong marker -> 5' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = (New-AgyEnvelope -Response 'plain answer') }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 5 -Actual $result.ExitCode -Message 'missing marker in envelope response code'
    Assert-Match -Pattern 'plain answer' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/output.md') -Message 'response saved to output'
}

Add-Case -Name '40: SUCCESS co marker, khong doi file -> 7' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'stdout'; text = (New-AgyEnvelope) }); exit_code = 0 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 7 -Actual $result.ExitCode -Message 'no file changes code'
}

Add-Case -Name '40: envelope + exit 2 -> 3' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'agy-json' }
    Set-Scenario -Project $project -Scenario @{ actions = @(@{ op = 'stdout'; text = (New-AgyEnvelope) }); exit_code = 2 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 3 -Actual $result.ExitCode -Message 'worker exit code priority'
    Assert-Match -Pattern 'conversation_id: smoke-conv' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/worker.log') -Message 'envelope logged on worker error'
    Assert-Match -Pattern 'agy-ok' -Text (Read-ProjectFile -Project $project -Path 'tasks/T1/output.md') -Message 'output saved on worker error'
}

Add-Case -Name '40: output khong hop le (xml) -> 1' -Body {
    $project = New-TestProject -WorkerOverrides @{ output = 'xml' }
    Set-Scenario -Project $project -Scenario @{ actions = @(); exit_code = 0 }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message 'invalid output mode code'
    Assert-Match -Pattern 'output.*agy-json' -Text $result.Output -Message 'invalid output mode message'
}

Add-Case -Name '40: worker text in JSON van theo marker -> 0' -Body {
    $project = New-TestProject
    $text = "{`n  `"response`": `"## OUTPUT_START`ntext-json`n## OUTPUT_END`"`n}"
    Set-Scenario -Project $project -Scenario @{
        actions = @(
            @{ op = 'write'; path = 'src/a.txt'; text = 'changed' },
            @{ op = 'stdout'; text = $text }
        )
        exit_code = 0
    }
    $result = Invoke-ProductScript -Project $project -Script 'scripts/run-worker.ps1' -Arguments @('-TaskId', 'T1')
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message 'text mode marker behavior'
}
