# Cập nhật trạng thái một task trong state/task-state.json (có khoá ghi, UTF-8 không BOM).
# Mã thoát: 0 = xong | 3 = đã hết lượt fix, task chuyển 'blocked' -> DỪNG, báo người dùng | 1 = lỗi
param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)]
    [ValidateSet('designed', 'planned', 'implementing', 'checked', 'reviewing', 'fixing', 'approved', 'blocked')]
    [string]$Status,
    [switch]$IncrementFixAttempts,
    [string]$Title
)
. (Join-Path $PSScriptRoot '_lib.ps1')
Assert-TaskId $TaskId

$fields = @{}
if ($PSBoundParameters.ContainsKey('Title')) { $fields.title = $Title }

$r = Update-TaskState -TaskId $TaskId -Status $Status -IncrementFixAttempts:$IncrementFixAttempts -Fields $fields
if ($r.LimitHit) {
    Write-Host "DỪNG: $TaskId đã dùng hết $($r.Max)/$($r.Max) lượt fix -> status = blocked. Báo người dùng, không gọi worker thêm."
    exit 3
}
Write-Host "State: $TaskId -> $($r.Status) (fix $($r.FixAttempts)/$($r.Max))"
exit 0
