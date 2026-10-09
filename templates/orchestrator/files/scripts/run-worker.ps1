# Gọi worker AI cho một task với prompt trong tasks/<id>/prompt.md; worker tự sửa file trong repo.
# Sau khi chạy: tách kết quả ra output.md, liệt kê file đã đổi, ghi changes.patch, kiểm tra phạm vi sửa.
#
# Chọn worker: -Worker <tên> nếu có, ngược lại theo "worker" trong orchestrator.config.json
# (tên trong "workers", ví dụ agy | codex | gemini-cli). Mỗi worker gồm:
#   command, args   lệnh gọi worker; trong args, {prompt_file} -> tasks/<id>/prompt.md, {task_id} -> <id>
#   stdin_prompt    true = đưa nội dung prompt.md vào stdin (Gemini CLI); false = không (agy đọc file theo đường dẫn)
#   timeout_sec     giới hạn thời gian; quá hạn thì dừng cả cây tiến trình
#   env             biến môi trường thêm, giá trị dạng "${env:TEN_BIEN}" được thay bằng biến của máy
#   output          "text" (mặc định) = tách marker từ stdout
#                   "agy-json" = stdout là JSON envelope của `agy --output-format json`; lấy "response" để tách marker
#
# Mã thoát (nhiều điều kiện cùng xảy ra thì lấy mã đứng trước: 6 > 124 > 3 > 11 > 10 > 8 > 9 > 5 > 7):
#   0   = xong, có file thay đổi, không vi phạm phạm vi
#   1   = lỗi thiết lập (thiếu prompt, chưa start-task, sai nhánh, nhánh được bảo vệ, 'output' không hợp lệ)
#   3   = worker trả mã lỗi            -> xem tasks/<id>/worker.log
#   5   = thiếu marker OUTPUT_START/END -> output.md chứa nội dung gốc
#   6   = worker sửa file bị cấm hoặc sửa .git (config, hooks, info, core.hooksPath)
#         -> DỪNG, báo người dùng, không tự hoàn tác, không chạy lệnh git nào
#   7   = worker không đổi file nào     -> đọc output.md để biết lý do
#   8   = (agy-json) worker bị từ chối hành động và không trả lời -> xem denied_actions trong worker.log
#   9   = (agy-json) worker không trả lời (response rỗng / stdout rỗng) — thường do hết --print-timeout
#   10  = (agy-json) status khác SUCCESS (ERROR, CANCELED, INTERRUPTED...)
#   11  = (agy-json) stdout không chứa JSON envelope -> kiểm tra args có --output-format json
#   124 = quá thời gian, đã dừng cả cây tiến trình
param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [string]$Worker,
    [switch]$Resume
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
$outputMode = ([string](Get-Prop $wcfg 'output' 'text')).Trim().ToLowerInvariant()
if (-not $outputMode) { $outputMode = 'text' }
if (@('text', 'agy-json') -notcontains $outputMode) {
    Fail 1 "Worker '$workerName' có 'output' không hợp lệ: '$outputMode' (chỉ nhận: text, agy-json)."
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
$currentResult = Invoke-Git 'rev-parse --abbrev-ref HEAD'
$current = ([string]$currentResult.StdOut).Trim()
if ($currentResult.ExitCode -ne 0 -or -not $current) {
    $gitErr = (([string]$currentResult.StdErr) -replace '[\r\n]+', ' ').Trim()
    if (-not $gitErr) { $gitErr = '(git không in lỗi)' }
    Fail 1 "Không xác định được nhánh hiện tại: git rev-parse --abbrev-ref HEAD trả mã $($currentResult.ExitCode), thư mục làm việc '$((Get-Location).Path)', lỗi git: $gitErr"
}
if ($protectedBranches -contains $current) { Fail 1 "Không chạy worker trên nhánh được bảo vệ '$current'." }
if ($current -ne $branch) { Fail 1 "Đang ở nhánh '$current' nhưng task $TaskId thuộc nhánh '$branch'. Chạy lại start-task." }

# 2. Chọn args thường hoặc resume, rồi thay các biến trong args.
$task = Get-TaskEntry $TaskId
$resumed = $false
$savedSession = [string](Get-Prop $task 'worker_session' '')
$savedWorker = [string](Get-Prop $task 'worker_name' '')
$resumeArgs = @(@(Get-Prop $wcfg 'resume_args' @()) | Where-Object { $null -ne $_ })
if ($Resume) {
    $resumeReason = ''
    if ([string]::IsNullOrWhiteSpace($savedSession)) {
        $resumeReason = 'chưa có phiên lưu'
    } elseif ($savedWorker -ne $workerName) {
        $resumeReason = "worker khác lần trước ($savedWorker)"
    } elseif ($resumeArgs.Count -eq 0) {
        $resumeReason = 'worker không có resume_args'
    } else {
        $resumed = $true
        Write-Host "Tiếp tục phiên worker $savedSession."
    }
    if (-not $resumed) { Write-Host "Không resume được ($resumeReason), chạy phiên mới." }
}

# Prompt dài nên không nhét vào dòng lệnh: hoặc đưa vào stdin bằng chuyển hướng của cmd,
# hoặc chỉ truyền đường dẫn {prompt_file} để worker tự đọc.
$promptRel = "$taskRel/prompt.md"
$rawArgs = if ($resumed) { $resumeArgs } else { @(@(Get-Prop $wcfg 'args' @()) | Where-Object { $null -ne $_ }) }
$workerArgs = @($rawArgs | ForEach-Object {
    $argument = ([string]$_).Replace('{prompt_file}', $promptRel).Replace('{task_id}', $TaskId)
    if ($resumed) { $argument = $argument.Replace('{session}', $savedSession) }
    $argument
})
$cmdLine = Join-CommandLine $command $workerArgs
if ([bool](Get-Prop $wcfg 'stdin_prompt' $false)) { $cmdLine += ' < "' + $promptPath + '"' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$historyDir = Join-Path $taskDir 'history'
New-Item -ItemType Directory -Force -Path $historyDir | Out-Null
Copy-Item -LiteralPath $promptPath -Destination (Join-Path $historyDir "$stamp-prompt.md")

Write-Host "Gọi worker '$workerName' cho $TaskId trên nhánh $branch (tối đa $timeout giây)..."
$watchRoots = Get-GitWatchRoots
$gitBefore = Get-GitDirSnapshot $watchRoots
$workerWatch = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-Cmd -CommandLine $cmdLine -TimeoutSec $timeout -EnvVars (Get-Prop $wcfg 'env')
$workerWatch.Stop()
$workerSeconds = [Math]::Round($workerWatch.Elapsed.TotalSeconds, 1)
$gitAfter = Get-GitDirSnapshot $watchRoots
$gitChanges = @(Compare-GitDirSnapshot $gitBefore $gitAfter)
$gitUnsafe = @($gitChanges | Where-Object { @('config', 'info', 'refs', 'gitignore') -contains $_.Kind }).Count -gt 0
$gitDiffUntrusted = @($gitChanges | Where-Object { $_.Kind -eq 'refs' -or $_.Kind -eq 'gitignore' }).Count -gt 0

# 3. Phân loại kết quả. Với agy-json, vẫn đọc envelope để lưu log cả khi worker lỗi/quá giờ.
$workerText = [string]$r.StdOut
$envelope = $null
$denied = @()
$response = ''
$outcome = $null
if ($outputMode -eq 'agy-json') {
    $envelope = ConvertFrom-WorkerEnvelope $r.StdOut
    if ($null -ne $envelope) {
        $response = [string](Get-Prop $envelope 'response' '')
        $workerText = $response
        $denied = @(@(Get-Prop $envelope 'denied_actions' @()) | Where-Object { $null -ne $_ })
    }
}

# Lưu session mới sau mỗi lần gọi, kể cả khi worker trả mã lỗi.
$workerSession = ''
if ($outputMode -eq 'agy-json') {
    $workerSession = [string](Get-Prop $envelope 'conversation_id' '')
} else {
    $sessionMatches = [regex]::Matches(($r.StdOut + "`n" + $r.StdErr), '(?im)^\s*session id:\s*([0-9a-fA-F-]{36})\s*$')
    if ($sessionMatches.Count -gt 0) { $workerSession = $sessionMatches[$sessionMatches.Count - 1].Groups[1].Value }
}
$stateAfterWorker = Get-TaskEntry $TaskId
$stateStatus = [string](Get-Prop $stateAfterWorker 'status' '')
Update-TaskState -TaskId $TaskId -Status $stateStatus -Fields @{ worker_name = $workerName; worker_session = $workerSession } | Out-Null

if ($r.TimedOut) {
    $outcome = @{ Code = 124; Message = "Worker chạy quá $timeout giây, đã dừng cả cây tiến trình. Xem $taskRel/worker.log" }
} elseif ($r.ExitCode -ne 0) {
    $outcome = @{ Code = 3; Message = "Worker trả mã lỗi $($r.ExitCode). Xem $taskRel/worker.log" }
} elseif ($outputMode -eq 'agy-json') {
    if ([string]::IsNullOrWhiteSpace($r.StdOut)) {
        $outcome = @{ Code = 9; Message = "Worker không in gì ra stdout. Xem $taskRel/worker.log" }
    } elseif ($null -eq $envelope) {
        $outcome = @{ Code = 11; Message = "Stdout của worker không chứa JSON envelope (output = agy-json). Kiểm tra args của worker có '--output-format json'. Xem $taskRel/worker.log" }
    } else {
        $status = [string](Get-Prop $envelope 'status' '')
        if ($status -ine 'SUCCESS') {
            if (-not $status) { $status = '(không có)' }
            $outcome = @{ Code = 10; Message = "Worker kết thúc với status '$status' (khác SUCCESS). Xem $taskRel/worker.log" }
        } elseif ([string]::IsNullOrWhiteSpace($response) -and $denied.Count -gt 0) {
            $names = @($denied | ForEach-Object {
                $parts = @()
                $actionName = [string](Get-Prop $_ 'action' '')
                $displayName = [string](Get-Prop $_ 'display_name' '')
                if ($actionName) { $parts += $actionName }
                if ($displayName) { $parts += $displayName }
                $parts -join '/'
            }) -join ', '
            $outcome = @{ Code = 8; Message = "Worker bị từ chối $($denied.Count) hành động ($names) và không trả lời gì. Prompt có yêu cầu chạy lệnh shell không? Xem $taskRel/worker.log" }
        } elseif ([string]::IsNullOrWhiteSpace($response)) {
            $outcome = @{ Code = 9; Message = "Worker không trả lời (response rỗng, status SUCCESS, không có hành động bị từ chối) — thường do hết --print-timeout của agy. Xem $taskRel/worker.log" }
        } elseif ($denied.Count -gt 0) {
            $names = @($denied | ForEach-Object {
                $parts = @()
                $actionName = [string](Get-Prop $_ 'action' '')
                $displayName = [string](Get-Prop $_ 'display_name' '')
                if ($actionName) { $parts += $actionName }
                if ($displayName) { $parts += $displayName }
                $parts -join '/'
            }) -join ', '
            Write-Host "CẢNH BÁO: worker bị từ chối $($denied.Count) hành động: $names (vẫn có câu trả lời, xử lý tiếp)."
        }
    }
}

# 4. Ghi worker.log + history; output.md luôn được tạo, kể cả khi worker lỗi/quá giờ.
$logLines = @("# $stamp | worker=$workerName | output=$outputMode | exit $($r.ExitCode) | timeout=$($r.TimedOut)", "# $cmdLine", '')
if ($outputMode -eq 'agy-json') {
    $logLines += '## ENVELOPE'
    if ($null -eq $envelope) {
        $logLines += '(không tìm thấy JSON envelope trong stdout)'
    } else {
        foreach ($field in @('conversation_id', 'status', 'duration_seconds', 'num_turns')) {
            $value = Get-Prop $envelope $field $null
            if ($null -eq $value) { $value = '(không có)' }
            $logLines += "${field}: $value"
        }
        $usage = Get-Prop $envelope 'usage' $null
        if ($null -eq $usage) { $usageText = '(không có)' }
        else { $usageText = ConvertTo-Json -InputObject $usage -Compress -Depth 5 }
        $deniedJson = ConvertTo-Json -InputObject @($denied) -Compress -Depth 5
        $logLines += "usage: $usageText"
        $logLines += "denied_actions: $deniedJson"
        $logLines += "response_chars: $($response.Length)"
    }
    $logLines += ''
}
if ($gitChanges.Count -gt 0) {
    $logLines += '## GIT-DIR'
    $logLines += @($gitChanges | ForEach-Object { "$($_.Status) $($_.Path) ($($_.Kind))" })
    $logLines += ''
}
$logLines += @('## STDOUT', $r.StdOut, '', '## STDERR', $r.StdErr, '')
$log = $logLines -join "`n"
Write-TextUtf8 (Join-Path $taskDir 'worker.log') $log
Write-TextUtf8 (Join-Path $historyDir "$stamp-worker.log") $log

$outputPath = Join-Path $taskDir 'output.md'
$m = [regex]::Match($workerText, '(?s)## OUTPUT_START(.*)## OUTPUT_END')
$markerOk = $m.Success -and $m.Groups[1].Value.Trim() -ne ''
if ($markerOk) { Write-TextUtf8 $outputPath ($m.Groups[1].Value.Trim() + "`n") }
else { Write-TextUtf8 $outputPath ("> CẢNH BÁO: không tìm thấy marker OUTPUT_START/OUTPUT_END — nội dung gốc:`n`n" + $workerText) }
Copy-Item -LiteralPath $outputPath -Destination (Join-Path $historyDir "$stamp-output.md")

# 5. Kiểm tra phạm vi. Không gọi git sau thay đổi config/info/refs/gitignore vì cấu hình có thể chạy lệnh hoặc kết quả git không còn tin được.
$changes = [pscustomobject]@{ Changed = @(); Violations = @() }
$changesListed = $false
$scopeError = $null
if ($gitUnsafe) {
    if ($gitDiffUntrusted) {
        Write-TextUtf8 (Join-Path $taskDir 'changed-files.txt') "(Không liệt kê: worker đã sửa refs hoặc .gitignore — kết quả git diff/ls-files không còn tin được. Xem $taskRel/worker.log, mục GIT-DIR.)`n"
    } else {
        Write-TextUtf8 (Join-Path $taskDir 'changed-files.txt') "(Không liệt kê: worker đã sửa .git/config hoặc .git/info — git diff có thể chạy lệnh do cấu hình chỉ định. Xem $taskRel/worker.log, mục GIT-DIR.)`n"
    }
} else {
    try {
        $changes = Save-TaskChanges $TaskId
        $changesListed = $true
    } catch {
        $scopeError = $_
    }
}

if ($gitChanges.Count -gt 0) { Show-GitDirChanges $gitChanges }
if ($changes.Violations.Count -gt 0) { Show-Violations $changes.Violations }

# Chọn mã cuối trước khi Fail để mọi lần gọi worker đều có đúng một dòng metrics.
$finalExitCode = 0
if ($scopeError -and $gitChanges.Count -eq 0) { $finalExitCode = 1 }
elseif ($gitChanges.Count -gt 0 -or $changes.Violations.Count -gt 0) { $finalExitCode = 6 }
elseif ($outcome) { $finalExitCode = [int]$outcome.Code }
elseif (-not $markerOk) { $finalExitCode = 5 }
elseif ($changesListed -and $changes.Changed.Count -eq 0) { $finalExitCode = 7 }

$usage = Get-Prop $envelope 'usage' $null
function ConvertTo-MetricNumber($Value) {
    if ($null -eq $Value) { return $null }
    $number = 0.0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $number }
    return $null
}
$metrics = [ordered]@{
    ts = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    task = $TaskId
    worker = $workerName
    resumed = [bool]$resumed
    exit = [int]$finalExitCode
    timed_out = [bool]$r.TimedOut
    seconds = [double]$workerSeconds
    status = [string](Get-Prop $envelope 'status' '')
    total_tokens = ConvertTo-MetricNumber (Get-Prop $usage 'total_tokens' $null)
    input_tokens = ConvertTo-MetricNumber (Get-Prop $usage 'input_tokens' $null)
    output_tokens = ConvertTo-MetricNumber (Get-Prop $usage 'output_tokens' $null)
    cached_tokens = ConvertTo-MetricNumber (Get-Prop $usage 'cache_read_tokens' $null)
    changed_files = if ($changesListed) { [int]$changes.Changed.Count } else { $null }
    session = $workerSession
}
$metricsLine = ConvertTo-Json -InputObject $metrics -Compress -Depth 5
$metricsLine = ($metricsLine -split "`r?`n") -join ''
$metricsPath = Join-Path $taskDir 'metrics.jsonl'
[IO.File]::AppendAllText($metricsPath, $metricsLine + "`n", (New-Object System.Text.UTF8Encoding $false))

if ($scopeError -and $gitChanges.Count -eq 0) { throw $scopeError }
if ($gitChanges.Count -gt 0) {
    $gitFailureMessage = 'Worker sửa thư mục .git (hook/cấu hình git). DỪNG, báo người dùng; không tự hoàn tác, KHÔNG chạy lệnh git nào (commit, checkout...) trước khi người dùng kiểm tra.'
    if ($gitDiffUntrusted) { $gitFailureMessage += ' Với thay đổi refs/gitignore, kết quả git diff không còn tin được.' }
    Fail 6 $gitFailureMessage
}
if ($changes.Violations.Count -gt 0) {
    Fail 6 'Worker vi phạm phạm vi. DỪNG, báo người dùng; không tự hoàn tác.'
}
if ($outcome) { Fail ([int]$outcome.Code) ([string]$outcome.Message) }
if (-not $markerOk) { Fail 5 "Không tìm thấy marker OUTPUT_START/END. Đọc $taskRel/output.md, báo người dùng; không tự đoán nội dung." }
if ($changes.Changed.Count -eq 0) { Fail 7 "Worker không thay đổi file nào. Đọc $taskRel/output.md để biết lý do." }

Write-Host "OK: $($changes.Changed.Count) file thay đổi. Xem $taskRel/output.md, changed-files.txt, changes.patch"
exit 0
