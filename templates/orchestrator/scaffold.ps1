# Tạo khung "Claude điều phối worker AI (mặc định Antigravity CLI)" (v3) trong một thư mục project, bằng cách chép file mẫu
# trong thư mục files/ cạnh script này. Không bao giờ ghi đè file đã có.
#
# Mã thoát: 0 = xong
#           2 = thư mục không trống -> hỏi người dùng, chỉ chạy lại với -AllowNonEmpty khi họ đồng ý
#           3 = thư mục đã có khung orchestrator -> dừng
#           1 = lỗi khác
param(
    [string]$Target = (Get-Location).Path,
    [string]$Tech,
    [string]$Db,
    [switch]$AllowNonEmpty
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
try { [Console]::OutputEncoding = $utf8 } catch { }

$templateRoot = $PSScriptRoot
$filesRoot = Join-Path $templateRoot 'files'
$required = @('files/orchestrator.config.json', 'files/scripts/_lib.ps1', 'files/.claude/commands/feature.md', 'orchestrator-guide.md')
$absent = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $templateRoot $_)) })
if ($absent.Count -gt 0) { Write-Host "LỖI: bộ mẫu trong $templateRoot thiếu: $($absent -join ', ')"; exit 1 }
if (-not (Test-Path -LiteralPath $Target)) { New-Item -ItemType Directory -Force -Path $Target | Out-Null }
$Target = (Resolve-Path -LiteralPath $Target).Path

# 1. Đã có khung (v3 hoặc v2)?
$markers = @('orchestrator.config.json', '.claude/commands/orchestrator.md', 'state/task-state.json')
$found = @($markers | Where-Object { Test-Path -LiteralPath (Join-Path $Target $_) })
$isV2 = @('agents', 'commands', 'state' | Where-Object { Test-Path -LiteralPath (Join-Path $Target $_) }).Count -eq 3
if ($found.Count -gt 0 -or $isV2) {
    $what = if ($isV2) { 'khung v2 (agents/ + commands/ + state/ ở gốc)' } else { $found -join ', ' }
    Write-Host "DỪNG: thư mục đã có khung orchestrator: $what"
    exit 3
}

# 2. Thư mục không trống?
$allowed = @('.git', '.gitignore', '.gitattributes', 'README.md', 'LICENSE', '.claude', '.vscode', '.idea')
$extra = @(Get-ChildItem -LiteralPath $Target -Force | Where-Object { $allowed -notcontains $_.Name } | ForEach-Object { $_.Name })
if ($extra.Count -gt 0 -and -not $AllowNonEmpty) {
    Write-Host "DỪNG: thư mục $Target không trống ($($extra.Count) mục):"
    $extra | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Khung này dành cho project mới. Nếu người dùng xác nhận vẫn muốn thêm vào đây, chạy lại với -AllowNonEmpty (không ghi đè file nào).'
    exit 2
}

# 3. Chép file mẫu, bỏ qua file đã có
$created = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]

function Save-IfMissing([string]$Relative, [scriptblock]$Writer) {
    $dest = Join-Path $Target $Relative
    if (Test-Path -LiteralPath $dest) { $skipped.Add($Relative); return }
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    & $Writer $dest
    $created.Add($Relative)
}

function Copy-IfMissing([string]$Source, [string]$Relative) {
    Save-IfMissing $Relative { param($dest) Copy-Item -LiteralPath $Source -Destination $dest }
}

function New-TextIfMissing([string]$Relative, [string]$Text) {
    Save-IfMissing $Relative { param($dest) [IO.File]::WriteAllText($dest, $Text, $utf8) }
}

Get-ChildItem -LiteralPath $filesRoot -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
    Copy-IfMissing $_.FullName ($_.FullName.Substring($filesRoot.Length).TrimStart('\', '/'))
}
Copy-IfMissing (Join-Path $templateRoot 'orchestrator-guide.md') 'orchestrator-guide.md'
New-TextIfMissing '.claude/settings.json' "{}`n"

# State và nhật ký task là dữ liệu lúc chạy: không để git theo dõi, nếu không mỗi lần đổi nhánh sẽ kéo state theo.
$ignoreLines = @('state/', 'tasks/', 'reviews/')
$gitignore = Join-Path $Target '.gitignore'
if (Test-Path -LiteralPath $gitignore) {
    $have = @([IO.File]::ReadAllLines($gitignore) | ForEach-Object { $_.Trim() })
    $add = @($ignoreLines | Where-Object { $have -notcontains $_ })
    if ($add.Count -gt 0) {
        [IO.File]::AppendAllText($gitignore, "`n# orchestrator: dữ liệu lúc chạy`n" + ($add -join "`n") + "`n", $utf8)
        Write-Host "Đã thêm vào .gitignore có sẵn: $($add -join ', ')"
    }
} else {
    New-TextIfMissing '.gitignore' ("# orchestrator: dữ liệu lúc chạy`n" + ($ignoreLines -join "`n") + "`n")
}

# 4. Skill khung theo stack (nội dung trống, chờ điền)
function ConvertTo-Slug([string]$Name) { return (($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')) }

function New-StackSkill([string]$Name, [string]$Suffix, [string]$Purpose, [string[]]$ExtraFiles) {
    $slug = ConvertTo-Slug $Name
    if (-not $slug) { Write-Host "Bỏ qua skill cho '$Name' (tên không hợp lệ)."; return }
    $dir = ".claude/skills/$slug-$Suffix"
    $skill = @"
---
name: $slug-$Suffix
description: Dùng khi thiết kế, viết prompt cho worker hoặc review phần $Name của dự án này, để áp dụng $Purpose riêng của dự án.
---

# $Name — $Purpose

_Chưa điền._ Bổ sung khi có quyết định thật:
$(($ExtraFiles | ForEach-Object { "- ``$_``" }) -join "`n")
"@
    New-TextIfMissing "$dir/SKILL.md" ($skill.Replace("`r`n", "`n") + "`n")
    foreach ($f in $ExtraFiles) { New-TextIfMissing "$dir/$f" "# $f`n`n_Chưa điền._`n" }
}

if ($Tech) { New-StackSkill $Tech 'architecture' 'quy tắc kiến trúc' @('rules.md', 'checklist.md', 'anti-patterns.md') }
if ($Db) { New-StackSkill $Db 'patterns' 'quy tắc truy cập dữ liệu' @('rules.md', 'anti-patterns.md') }

# 5. Báo cáo
Write-Host "Đã tạo $($created.Count) file trong $Target"
if ($skipped.Count -gt 0) {
    Write-Host "Giữ nguyên $($skipped.Count) file đã có (không ghi đè):"
    $skipped | ForEach-Object { Write-Host "  $_" }
}

function Show-Tree([string]$Dir, [string]$Indent, [int]$Depth) {
    if ($Depth -gt 3) { return }
    $items = @(Get-ChildItem -LiteralPath $Dir -Force | Where-Object { $_.Name -ne '.git' } |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $last = $i -eq $items.Count - 1
        $branch = if ($last) { '└── ' } else { '├── ' }
        $name = if ($items[$i].PSIsContainer) { $items[$i].Name + '/' } else { $items[$i].Name }
        Write-Host "$Indent$branch$name"
        if ($items[$i].PSIsContainer) {
            $next = if ($last) { "$Indent    " } else { "$Indent│   " }
            Show-Tree $items[$i].FullName $next ($Depth + 1)
        }
    }
}
Write-Host ''
Write-Host (Split-Path -Leaf $Target)
Show-Tree $Target '' 1
exit 0
