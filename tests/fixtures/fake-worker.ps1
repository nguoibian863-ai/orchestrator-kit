param([Parameter(Mandatory = $true)][string]$Scenario, [string]$Echo)

$ErrorActionPreference = 'Stop'
$encoding = New-Object System.Text.UTF8Encoding $false
try {
    if (-not (Test-Path -LiteralPath $Scenario -PathType Leaf)) { throw 'scenario file not found' }
    $data = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Scenario).Path, $encoding) | ConvertFrom-Json
} catch {
    [Console]::Error.WriteLine("Cannot read scenario: $Scenario")
    [Console]::Error.Flush()
    exit 99
}

try {
    foreach ($action in @($data.actions)) {
        $op = [string]$action.op
        switch ($op) {
            'write' {
                $path = Join-Path (Get-Location).Path ([string]$action.path)
                $parent = Split-Path -Parent $path
                if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
                [IO.File]::WriteAllText($path, [string]$action.text, $encoding)
            }
            'append' {
                $path = Join-Path (Get-Location).Path ([string]$action.path)
                $parent = Split-Path -Parent $path
                if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
                [IO.File]::AppendAllText($path, [string]$action.text, $encoding)
            }
            'delete' {
                $path = Join-Path (Get-Location).Path ([string]$action.path)
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -Recurse }
            }
            'stdout' {
                [Console]::Out.Write([string]$action.text)
                [Console]::Out.Flush()
            }
            'stderr' {
                [Console]::Error.Write([string]$action.text)
                [Console]::Error.Flush()
            }
            'sleep' {
                Start-Sleep -Seconds ([int]$action.seconds)
            }
            default { throw "unknown action: $op" }
        }
    }
    if ($Echo) { [Console]::Out.WriteLine("echo:$Echo"); [Console]::Out.Flush() }
    $code = 0
    if ($null -ne $data.PSObject.Properties['exit_code']) { $code = [int]$data.exit_code }
    exit $code
} catch {
    [Console]::Error.WriteLine("Fake worker error: $($_.Exception.Message)")
    [Console]::Error.Flush()
    exit 99
}
