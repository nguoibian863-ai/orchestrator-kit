# Gọi worker AI cho một task với prompt trong tasks/<id>/prompt.md; worker tự sửa file trong repo.
# Sau khi chạy: tách kết quả ra output.md, liệt kê file đã đổi, ghi changes.patch, kiểm tra phạm vi sửa.
#
# Chọn worker: -Worker <tên> nếu có, ngược lại theo "worker" trong orchestrator.config.json
# (tên trong "workers", ví dụ agy | codex | gemini-cli). Mỗi worker gồm:
#   command, args   lệnh gọi worker; trong args, {prompt_file} -> tasks/<id>/prompt.md, {task_id} -> <id>
#   stdin_prompt    true = đưa nội dung prompt.md vào stdin (Gemini CLI); false = không (agy đọc file theo đường dẫn)
#   timeout_sec     giới hạn thời gian; quá hạn thì dừng cả cây tiến trình
#   env             biến môi trường thêm, giá trị dạng "${env:TEN_BIEN}" được thay bằng biến của máy
#
# Mã thoát:
#   0   = xong, có file thay đổi, không vi phạm phạm vi
#   1   = lỗi thiết lập (thiếu prompt, chưa start-task, sai nhánh, nhánh được bảo vệ)
#   3   = worker trả mã lỗi            -> xem tasks/<id>/worker.log
#   5   = thiếu marker OUTPUT_START/END -> output.md chứa nội dung gốc
#   6   = worker sửa file bị cấm        -> DỪNG, báo người dùng, không tự hoàn tác
#   7   = worker không đổi file nào     -> đọc output.md để biết lý do
#   124 = quá thời gian, đã dừng cả cây tiến trình
param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [string]$Worker
)
. (Join-Path $PSScriptRoot '_lib.ps1')
Assert-TaskId $TaskId

# Lưu ý: tên biến PowerShell không phân biệt hoa thường — không đặt biến cục bộ trùng tên tham số $Worker.
$config = Get-Config
$selected = Get-Prop $config 'worker'
$workers = Get-Prop $config 'workers'
$workerName = if ($Worker) { $Worker } elseif ($selected -is [string]) { $selected } else { '' }
if ($workerName) {
    $wcfg = Get-Prop $workers $workerName
    if ($null -eq $wcfg) {
        $known = @(if ($workers) { $workers.PSObject.Properties.Name }) -join ', '
        Fail 1 "Không có worker '$workerName' trong mục 'workers' của orchestrator.config.json (đang có: $known)."
    }
} else {
    $wcfg = $selected
    $workerName = 'worker'
}
$command = [string](Get-Prop $wcfg 'command' '')
if (-not $command) { Fail 1 "Worker '$workerName' thiếu 'command' trong orchestrator.config.json." }
$protectedBranches = @(Get-Prop (Get-Prop $config 'git') 'protected_branches' @('main', 'master'))
$timeout = [int](Get-Prop $wcfg 'timeout_sec' 540)

$taskRel = "tasks/$TaskId"
$taskDir = Get-ProjectPath $taskRel
$promptPath = Join-Path $taskDir 'prompt.md'
if (-not (Test-Path -LiteralPath $promptPath)) { Fail 1 "Không tìm thấy $taskRel/prompt.md" }
if ((Read-TextUtf8 $promptPath).Trim() -eq '') { Fail 1 "$taskRel/prompt.md đang rỗng" }

# 1. Chỉ cho worker sửa file trên nhánh riêng của task
$task = Get-TaskEntry $TaskId
$base = [string](Get-Prop $task 'base_commit' '')
$branch = [string](Get-Prop $task 'branch' '')
if (-not $base -or -not $branch) { Fail 1 "Task chưa có nhánh. Chạy scripts/start-task.ps1 -TaskId $TaskId trước." }
$current = (Invoke-Git 'rev-parse --abbrev-ref HEAD').StdOut.Trim()
if ($protectedBranches -contains $current) { Fail 1 "Không chạy worker trên nhánh được bảo vệ '$current'." }
if ($current -ne $branch) { Fail 1 "Đang ở nhánh '$current' nhưng task $TaskId thuộc nhánh '$branch'. Chạy lại start-task." }

# 2. Gọi worker. Prompt dài nên không nhét vào dòng lệnh: hoặc đưa vào stdin bằng chuyển hướng của cmd,
#    hoặc chỉ truyền đường dẫn {prompt_file} để worker tự đọc.
$promptRel = "$taskRel/prompt.md"
$workerArgs = @(@(Get-Prop $wcfg 'args' @()) | Where-Object { $null -ne $_ } |
    ForEach-Object { ([string]$_).Replace('{prompt_file}', $promptRel).Replace('{task_id}', $TaskId) })
$cmdLine = Join-CommandLine $command $workerArgs
if ([bool](Get-Prop $wcfg 'stdin_prompt' $false)) { $cmdLine += ' < "' + $promptPath + '"' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$historyDir = Join-Path $taskDir 'history'
New-Item -ItemType Directory -Force -Path $historyDir | Out-Null
Copy-Item -LiteralPath $promptPath -Destination (Join-Path $historyDir "$stamp-prompt.md")

Write-Host "Gọi worker '$workerName' cho $TaskId trên nhánh $branch (tối đa $timeout giây)..."
$r = Invoke-Cmd -CommandLine $cmdLine -TimeoutSec $timeout -EnvVars (Get-Prop $wcfg 'env')
$log = "# $stamp | worker=$workerName | exit $($r.ExitCode) | timeout=$($r.TimedOut)`n# $cmdLine`n`n## STDOUT`n$($r.StdOut)`n`n## STDERR`n$($r.StdErr)`n"
Write-TextUtf8 (Join-Path $taskDir 'worker.log') $log
Write-TextUtf8 (Join-Path $historyDir "$stamp-worker.log") $log
if ($r.TimedOut) { Fail 124 "Worker chạy quá $timeout giây, đã dừng cả cây tiến trình. Xem $taskRel/worker.log" }
if ($r.ExitCode -ne 0) { Fail 3 "Worker trả mã lỗi $($r.ExitCode). Xem $taskRel/worker.log" }

# 3. Tách phần kết quả giữa hai marker
$outputPath = Join-Path $taskDir 'output.md'
$m = [regex]::Match($r.StdOut, '(?s)## OUTPUT_START(.*)## OUTPUT_END')
$markerOk = $m.Success -and $m.Groups[1].Value.Trim() -ne ''
if ($markerOk) { Write-TextUtf8 $outputPath ($m.Groups[1].Value.Trim() + "`n") }
else { Write-TextUtf8 $outputPath ("> CẢNH BÁO: không tìm thấy marker OUTPUT_START/OUTPUT_END — nội dung gốc:`n`n" + $r.StdOut) }
Copy-Item -LiteralPath $outputPath -Destination (Join-Path $historyDir "$stamp-output.md")

# 4. Liệt kê thay đổi so với commit gốc và kiểm tra phạm vi
$changes = Save-TaskChanges $TaskId
if ($changes.Violations.Count -gt 0) {
    Show-Violations $changes.Violations
    Fail 6 'Worker vi phạm phạm vi. DỪNG, báo người dùng; không tự hoàn tác.'
}
if (-not $markerOk) { Fail 5 "Không tìm thấy marker OUTPUT_START/OUTPUT_END. Đọc $taskRel/output.md, báo người dùng; không tự đoán nội dung." }
if ($changes.Changed.Count -eq 0) { Fail 7 "Worker không thay đổi file nào. Đọc $taskRel/output.md để biết lý do." }

Write-Host "OK: $($changes.Changed.Count) file thay đổi. Xem $taskRel/output.md, changed-files.txt, changes.patch"
exit 0
