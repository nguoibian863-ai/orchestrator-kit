# Chạy trọn vòng triển khai task: tạo nhánh nếu cần, cập nhật state, gọi worker và checks.
# Mã thoát: 0 = task ở checked | khác 0 = giữ nguyên mã của bước lỗi | 1 = lỗi thiết lập của run-task
param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [string]$Worker,
    [switch]$Fix
)
. (Join-Path $PSScriptRoot '_lib.ps1')
Assert-TaskId $TaskId

function Invoke-TaskStep {
    param(
        [string]$Name,
        [string]$ScriptName,
        [string[]]$Arguments,
        [int]$TimeoutSec = 600,
        [string]$LogHint
    )

    Write-Host "-> $Name"
    try {
        $childPath = Join-Path $PSScriptRoot $ScriptName
        $childArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $childPath) + $Arguments
        $commandLine = Join-CommandLine 'powershell' $childArgs
        $result = Invoke-Cmd -CommandLine $commandLine -TimeoutSec $TimeoutSec
    } catch {
        @(Get-Lines $_.Exception.Message) | Select-Object -Last 15 | ForEach-Object { Write-Host "  $_" }
        Write-Host "DỪNG: $Name trả mã 1."
        if ($LogHint) { Write-Host "Xem $LogHint" }
        exit 1
    }

    if ($result.ExitCode -ne 0) {
        @(Get-Lines ($result.StdOut + "`n" + $result.StdErr)) | Select-Object -Last 15 | ForEach-Object { Write-Host "  $_" }
        Write-Host "DỪNG: $Name trả mã $($result.ExitCode)."
        if ($LogHint) { Write-Host "Xem $LogHint" }
        exit ([int]$result.ExitCode)
    }
}

try {
    $task = Get-TaskEntry $TaskId
} catch {
    Fail 1 "Không đọc được state của task $TaskId`: $($_.Exception.Message)"
}

$taskConfig = $null
try {
    $configPath = Get-ProjectPath 'orchestrator.config.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) { $taskConfig = Get-Config }
} catch {
    $taskConfig = $null
}

$selectedWorker = if ($Worker) { $Worker } else { Get-Prop $taskConfig 'worker' $null }
$workerTimeoutSec = 540 + 60
try {
    $workers = Get-Prop $taskConfig 'workers' $null
    $workerConfig = Get-Prop $workers ([string]$selectedWorker) $null
    $workerTimeoutValue = Get-Prop $workerConfig 'timeout_sec' $null
    $parsedWorkerTimeout = 0
    if ($null -ne $workerTimeoutValue -and [int]::TryParse([string]$workerTimeoutValue, [ref]$parsedWorkerTimeout) -and $parsedWorkerTimeout -le ([int]::MaxValue - 60)) {
        $workerTimeoutSec = $parsedWorkerTimeout + 60
    }
} catch {
    $workerTimeoutSec = 540 + 60
}

$checkTimeoutTotal = [long]0
$checks = Get-Prop $taskConfig 'checks' $null
if ($null -eq $checks) {
    $checkTimeoutTotal = 600
} else {
    $checkItems = @($checks)
    if ($checkItems.Count -eq 0) {
        $checkTimeoutTotal = 600
    } else {
        foreach ($check in $checkItems) {
            $checkTimeoutValue = Get-Prop $check 'timeout_sec' $null
            $parsedCheckTimeout = 0
            if ($null -ne $checkTimeoutValue -and [int]::TryParse([string]$checkTimeoutValue, [ref]$parsedCheckTimeout)) {
                $checkTimeoutTotal += $parsedCheckTimeout
            } else {
                $checkTimeoutTotal += 600
            }
        }
    }
}
if ($checkTimeoutTotal -lt 600) { $checkTimeoutTotal = 600 }
$checksTimeoutSec = if ($checkTimeoutTotal -gt ([int]::MaxValue - 60)) { [int]::MaxValue } else { [int]($checkTimeoutTotal + 60) }
if (-not [string](Get-Prop $task 'branch' '').Trim()) {
    Invoke-TaskStep -Name 'start-task' -ScriptName 'start-task.ps1' -Arguments @('-TaskId', $TaskId)
}

if ($Fix) {
    Invoke-TaskStep -Name 'update-state fixing' -ScriptName 'update-state.ps1' -Arguments @('-TaskId', $TaskId, '-Status', 'fixing', '-IncrementFixAttempts')
} else {
    Invoke-TaskStep -Name 'update-state implementing' -ScriptName 'update-state.ps1' -Arguments @('-TaskId', $TaskId, '-Status', 'implementing')
}

$workerArgs = @('-TaskId', $TaskId)
if ($Worker) { $workerArgs += @('-Worker', $Worker) }
if ($Fix) { $workerArgs += '-Resume' }
Invoke-TaskStep -Name 'run-worker' -ScriptName 'run-worker.ps1' -Arguments $workerArgs -TimeoutSec $workerTimeoutSec -LogHint "tasks/$TaskId/worker.log"
Invoke-TaskStep -Name 'run-checks' -ScriptName 'run-checks.ps1' -Arguments @('-TaskId', $TaskId) -TimeoutSec $checksTimeoutSec -LogHint "tasks/$TaskId/checks.log"
Invoke-TaskStep -Name 'update-state checked' -ScriptName 'update-state.ps1' -Arguments @('-TaskId', $TaskId, '-Status', 'checked')

Write-Host "OK: $TaskId đã ở status checked."
exit 0
