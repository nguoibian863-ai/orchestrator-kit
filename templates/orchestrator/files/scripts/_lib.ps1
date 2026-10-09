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

# Các vị trí trong git có thể chạy lệnh hoặc che file khỏi kiểm tra phạm vi. GỌI TRƯỚC khi chạy worker (có gọi git).
# watched_external nhận đường dẫn tuyệt đối, ~/ hoặc ~\ mở thành $HOME; đường dẫn tương đối tính từ gốc project. Bỏ qua phần tử rỗng/null.
# Trả về mảng [pscustomobject]@{ Kind = 'config'|'hooks'|'info'|'hooksPath'|'refs'|'gitignore'|'external'; Path = <đường dẫn tuyệt đối>; IsDir = <bool> }
function Get-GitWatchRoots {
    $commonResult = Invoke-Git 'rev-parse --git-common-dir'
    if ($commonResult.ExitCode -ne 0) { throw "git rev-parse --git-common-dir lỗi: $($commonResult.StdErr)" }
    $common = $commonResult.StdOut.Trim()
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $script:ProjectRoot $common }
    $common = [IO.Path]::GetFullPath($common)

    $gitDirResult = Invoke-Git 'rev-parse --git-dir'
    if ($gitDirResult.ExitCode -ne 0) { throw "git rev-parse --git-dir lỗi: $($gitDirResult.StdErr)" }
    $gitDir = $gitDirResult.StdOut.Trim()
    if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $script:ProjectRoot $gitDir }
    $gitDir = [IO.Path]::GetFullPath($gitDir)

    $branchResult = Invoke-Git 'rev-parse --abbrev-ref HEAD'
    if ($branchResult.ExitCode -ne 0) { throw "git rev-parse --abbrev-ref HEAD lỗi: $($branchResult.StdErr)" }
    $branch = $branchResult.StdOut.Trim()

    $roots = @(
        [pscustomobject]@{ Kind = 'config'; Path = [IO.Path]::GetFullPath((Join-Path $common 'config')); IsDir = $false },
        [pscustomobject]@{ Kind = 'hooks'; Path = [IO.Path]::GetFullPath((Join-Path $common 'hooks')); IsDir = $true },
        [pscustomobject]@{ Kind = 'info'; Path = [IO.Path]::GetFullPath((Join-Path $common 'info')); IsDir = $true },
        [pscustomobject]@{ Kind = 'refs'; Path = [IO.Path]::GetFullPath((Join-Path $common 'HEAD')); IsDir = $false },
        [pscustomobject]@{ Kind = 'refs'; Path = [IO.Path]::GetFullPath((Join-Path $common 'packed-refs')); IsDir = $false },
        [pscustomobject]@{ Kind = 'refs'; Path = [IO.Path]::GetFullPath((Join-Path (Join-Path $gitDir 'refs/heads') $branch)); IsDir = $false }
    )

    $gitignoreResult = Invoke-Git 'ls-files -co --exclude-standard -- "*.gitignore" ".gitignore"'
    if ($gitignoreResult.ExitCode -ne 0) { throw "git ls-files không tìm được .gitignore: $($gitignoreResult.StdErr)" }
    $gitignorePaths = @(Get-Lines $gitignoreResult.StdOut)
    foreach ($relativePath in $gitignorePaths) {
        $gitignorePath = Join-Path $script:ProjectRoot $relativePath
        $roots += [pscustomobject]@{ Kind = 'gitignore'; Path = [IO.Path]::GetFullPath($gitignorePath); IsDir = $false }
    }
    if ($gitignorePaths.Count -gt 0) {
        # Theo dõi cả .gitignore sẽ được tạo sau khi chụp roots, kể cả khi nó nằm trong thư mục con đã có.
        # Snapshot chỉ lấy file tên .gitignore từ root này, không băm các file nguồn khác.
        $roots += [pscustomobject]@{ Kind = 'gitignore'; Path = $script:ProjectRoot; IsDir = $true; NameFilter = '.gitignore' }
    }

    $scope = Get-Prop (Get-Config) 'scope'
    $defaultExternal = @('~/.claude/settings.json', '~/.gemini/antigravity-cli/settings.json', '~/.codex/config.toml')
    foreach ($externalItem in @(Get-Prop $scope 'watched_external' $defaultExternal)) {
        if ($null -eq $externalItem) { continue }
        $externalPath = [string]$externalItem
        if ([string]::IsNullOrWhiteSpace($externalPath)) { continue }
        if ($externalPath -match '^~[\\/]') { $externalPath = Join-Path $HOME $externalPath.Substring(2) }
        elseif (-not [IO.Path]::IsPathRooted($externalPath)) { $externalPath = Join-Path $script:ProjectRoot $externalPath }
        $externalPath = [IO.Path]::GetFullPath($externalPath)
        $alreadyWatched = @($roots | Where-Object { -not $_.IsDir -and $_.Path.Equals($externalPath, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if (-not $alreadyWatched) { $roots += [pscustomobject]@{ Kind = 'external'; Path = $externalPath; IsDir = $false } }
    }

    $hooksResult = Invoke-Git 'config --get core.hooksPath'
    $hooksPath = if ($hooksResult.ExitCode -eq 0) { $hooksResult.StdOut.Trim() } else { '' }
    if ($hooksPath) {
        if ($hooksPath -match '^~[\\/]') { $hooksPath = Join-Path $HOME $hooksPath.Substring(2) }
        $topResult = Invoke-Git 'rev-parse --show-toplevel'
        if ($topResult.ExitCode -ne 0) { throw "git rev-parse --show-toplevel lỗi: $($topResult.StdErr)" }
        $top = [IO.Path]::GetFullPath($topResult.StdOut.Trim())
        if (-not [IO.Path]::IsPathRooted($hooksPath)) { $hooksPath = Join-Path $top $hooksPath }
        $hooksPath = [IO.Path]::GetFullPath($hooksPath)
        $sameAsRoot = @($roots | Where-Object { $_.Path.Equals($hooksPath, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if (-not $sameAsRoot -and -not $hooksPath.Equals($top, [StringComparison]::OrdinalIgnoreCase)) {
            $roots += [pscustomobject]@{ Kind = 'hooksPath'; Path = $hooksPath; IsDir = $true }
        }
    }
    return ,$roots
}

# Chuyển đường dẫn giám sát thành đường dẫn hiển thị tương đối nếu nó nằm trong project.
function ConvertTo-GitWatchDisplayPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($script:ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($prefix.Length).Replace('\', '/')
    }
    return $full
}

# Dấu vân tay các file trong $Roots. Không gọi git, không ném lỗi khi thư mục/file không tồn tại.
# Trả về [hashtable]: khoá = đường dẫn hiển thị, giá trị = [pscustomobject]@{ Hash = <SHA256 hex | 'UNREADABLE'>; Kind = <Kind của root> }
function Get-GitDirSnapshot([object[]]$Roots) {
    $snapshot = @{}
    foreach ($root in $Roots) {
        $files = @()
        if ($root.IsDir) {
            if (Test-Path -LiteralPath $root.Path -PathType Container) {
                if (Test-Prop $root 'NameFilter') {
                    $files = @(Get-ChildItem -LiteralPath $root.Path -Recurse -File -Force -Filter ([string]$root.NameFilter) -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notmatch '[\\/]\.git([\\/]|$)' })
                    $scope = Get-Prop (Get-Config) 'scope'
                    $ignored = @(Get-Prop $scope 'ignored' @('tasks/', 'reviews/', 'state/'))
                    $files = @($files | Where-Object {
                        $displayPath = ConvertTo-GitWatchDisplayPath $_.FullName
                        -not (Test-PathMatch $displayPath $ignored)
                    })
                } else {
                    $files = @(Get-ChildItem -LiteralPath $root.Path -Recurse -File -Force -ErrorAction SilentlyContinue)
                }
            }
        } elseif (Test-Path -LiteralPath $root.Path -PathType Leaf) {
            $files = @(Get-Item -LiteralPath $root.Path -Force)
        }
        foreach ($file in $files) {
            $display = ConvertTo-GitWatchDisplayPath $file.FullName
            $hash = 'UNREADABLE'
            try { $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
            catch { $hash = 'UNREADABLE' }
            $snapshot[$display] = [pscustomobject]@{ Hash = $hash; Kind = [string]$root.Kind }
        }
    }
    return $snapshot
}

# So sánh hai dấu vân tay, trả về thay đổi theo đường dẫn hiển thị.
function Compare-GitDirSnapshot($Before, $After) {
    $changes = New-Object System.Collections.ArrayList
    $paths = @(@($Before.Keys) + @($After.Keys) | Sort-Object -Unique)
    foreach ($path in $paths) {
        $beforeHas = $Before.ContainsKey($path)
        $afterHas = $After.ContainsKey($path)
        if (-not $beforeHas) {
            [void]$changes.Add([pscustomobject]@{ Status = 'A'; Path = [string]$path; Kind = [string]$After[$path].Kind })
        } elseif (-not $afterHas) {
            [void]$changes.Add([pscustomobject]@{ Status = 'D'; Path = [string]$path; Kind = [string]$Before[$path].Kind })
        } elseif ($Before[$path].Hash -ne $After[$path].Hash) {
            [void]$changes.Add([pscustomobject]@{ Status = 'M'; Path = [string]$path; Kind = [string]$After[$path].Kind })
        }
    }
    return @($changes | Sort-Object Path)
}

# In danh sách thay đổi .git theo định dạng cố định.
function Show-GitDirChanges($Changes) {
    Write-Host 'Worker đã thay đổi thư mục git (hook/cấu hình — có thể chạy lệnh khi commit/checkout):'
    $Changes | ForEach-Object { Write-Host "  $($_.Status) $($_.Path) ($($_.Kind))" }
}

# Tìm JSON envelope của worker (agy --output-format json) trong stdout. Không bao giờ ném lỗi.
# Trả về PSCustomObject đầu tiên có thuộc tính 'status' hoặc 'response'; không có -> $null.
function ConvertFrom-WorkerEnvelope([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { $trimmed = $Text.Trim() } catch { return $null }
    $matches = [regex]::Matches($trimmed, '(?m)^[\t ]*\{')
    $count = [Math]::Min(20, $matches.Count)
    $lastBrace = $trimmed.LastIndexOf('}')
    for ($i = 0; $i -lt $count; $i++) {
        $start = $matches[$i].Index + $matches[$i].Length - 1
        $lineEnd = $trimmed.IndexOf("`n", $start)
        if ($lineEnd -lt 0) { $lineEnd = $trimmed.Length }
        $candidates = @($trimmed.Substring($start, $lineEnd - $start))
        if ($lastBrace -ge $start -and $lastBrace -ge $lineEnd) {
            $candidates += $trimmed.Substring($start, $lastBrace - $start + 1)
        }
        foreach ($candidate in $candidates) {
            try {
                $parsed = ConvertFrom-Json -InputObject $candidate -ErrorAction Stop
                if ($parsed -is [System.Management.Automation.PSCustomObject] -and ((Test-Prop $parsed 'status') -or (Test-Prop $parsed 'response'))) {
                    return $parsed
                }
            } catch { }
        }
    }
    return $null
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
