# Cập nhật state/workflow-state.json: bắt đầu feature mới và/hoặc đổi phase hiện tại.
# Mã thoát: 0 = xong | 3 = đang có feature dang dở khác (cần người dùng xác nhận rồi chạy lại với -Force) | 1 = lỗi
param(
    [string]$Feature,
    [ValidateSet('retrieving', 'designing', 'planning', 'implementing', 'review-loop', 'done', 'blocked')]
    [string]$Phase,
    [switch]$Force
)
. (Join-Path $PSScriptRoot '_lib.ps1')
if (-not $Feature -and -not $Phase) { Fail 1 'Cần ít nhất -Feature hoặc -Phase' }

$now = (Get-Date).ToString('o')
$r = Update-JsonLocked (Get-ProjectPath 'state/workflow-state.json') $script:DefaultWorkflowJson {
    param($wf)
    $current = Get-Prop $wf 'feature'
    $currentPhase = Get-Prop $wf 'current_phase'
    if ($Feature -and $current -and $current -ne $Feature -and $currentPhase -ne 'done' -and -not $Force) {
        return [pscustomobject]@{ Busy = $true; Feature = $current; Phase = $currentPhase }
    }
    if ($Feature -and $current -ne $Feature) {
        Set-Prop $wf 'feature' $Feature
        Set-Prop $wf 'started_at' $now
        Set-Prop $wf 'tasks' @()
        Set-Prop $wf 'blocked_tasks' @()
        if (-not $Phase) { Set-Prop $wf 'current_phase' 'designing' }
    }
    if ($Phase) { Set-Prop $wf 'current_phase' $Phase }
    [pscustomobject]@{ Busy = $false; Feature = $wf.feature; Phase = $wf.current_phase }
}

if ($r.Busy) {
    Write-Host "DỪNG: đang có feature dang dở '$($r.Feature)' (phase $($r.Phase)). Hỏi người dùng: tiếp tục feature cũ, hay bỏ nó (chạy lại với -Force)."
    exit 3
}
Write-Host "Workflow: feature='$($r.Feature)' phase=$($r.Phase)"
exit 0
