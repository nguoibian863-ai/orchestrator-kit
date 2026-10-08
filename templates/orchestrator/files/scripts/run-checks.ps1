# Chạy lần lượt các bước kiểm tra trong orchestrator.config.json (mục "checks"), dừng ở bước lỗi đầu tiên.
# Mã thoát: 0 = tất cả PASS | 1 = có bước FAIL hoặc quá giờ | 2 = chưa cấu hình checks
param([string]$TaskId)
. (Join-Path $PSScriptRoot '_lib.ps1')

$config = Get-Config
$checks = @(@(Get-Prop $config 'checks' @()) | Where-Object { $null -ne $_ })
if ($checks.Count -eq 0) {
    Fail 2 "Chưa cấu hình 'checks' trong orchestrator.config.json (xem mẫu 'checks_example'). Hỏi người dùng lệnh lint/build/test của dự án."
}

if ($TaskId) { Assert-TaskId $TaskId; $logRel = "tasks/$TaskId/checks.log" } else { $logRel = 'tasks/checks-latest.log' }
$logPath = Get-ProjectPath $logRel
$log = New-Object System.Text.StringBuilder

foreach ($c in $checks) {
    $name = [string](Get-Prop $c 'name' 'check')
    $command = [string](Get-Prop $c 'command' '')
    if (-not $command) { Fail 2 "Bước '$name' thiếu 'command'." }
    $timeout = [int](Get-Prop $c 'timeout_sec' 600)

    Write-Host "== $name`: $command"
    $r = Invoke-Cmd -CommandLine $command -TimeoutSec $timeout
    [void]$log.AppendLine("===== $name | exit $($r.ExitCode)$(if ($r.TimedOut) { ' | TIMEOUT' }) | $command =====")
    [void]$log.AppendLine($r.StdOut)
    if ($r.StdErr) { [void]$log.AppendLine('--- stderr ---'); [void]$log.AppendLine($r.StdErr) }
    Write-TextUtf8 $logPath $log.ToString()

    if ($r.ExitCode -ne 0) {
        $reason = if ($r.TimedOut) { "quá $timeout giây" } else { "exit $($r.ExitCode)" }
        Write-Host "FAIL: $name ($reason). 40 dòng cuối:"
        @(Get-Lines ($r.StdOut + "`n" + $r.StdErr)) | Select-Object -Last 40 | ForEach-Object { Write-Host "  $_" }
        Write-Host "Log đầy đủ: $logRel"
        exit 1
    }
    Write-Host "PASS: $name"
}
Write-Host "PASS: tất cả $($checks.Count) bước. Log: $logRel"
exit 0
