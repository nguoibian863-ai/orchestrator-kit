# Tạo lại tasks/<id>/changed-files.txt + changes.patch từ trạng thái hiện tại và kiểm tra phạm vi sửa.
# Dùng trước khi review lại sau khi có người sửa tay. (run-worker.ps1 đã tự làm việc này sau mỗi lần gọi worker.)
# Mã thoát: 0 = xong | 6 = có file bị cấm đã bị thay đổi | 1 = lỗi
param([Parameter(Mandatory = $true)][string]$TaskId)
. (Join-Path $PSScriptRoot '_lib.ps1')
Assert-TaskId $TaskId

$changes = Save-TaskChanges $TaskId
if ($changes.Violations.Count -gt 0) {
    Show-Violations $changes.Violations
    Fail 6 'Vi phạm phạm vi. Báo người dùng.'
}
Write-Host "OK: $($changes.Changed.Count) file thay đổi so với commit gốc. Xem tasks/$TaskId/changed-files.txt, changes.patch"
exit 0
