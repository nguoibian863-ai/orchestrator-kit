$configPath = Join-Path $PSScriptRoot '..\..\templates\orchestrator\files\orchestrator.config.json'
$productConfig = Get-Content -Raw -Encoding UTF8 (Resolve-Path -LiteralPath $configPath).Path | ConvertFrom-Json

Add-Case -Name '45: agy output = agy-json' -Body {
    Assert-Equal -Expected 'agy-json' -Actual $productConfig.workers.agy.output -Message 'agy output mode'
}

Add-Case -Name '45: agy args co --output-format json' -Body {
    $argsList = @($productConfig.workers.agy.args)
    $formatIndex = [Array]::IndexOf($argsList, '--output-format')
    if ($formatIndex -lt 0 -or $formatIndex + 1 -ge $argsList.Count -or $argsList[$formatIndex + 1] -ne 'json') {
        throw 'agy args must contain adjacent --output-format and json'
    }
}

Add-Case -Name '45: agy --effort thuoc low|medium|high|xhigh|max' -Body {
    $argsList = @($productConfig.workers.agy.args)
    $effortIndex = [Array]::IndexOf($argsList, '--effort')
    if ($effortIndex -lt 0 -or $effortIndex + 1 -ge $argsList.Count) { throw 'agy args are missing --effort' }
    if (@('low', 'medium', 'high', 'xhigh', 'max') -notcontains [string]$argsList[$effortIndex + 1]) {
        throw 'agy effort value is not supported'
    }
}

Add-Case -Name '45: agy khong co --dangerously-skip-permissions' -Body {
    Assert-NotMatch -Pattern '--dangerously-skip-permissions' -Text (@($productConfig.workers.agy.args) -join ' ') -Message 'agy permissions bypass flag'
}

Add-Case -Name '45: codex, gemini-cli output = text' -Body {
    Assert-Equal -Expected 'text' -Actual $productConfig.workers.codex.output -Message 'codex output mode'
    Assert-Equal -Expected 'text' -Actual $productConfig.workers.'gemini-cli'.output -Message 'gemini output mode'
}
