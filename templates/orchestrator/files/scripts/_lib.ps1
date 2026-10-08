# Thư viện dùng chung cho các script orchestrator.
# Chạy được trên Windows PowerShell 5.1 và PowerShell 7+ (Windows).
# Cách dùng trong script khác:  . (Join-Path $PSScriptRoot '_lib.ps1')

$ErrorActionPreference = 'Stop'
$script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$script:ValidStatuses = @('designed', 'planned', 'implementing', 'checked', 'reviewing', 'fixing', 'approved', 'blocked')
$script:DefaultTaskStateJson = '{"tasks":{}}'
$script:DefaultWorkflowJson = '{"feature":null,"current_phase":null,"tasks":[],"blocked_tasks":[],"started_at":null}'
try { [Console]::OutputEncoding = $script:Utf8NoBom } catch { }

# ---------- Tiện ích chung ----------

function Fail([int]$Code, [string]$Message) {
    Write-Host "LỖI: $Message"
    exit $Code
}

function Get-ProjectPath([string]$Relative) {
    return (Join-Path $script:ProjectRoot $Relative)
}

function Assert-TaskId([string]$TaskId) {
    if ($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        Fail 1 "TaskId không hợp lệ: '$TaskId' (chỉ dùng chữ, số và . _ -)"
    }
}

function Test-Prop($Object, [string]$Name) {
    return ($null -ne $Object) -and ($Object.PSObject.Properties.Name -contains $Name)
}

# Lưu ý: PowerShell trải phẳng mảng khi trả về — nơi gọi cần bọc @(...) nếu muốn mảng.
function Get-Prop($Object, [string]$Name, $Default = $null) {
    if (Test-Prop $Object $Name) { return $Object.$Name }
    return $Default
}

function Set-Prop($Object, [string]$Name, $Value) {
    if (Test-Prop $Object $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Get-Lines([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return }
    $Text -split "`r?`n" | Where-Object { $_ -ne '' }
}

# ---------- Đọc/ghi file UTF-8 (không BOM) ----------

function Test-SharingViolation($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    if ($ex.InnerException) { $ex = $ex.InnerException }
    return ($ex.GetType() -eq [System.IO.IOException])
}

function Read-TextUtf8([string]$Path) {
    for ($attempt = 0; ; $attempt++) {
        try { $bytes = [IO.File]::ReadAllBytes($Path); break }
        catch { if ($attempt -ge 50 -or -not (Test-SharingViolation $_)) { throw }; Start-Sleep -Milliseconds 100 }
    }
    $text = $script:Utf8NoBom.GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text
}

function Write-TextUtf8([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom)
}

function Get-Config {
    $path = Get-ProjectPath 'orchestrator.config.json'
    if (-not (Test-Path -LiteralPath $path)) { Fail 1 "Không tìm thấy $path" }
    return (Read-TextUtf8 $path | ConvertFrom-Json)
}

# Đọc - sửa - ghi một file JSON trong lúc giữ khoá độc quyền, để hai tiến trình ghi cùng lúc
# không làm mất dữ liệu của nhau. $Mutate nhận object JSON, sửa tại chỗ, giá trị trả về được chuyển tiếp.
function Update-JsonLocked([string]$Path, [string]$DefaultJson, [scriptblock]$Mutate) {
    $__stream = $null
    for ($__i = 0; $__i -lt 100 -and -not $__stream; $__i++) {
        try { $__stream = [IO.File]::Open($Path, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { if (-not (Test-SharingViolation $_)) { throw }; Start-Sleep -Milliseconds 100 }
    }
    if (-not $__stream) { throw "Không lấy được khoá ghi cho $Path sau 10 giây" }
    try {
        $__buffer = New-Object byte[] ([int]$__stream.Length)
        $__read = 0
        while ($__read -lt $__buffer.Length) {
            $__n = $__stream.Read($__buffer, $__read, $__buffer.Length - $__read)
            if ($__n -le 0) { break }
            $__read += $__n
        }
        $__text = $script:Utf8NoBom.GetString($__buffer, 0, $__read)
        if ($__text.Length -gt 0 -and $__text[0] -eq [char]0xFEFF) { $__text = $__text.Substring(1) }
        if ([string]::IsNullOrWhiteSpace($__text)) { $__text = $DefaultJson }
        $__data = $__text | ConvertFrom-Json
        $__result = & $Mutate $__data
        $__bytes = $script:Utf8NoBom.GetBytes(($__data | ConvertTo-Json -Depth 20))
        $__stream.SetLength(0)
        $__stream.Write($__bytes, 0, $__bytes.Length)
        return $__result
    } finally {
        $__stream.Dispose()
    }
}

# ---------- Chạy tiến trình ngoài có timeout ----------

function ConvertTo-CmdArg([string]$Arg) {
    if ($Arg -eq '') { return '""' }
    if ($Arg -notmatch '[\s"&|<>^()]') { return $Arg }
    return '"' + ($Arg -replace '"', '\"') + '"'
}

function Join-CommandLine([string]$Command, [object[]]$Arguments) {
    $parts = @(ConvertTo-CmdArg $Command)
    foreach ($a in $Arguments) { if ($null -ne $a) { $parts += (ConvertTo-CmdArg ([string]$a)) } }
    return ($parts -join ' ')
}

# "${env:TEN_BIEN}" -> giá trị biến môi trường (để không phải ghi key vào file cấu hình).
function Expand-EnvRef([string]$Value) {
    return [regex]::Replace($Value, '\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}', {
        param($m) [string][Environment]::GetEnvironmentVariable($m.Groups[1].Value)
    })
}

function Stop-ProcessTree([int]$ProcessId) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'taskkill.exe'
    $psi.Arguments = "/T /F /PID $ProcessId"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $killer = [System.Diagnostics.Process]::Start($psi)
    [void]$killer.StandardOutput.ReadToEnd()
    [void]$killer.StandardError.ReadToEnd()
    [void]$killer.WaitForExit(15000)
}

# Chạy một dòng lệnh qua cmd.exe (nhận được npm.cmd, agy, gemini.cmd, chuyển hướng "<" ...).
# Quá $TimeoutSec giây thì giết cả cây tiến trình và trả ExitCode = 124.
function Invoke-Cmd {
    param(
        [string]$CommandLine,
        [int]$TimeoutSec = 600,
        [string]$WorkDir = $script:ProjectRoot,
        $EnvVars = $null
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /s /c "' + $CommandLine + '"'
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:Utf8NoBom
    $psi.StandardErrorEncoding = $script:Utf8NoBom
    if ($null -ne $EnvVars) {
        foreach ($p in $EnvVars.PSObject.Properties) { $psi.EnvironmentVariables[$p.Name] = (Expand-EnvRef ([string]$p.Value)) }
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Close()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $finished = $proc.WaitForExit([int]([Math]::Max(1, $TimeoutSec) * 1000))
    if ($finished) { $proc.WaitForExit() }
    else {
        Stop-ProcessTree $proc.Id
        [void]$proc.WaitForExit(10000)
    }
    $stdout = if ($outTask.Wait(10000)) { $outTask.Result } else { '' }
    $stderr = if ($errTask.Wait(10000)) { $errTask.Result } else { '' }
    $code = if ($finished) { $proc.ExitCode } else { 124 }
    return [pscustomobject]@{ ExitCode = $code; TimedOut = (-not $finished); StdOut = $stdout; StdErr = $stderr }
}

function Invoke-Git([string]$Arguments, [int]$TimeoutSec = 120) {
    return (Invoke-Cmd -CommandLine ('git -c core.quotepath=off ' + $Arguments) -TimeoutSec $TimeoutSec)
}

# ---------- Phạm vi file ----------

# Glob kiểu gitignore đơn giản: '*' không qua '/', '**' qua mọi cấp, 'thu-muc/' = mọi thứ bên trong.
function Test-PathMatch([string]$Path, [object[]]$Patterns) {
    $p = $Path.Replace('\', '/')
    foreach ($raw in $Patterns) {
        if ($null -eq $raw) { continue }
        $g = ([string]$raw).Trim().Replace('\', '/')
        if ($g -eq '' -or $g.StartsWith('#')) { continue }
        if ($g.EndsWith('/')) { $g += '**' }
        $rx = [regex]::Escape($g) -replace '\\\*\\\*', '.*' -replace '\\\*', '[^/]*' -replace '\\\?', '[^/]'
        if ($p -match ('^' + $rx + '(/.*)?$')) { return $true }
    }
    return $false
}

# Các file thay đổi so với commit gốc của task (đã commit + chưa commit + file mới chưa track).
function Get-ChangedFiles([string]$BaseCommit, [object[]]$Ignored) {
    $diff = Invoke-Git "diff --name-status $BaseCommit"
    if ($diff.ExitCode -ne 0) { throw "git diff lỗi: $($diff.StdErr)" }
    foreach ($line in @(Get-Lines $diff.StdOut)) {
        $parts = @($line -split "`t")
        $old = $null
        if ($parts.Count -gt 2) { $old = $parts[1] }
        $item = [pscustomobject]@{ Status = $parts[0].Substring(0, 1); Path = $parts[-1]; OldPath = $old }
        if (-not (Test-PathMatch $item.Path $Ignored)) { $item }
    }
    $untracked = Invoke-Git 'ls-files --others --exclude-standard'
    foreach ($line in @(Get-Lines $untracked.StdOut)) {
        if (-not (Test-PathMatch $line $Ignored)) { [pscustomobject]@{ Status = '?'; Path = $line; OldPath = $null } }
    }
}

# Ghi changed-files.txt + changes.patch của task và kiểm tra phạm vi sửa.
# Trả về object: Changed (danh sách file), Violations (file bị cấm đã bị đụng tới).
function Save-TaskChanges([string]$TaskId) {
    $config = Get-Config
    $scope = Get-Prop $config 'scope'
    $ignored = @(Get-Prop $scope 'ignored' @('tasks/', 'reviews/', 'state/'))
    $task = Get-TaskEntry $TaskId
    $base = [string](Get-Prop $task 'base_commit' '')
    if (-not $base) { Fail 1 "Task $TaskId chưa có base_commit. Chạy scripts/start-task.ps1 -TaskId $TaskId trước." }
    $taskDir = Get-ProjectPath "tasks/$TaskId"

    $changed = @(Get-ChangedFiles $base $ignored)
    $listing = @($changed | ForEach-Object {
        if ($_.Status -eq '?') { "? $($_.Path)  (file mới, chưa track — đọc trực tiếp)" }
        elseif ($_.OldPath) { "$($_.Status) $($_.OldPath) -> $($_.Path)" }
        else { "$($_.Status) $($_.Path)" }
    })
    Write-TextUtf8 (Join-Path $taskDir 'changed-files.txt') (($listing -join "`n") + "`n")

    $excludes = @($ignored | ForEach-Object { '":(exclude)' + ([string]$_).TrimEnd('/') + '"' })
    $patch = Invoke-Git ("diff $base -- . " + ($excludes -join ' '))
    if ($patch.ExitCode -ne 0) { throw "git diff lỗi: $($patch.StdErr)" }
    Write-TextUtf8 (Join-Path $taskDir 'changes.patch') $patch.StdOut

    $guard = @(Get-Prop $scope 'always_protected' @())
    $dnmPath = Join-Path $taskDir 'do-not-modify.txt'
    if (Test-Path -LiteralPath $dnmPath) { $guard += @(Get-Lines (Read-TextUtf8 $dnmPath)) }
    $violations = @($changed | Where-Object { (Test-PathMatch $_.Path $guard) -or ($_.OldPath -and (Test-PathMatch $_.OldPath $guard)) })
    return [pscustomobject]@{ Changed = $changed; Violations = $violations }
}

function Show-Violations($Violations) {
    Write-Host 'Có file nằm trong danh sách cấm sửa đã bị thay đổi:'
    $Violations | ForEach-Object { Write-Host "  $($_.Status) $($_.Path)" }
}

# ---------- State ----------

function Get-TaskEntry([string]$TaskId) {
    $path = Get-ProjectPath 'state/task-state.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $state = Read-TextUtf8 $path | ConvertFrom-Json
    return (Get-Prop (Get-Prop $state 'tasks') $TaskId)
}

function Sync-WorkflowTask([string]$TaskId, [string]$Status) {
    [void](Update-JsonLocked (Get-ProjectPath 'state/workflow-state.json') $script:DefaultWorkflowJson {
        param($wf)
        $taskList = @(@(Get-Prop $wf 'tasks' @()) | Where-Object { $null -ne $_ })
        if ($taskList -notcontains $TaskId) { $taskList += $TaskId }
        Set-Prop $wf 'tasks' $taskList
        $blockedList = @(@(Get-Prop $wf 'blocked_tasks' @()) | Where-Object { $null -ne $_ -and $_ -ne $TaskId })
        if ($Status -eq 'blocked') { $blockedList += $TaskId }
        Set-Prop $wf 'blocked_tasks' $blockedList
    })
}

# Cập nhật một task. $Status rỗng = giữ nguyên status. Vượt max_fix_attempts thì tự chuyển 'blocked'.
function Update-TaskState {
    param(
        [string]$TaskId,
        [string]$Status = '',
        [switch]$IncrementFixAttempts,
        [hashtable]$Fields = @{}
    )
    if ($Status -and $script:ValidStatuses -notcontains $Status) { Fail 1 "Status không hợp lệ: $Status" }
    $maxFix = [int](Get-Prop (Get-Config) 'max_fix_attempts' 3)
    $outcome = Update-JsonLocked (Get-ProjectPath 'state/task-state.json') $script:DefaultTaskStateJson {
        param($state)
        if ($null -eq (Get-Prop $state 'tasks')) { Set-Prop $state 'tasks' ([pscustomobject]@{}) }
        $task = Get-Prop $state.tasks $TaskId
        $isNew = $null -eq $task
        if ($isNew) {
            $task = [pscustomobject]@{}
            $state.tasks | Add-Member -NotePropertyName $TaskId -NotePropertyValue $task
        }
        $defaults = [ordered]@{ title = ''; status = ''; phase_history = @(); fix_attempts = 0; max_fix_attempts = $maxFix
                                branch = ''; base_commit = ''; last_review_summary = ''; updated_at = '' }
        foreach ($k in $defaults.Keys) { if (-not (Test-Prop $task $k)) { Set-Prop $task $k $defaults[$k] } }
        foreach ($k in $Fields.Keys) { Set-Prop $task $k $Fields[$k] }

        $newStatus = $Status
        if (-not $newStatus -and $isNew) { $newStatus = 'planned' }
        $limitHit = $false
        if ($IncrementFixAttempts) {
            $next = [int]$task.fix_attempts + 1
            if ($next -gt [int]$task.max_fix_attempts) { $limitHit = $true; $newStatus = 'blocked' }
            else { $task.fix_attempts = $next }
        }
        if ($newStatus) {
            $task.status = $newStatus
            $history = @(@($task.phase_history) | Where-Object { $null -ne $_ })
            $task.phase_history = $history + $newStatus
        }
        $task.updated_at = (Get-Date).ToString('o')
        [pscustomobject]@{ LimitHit = $limitHit; Status = $task.status; FixAttempts = $task.fix_attempts; Max = $task.max_fix_attempts }
    }
    Sync-WorkflowTask $TaskId $outcome.Status
    return $outcome
}
