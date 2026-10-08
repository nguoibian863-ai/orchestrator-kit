# Cài bộ orchestrator kit từ repo này vào ~/.claude. Repo là nguồn sự thật: sửa ở đây rồi chạy lại script.
#   commands/*.md          -> ~/.claude/commands/
#   templates/orchestrator -> ~/.claude/templates/orchestrator/
# Ghi đè file khác nội dung, bỏ qua file giống hệt. File chỉ còn ở bản cài (đã xoá/đổi tên trong repo) chỉ được liệt kê;
# thêm -Prune để xoá chúng — scaffold.ps1 chép mọi thứ trong files/ nên file cũ sót lại sẽ lọt vào project mới.
# -Prune chỉ áp dụng cho templates/orchestrator (thư mục riêng của kit), không đụng tới các lệnh khác trong commands/.
#
# Mã thoát: 0 = xong
#           1 = lỗi
param(
    [string]$ClaudeHome = (Join-Path $HOME '.claude'),
    [switch]$DryRun,
    [switch]$Prune
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
try { [Console]::OutputEncoding = $utf8 } catch { }

$repo = $PSScriptRoot
$parts = @(
    @{ Label = 'commands'; Src = Join-Path $repo 'commands'; Dest = Join-Path $ClaudeHome 'commands'; Owned = $false },
    @{ Label = 'templates\orchestrator'; Src = Join-Path $repo 'templates\orchestrator'; Dest = Join-Path $ClaudeHome 'templates\orchestrator'; Owned = $true }
)

try {
    $absent = @($parts | Where-Object { -not (Test-Path -LiteralPath $_.Src) } | ForEach-Object { $_.Label })
    if ($absent.Count -gt 0) { Write-Host "LỖI: repo $repo thiếu: $($absent -join ', ')"; exit 1 }

    $mode = if ($DryRun) { ' (chạy thử, không ghi gì)' } else { '' }
    Write-Host "Cài từ $repo vào $ClaudeHome$mode"
    $added = 0; $updated = 0; $same = 0
    $stale = New-Object System.Collections.Generic.List[string]

    foreach ($p in $parts) {
        $srcRoot = (Resolve-Path -LiteralPath $p.Src).Path
        $known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($f in Get-ChildItem -LiteralPath $srcRoot -Recurse -File -Force) {
            $rel = $f.FullName.Substring($srcRoot.Length).TrimStart('\')
            [void]$known.Add($rel)
            $dest = Join-Path $p.Dest $rel
            if (Test-Path -LiteralPath $dest) {
                if ((Get-FileHash -LiteralPath $dest).Hash -eq (Get-FileHash -LiteralPath $f.FullName).Hash) { $same++; continue }
                $action = 'cập nhật'; $updated++
            } else {
                $action = 'thêm    '; $added++
            }
            Write-Host "  $action  $($p.Label)\$rel"
            if ($DryRun) { continue }
            $dir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        }

        if (-not $p.Owned -or -not (Test-Path -LiteralPath $p.Dest)) { continue }
        $destRoot = (Resolve-Path -LiteralPath $p.Dest).Path
        foreach ($f in Get-ChildItem -LiteralPath $destRoot -Recurse -File -Force) {
            $rel = $f.FullName.Substring($destRoot.Length).TrimStart('\')
            if ($known.Contains($rel)) { continue }
            $stale.Add("$($p.Label)\$rel")
            if ($Prune -and -not $DryRun) { Remove-Item -LiteralPath $f.FullName -Force }
        }
    }

    Write-Host "Xong: $added thêm, $updated cập nhật, $same giữ nguyên."
    if ($stale.Count -gt 0) {
        $verb = if ($Prune -and -not $DryRun) { 'Đã xoá' } elseif ($Prune) { 'Sẽ xoá' } else { 'CẢNH BÁO: còn' }
        Write-Host "$verb $($stale.Count) file ở bản cài không có trong repo:"
        $stale | ForEach-Object { Write-Host "  $_" }
        if (-not $Prune) { Write-Host 'Nếu đó là file cũ, chạy lại với -Prune để xoá. Nếu là file bạn sửa trực tiếp trong ~/.claude, chép ngược vào repo trước.' }
    }
    exit 0
} catch {
    Write-Host "LỖI: $($_.Exception.Message)"
    exit 1
}
