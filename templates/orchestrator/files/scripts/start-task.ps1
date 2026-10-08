# Bắt đầu (hoặc tiếp tục) một task: tạo/chuyển sang nhánh riêng và ghi commit gốc vào state.
# Worker chỉ được chạy trên nhánh này; mọi thay đổi so với commit gốc được dùng để kiểm tra phạm vi sửa.
# Mã thoát: 0 = xong | 1 = lỗi (chưa có git/commit, còn thay đổi chưa commit, ...)
param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [string]$Title
)
. (Join-Path $PSScriptRoot '_lib.ps1')
Assert-TaskId $TaskId

$config = Get-Config
$gitCfg = Get-Prop $config 'git'
$prefix = [string](Get-Prop $gitCfg 'branch_prefix' 'feature/')
$protected = @(Get-Prop $gitCfg 'protected_branches' @('main', 'master'))
$ignored = @(Get-Prop (Get-Prop $config 'scope') 'ignored' @('tasks/', 'reviews/', 'state/'))

$inside = Invoke-Git 'rev-parse --is-inside-work-tree'
if ($inside.ExitCode -ne 0 -or $inside.StdOut.Trim() -ne 'true') {
    Fail 1 'Thư mục project chưa phải git repo. Hỏi người dùng có muốn git init và commit khung hiện tại không.'
}
$head = Invoke-Git 'rev-parse --verify HEAD'
if ($head.ExitCode -ne 0) {
    Fail 1 'Repo chưa có commit nào. Cần một commit đầu tiên (hỏi người dùng) trước khi tạo nhánh task.'
}

# Chỉ cần cây làm việc sạch khi tạo/chuyển nhánh; đang ở đúng nhánh task (vòng fix) thì không chặn.
function Assert-CleanTree {
    $dirty = @(@(Get-Lines (Invoke-Git 'status --porcelain=v1 -uall').StdOut) |
        Where-Object { -not (Test-PathMatch ($_.Substring(3) -replace '^.* -> ', '') $ignored) })
    if ($dirty.Count -gt 0) {
        Write-Host 'Các thay đổi chưa commit:'
        $dirty | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
        Fail 1 'Còn thay đổi chưa commit ngoài tasks/ reviews/ state/. Commit (khi người dùng đồng ý) hoặc xử lý trước khi tạo/chuyển nhánh task.'
    }
}

$branch = "$prefix$TaskId"
if ($protected -contains $branch) { Fail 1 "Tên nhánh '$branch' trùng nhánh được bảo vệ." }
$current = (Invoke-Git 'rev-parse --abbrev-ref HEAD').StdOut.Trim()
$exists = (Invoke-Git "rev-parse --verify --quiet refs/heads/$branch").ExitCode -eq 0
$existing = Get-TaskEntry $TaskId
$base = [string](Get-Prop $existing 'base_commit' '')

if ($exists) {
    if (-not $base) { Fail 1 "Nhánh $branch đã tồn tại nhưng state không có base_commit cho $TaskId. Hỏi người dùng cách xử lý." }
    if ($current -ne $branch) {
        Assert-CleanTree
        $sw = Invoke-Git "checkout $branch"
        if ($sw.ExitCode -ne 0) { Fail 1 "Không chuyển được sang $branch`: $($sw.StdErr.Trim())" }
    }
    Write-Host "Tiếp tục task $TaskId trên nhánh $branch (base $($base.Substring(0, 7)))."
} else {
    Assert-CleanTree
    $base = $head.StdOut.Trim()
    $sw = Invoke-Git "checkout -b $branch"
    if ($sw.ExitCode -ne 0) { Fail 1 "Không tạo được nhánh $branch`: $($sw.StdErr.Trim())" }
    Write-Host "Tạo nhánh $branch từ $current (base $($base.Substring(0, 7)))."
}

$fields = @{ branch = $branch; base_commit = $base }
if ($PSBoundParameters.ContainsKey('Title')) { $fields.title = $Title }
[void](Update-TaskState -TaskId $TaskId -Fields $fields)
New-Item -ItemType Directory -Force -Path (Get-ProjectPath "tasks/$TaskId") | Out-Null
exit 0
