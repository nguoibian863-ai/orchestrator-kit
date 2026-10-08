$configPath = Join-Path $PSScriptRoot '..\..\templates\orchestrator\files\orchestrator.config.json'
$productConfig = Get-Content -Raw -Encoding UTF8 (Resolve-Path -LiteralPath $configPath).Path | ConvertFrom-Json

Add-Case -Name '46: agy args co --mode accept-edits' -Body {
    $argsList = @($productConfig.workers.agy.args)
    $modeIndex = [Array]::IndexOf($argsList, '--mode')
    if ($modeIndex -lt 0 -or $modeIndex + 1 -ge $argsList.Count -or $argsList[$modeIndex + 1] -ne 'accept-edits') {
        throw 'agy args must contain adjacent --mode and accept-edits'
    }
}

Add-Case -Name '46: agy args khong co --dangerously-skip-permissions' -Body {
    Assert-NotMatch -Pattern '--dangerously-skip-permissions' -Text (@($productConfig.workers.agy.args) -join ' ') -Message 'agy permissions bypass flag'
}
