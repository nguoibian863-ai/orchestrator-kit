# Gộp báo cáo review của một task, đếm phát hiện theo mức độ và ra kết luận.
# Nếu thiếu khoá mode và thiếu review-output.md nhưng đủ 3 báo cáo cũ thì dùng full để tương thích ngược.
# CRITICAL/HIGH gắn conf:LOW không tính chặn và được liệt kê riêng trong báo cáo tổng hợp.
# Mã thoát: 0 = không còn CRITICAL/HIGH tính chặn | 1 = còn CRITICAL/HIGH tính chặn -> sang bước fix | 2 = thiếu báo cáo
param([Parameter(Mandatory = $true)][string]$TaskId)
. (Join-Path $PSScriptRoot '_lib.ps1')
Assert-TaskId $TaskId

# Đếm phát hiện theo heading; nhãn chỉ hợp lệ khi đứng ngay đầu nội dung sau dấu đầu dòng.
function Measure-Findings([string]$Text) {
    $result = @{
        CRITICAL = 0
        HIGH = 0
        MEDIUM = 0
        LOW = 0
        LowConf = 0
        Untagged = 0
        LowConfLines = @()
    }
    $section = $null
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s{0,3}#{1,6}\s*(CRITICAL|HIGH|MEDIUM|LOW)\b') { $section = $Matches[1].ToUpperInvariant(); continue }
        if ($line -match '^\s{0,3}#') { $section = $null; continue }
        if ($section -and $line -match '^(?:[-*+]|\d+[.)])\s+(.*)$') {
            $originalContent = $Matches[1]
            $content = $originalContent
            $confidence = $null
            if ($originalContent -match '^[*_]*\[\s*conf(?:idence)?\s*[:=]\s*(HIGH|MEDIUM|LOW)\s*\][*_]*\s*(.*)$') {
                $confidence = $Matches[1].ToUpperInvariant()
                $content = $Matches[2]
            }
            if ($content.Trim() -notmatch '^[\(\[_*]*\s*(không có|không|none|n/?a|—|-)\s*[\)\]_*.]*$') {
                if ($section -eq 'CRITICAL' -or $section -eq 'HIGH') {
                    if ($confidence -eq 'LOW') {
                        $result.LowConf++
                        $result.LowConfLines += "[$section] $originalContent"
                    } else {
                        $result[$section]++
                        if (-not $confidence) { $result.Untagged++ }
                    }
                } else {
                    $result[$section]++
                }
            }
        }
    }
    return $result
}

$taskRel = "tasks/$TaskId"
# Khi config không có khoá mode, nếu thiếu review-output.md nhưng đủ cả 3 báo cáo cũ thì dùng full để tương thích ngược.
$config = Get-Config
$modeWasSet = Test-Prop $config 'mode'
$configuredMode = Get-Prop $config 'mode' ''
$modeValue = if ($null -eq $configuredMode) { '' } else { [string]$configuredMode }
$mode = if ([string]::IsNullOrWhiteSpace($modeValue)) { 'lean' } else { $modeValue.Trim().ToLowerInvariant() }
if ($mode -notin @('lean', 'full')) {
    Fail 1 "Khoá 'mode' trong orchestrator.config.json không hợp lệ: '$modeValue' (chỉ nhận: lean, full)."
}

$roles = [ordered]@{ reviewer = 'Reviewer'; security = 'Security Auditor'; qa = 'QA' }
$reportFiles = [ordered]@{ reviewer = 'reviewer-output.md'; security = 'security-output.md'; qa = 'qa-output.md' }
$legacyReportsExist = $true
foreach ($file in $reportFiles.Values) {
    if (-not (Test-Path -LiteralPath (Get-ProjectPath "$taskRel/$file"))) { $legacyReportsExist = $false; break }
}
$singleReportExists = Test-Path -LiteralPath (Get-ProjectPath "$taskRel/review-output.md")
if (-not $modeWasSet -and -not $singleReportExists -and $legacyReportsExist) {
    $mode = 'full'
}
if ($mode -eq 'lean') {
    $roles = [ordered]@{ orchestrator = 'Orchestrator' }
    $reportFiles = [ordered]@{ orchestrator = 'review-output.md' }
}
Write-Host "Chế độ review: $mode"

$levels = @('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
$reports = [ordered]@{}
$missing = @()
foreach ($k in $roles.Keys) {
    $relativeReport = "$taskRel/$($reportFiles[$k])"
    $p = Get-ProjectPath $relativeReport
    if (Test-Path -LiteralPath $p) { $reports[$k] = Read-TextUtf8 $p } else { $missing += $relativeReport }
}
if ($missing.Count -gt 0) { Fail 2 "Thiếu báo cáo: $($missing -join ', ')" }

$totals = @{ CRITICAL = 0; HIGH = 0; MEDIUM = 0; LOW = 0; LowConf = 0; Untagged = 0 }
$rows = @('| Nguồn | CRITICAL | HIGH | MEDIUM | LOW | CRIT/HIGH conf:LOW |', '|---|---|---|---|---|---|')
$lowConfLines = @()
foreach ($k in $reports.Keys) {
    $c = Measure-Findings $reports[$k]
    foreach ($l in $levels) { $totals[$l] += $c[$l] }
    $totals.LowConf += $c.LowConf
    $totals.Untagged += $c.Untagged
    $rows += "| $($roles[$k]) | $($c.CRITICAL) | $($c.HIGH) | $($c.MEDIUM) | $($c.LOW) | $($c.LowConf) |"
    foreach ($finding in $c.LowConfLines) { $lowConfLines += "- [$($roles[$k])]$finding" }
}
$rows += "| **Tổng** | **$($totals.CRITICAL)** | **$($totals.HIGH)** | **$($totals.MEDIUM)** | **$($totals.LOW)** | **$($totals.LowConf)** |"
$blocking = $totals.CRITICAL + $totals.HIGH
if ($blocking -gt 0) {
    $verdict = "CHƯA ĐẠT — còn $($totals.CRITICAL) CRITICAL, $($totals.HIGH) HIGH"
} elseif ($totals.LowConf -gt 0) {
    $verdict = "ĐẠT — không còn CRITICAL/HIGH tính chặn (có $($totals.LowConf) CRITICAL/HIGH gắn conf:LOW, xem mục riêng)"
} else {
    $verdict = 'ĐẠT — không còn CRITICAL/HIGH'
}

$task = Get-TaskEntry $TaskId
$round = 1 + [int](Get-Prop $task 'fix_attempts' 0)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$summaryRel = "reviews/$TaskId-round$round-$stamp.md"

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Báo cáo tổng hợp — $TaskId (vòng $round)")
[void]$sb.AppendLine()
[void]$sb.AppendLine("**Kết luận: $verdict**")
[void]$sb.AppendLine()
$rows | ForEach-Object { [void]$sb.AppendLine($_) }
if ($totals.Untagged -gt 0) {
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("> Ghi chú: $($totals.Untagged) phát hiện CRITICAL/HIGH thiếu nhãn [conf:...] — vẫn tính chặn.")
}
if ($lowConfLines.Count -gt 0) {
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Phát hiện CRITICAL/HIGH gắn conf:LOW (không tính chặn)')
    [void]$sb.AppendLine('> Agent vi phạm quy tắc "độ tin cậy LOW không được xếp CRITICAL/HIGH" — người đọc cần xem lại từng dòng.')
    foreach ($finding in $lowConfLines) { [void]$sb.AppendLine($finding) }
}
foreach ($k in $reports.Keys) {
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine("## Từ $($roles[$k])")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($reports[$k].Trim())
}
Write-TextUtf8 (Get-ProjectPath $summaryRel) $sb.ToString()
[void](Update-TaskState -TaskId $TaskId -Fields @{ last_review_summary = $summaryRel })

$rows | ForEach-Object { Write-Host $_ }
Write-Host "Kết luận: $verdict"
if ($totals.LowConf -gt 0) { Write-Host ('Chú ý: {0} phát hiện CRITICAL/HIGH gắn conf:LOW (không tính chặn) — xem mục "Phát hiện CRITICAL/HIGH gắn conf:LOW" trong báo cáo.' -f $totals.LowConf) }
if ($totals.Untagged -gt 0) { Write-Host "Ghi chú: $($totals.Untagged) phát hiện CRITICAL/HIGH thiếu nhãn [conf:...] — vẫn tính chặn." }
Write-Host "Báo cáo: $summaryRel"
if ($blocking -gt 0) { exit 1 }
exit 0
