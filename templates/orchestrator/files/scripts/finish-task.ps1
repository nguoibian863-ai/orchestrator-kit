# Tổng hợp review, approve task đạt và commit thay đổi trên nhánh task.
# Mã thoát: 0 = approved và đã commit | 1 = còn CRITICAL/HIGH hoặc lỗi git | 2 = thiếu báo cáo | 3 = hết lượt fix
param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][string]$Message
)
. (Join-Path $PSScriptRoot '_lib.ps1')
Assert-TaskId $TaskId
if ([string]::IsNullOrWhiteSpace($Message)) { Fail 1 'Message không được để trống.' }

function Invoke-FinishChild {
    param([string]$ScriptName, [string[]]$Arguments)
    $childPath = Join-Path $PSScriptRoot $ScriptName
    $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $childPath) + $Arguments
    $commandLine = Join-CommandLine 'powershell' $childArgs
    return (Invoke-Cmd -CommandLine $commandLine)
}

function Write-CommandOutput($Result) {
    if ($Result.StdOut) { [Console]::Out.Write($Result.StdOut) }
    if ($Result.StdErr) { [Console]::Error.Write($Result.StdErr) }
}

try {
    $stateResult = Invoke-FinishChild -ScriptName 'update-state.ps1' -Arguments @('-TaskId', $TaskId, '-Status', 'reviewing')
} catch {
    Fail 1 "Không chạy được update-state reviewing: $($_.Exception.Message)"
}
if ($stateResult.ExitCode -ne 0) {
    Write-CommandOutput $stateResult
    exit ([int]$stateResult.ExitCode)
}

Write-Host '-> run-review'
try {
    $reviewResult = Invoke-FinishChild -ScriptName 'run-review.ps1' -Arguments @('-TaskId', $TaskId)
} catch {
    Fail 1 "Không chạy được run-review: $($_.Exception.Message)"
}
Write-CommandOutput $reviewResult
if ($reviewResult.ExitCode -ne 0) { exit ([int]$reviewResult.ExitCode) }

try {
    $stateResult = Invoke-FinishChild -ScriptName 'update-state.ps1' -Arguments @('-TaskId', $TaskId, '-Status', 'approved')
} catch {
    Fail 1 "Không chạy được update-state approved: $($_.Exception.Message)"
}
if ($stateResult.ExitCode -ne 0) {
    Write-CommandOutput $stateResult
    exit ([int]$stateResult.ExitCode)
}

$addResult = Invoke-Git 'add -A'
if ($addResult.ExitCode -ne 0) {
    Write-CommandOutput $addResult
    Fail 1 'git add -A thất bại.'
}

$commitMessage = "[worker] ${TaskId}: $Message"
$commitResult = Invoke-Git ("commit -m " + (ConvertTo-CmdArg $commitMessage))
if ($commitResult.ExitCode -ne 0) {
    Write-CommandOutput $commitResult
    Fail 1 'git commit thất bại.'
}

$shaResult = Invoke-Git 'rev-parse --short HEAD'
if ($shaResult.ExitCode -ne 0) { Fail 1 "Commit thành công nhưng không đọc được SHA: $($shaResult.StdErr.Trim())" }
$task = Get-TaskEntry $TaskId
$branch = [string](Get-Prop $task 'branch' '')
if (-not $branch) { $branch = (Invoke-Git 'rev-parse --abbrev-ref HEAD').StdOut.Trim() }
Write-Host "OK: $TaskId approved, đã commit $($shaResult.StdOut.Trim()) trên nhánh $branch."
exit 0
