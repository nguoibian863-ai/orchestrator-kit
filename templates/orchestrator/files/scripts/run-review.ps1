# Gộp 3 báo cáo reviewer/security/qa của một task, đếm phát hiện theo mức độ và ra kết luận.
# Mã thoát: 0 = không còn CRITICAL/HIGH | 1 = còn CRITICAL/HIGH -> sang bước fix | 2 = thiếu báo cáo
param([Parameter(Mandatory = $true)][string]$TaskId)
. (Join-Path $PSScriptRoot '_lib.ps1')
Assert-TaskId $TaskId

# Đếm dòng phát hiện (dòng bắt đầu bằng "- ", "* " hoặc "1. " ở đầu dòng) dưới từng heading mức độ.
function Measure-Findings([string]$Text) {
    $result = @{ CRITICAL = 0; HIGH = 0; MEDIUM = 0; LOW = 0 }
    $section = $null
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s{0,3}#{1,6}\s*(CRITICAL|HIGH|MEDIUM|LOW)\b') { $section = $Matches[1].ToUpper(); continue }
        if ($line -match '^\s{0,3}#') { $section = $null; continue }
        if ($section -and $line -match '^(?:[-*+]|\d+[.)])\s+(.*)$') {
            if ($Matches[1].Trim() -notmatch '^[\(\[_*]*\s*(không có|không|none|n/?a|—|-)\s*[\)\]_*.]*$') { $result[$section]++ }
        }
    }
    return $result
}

$taskRel = "tasks/$TaskId"
$roles = [ordered]@{ reviewer = 'Reviewer'; security = 'Security Auditor'; qa = 'QA' }
$levels = @('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
$reports = [ordered]@{}
$missing = @()
foreach ($k in $roles.Keys) {
    $p = Get-ProjectPath "$taskRel/$k-output.md"
    if (Test-Path -LiteralPath $p) { $reports[$k] = Read-TextUtf8 $p } else { $missing += "$taskRel/$k-output.md" }
}
if ($missing.Count -gt 0) { Fail 2 "Thiếu báo cáo: $($missing -join ', ')" }

$totals = @{ CRITICAL = 0; HIGH = 0; MEDIUM = 0; LOW = 0 }
$rows = @('| Nguồn | CRITICAL | HIGH | MEDIUM | LOW |', '|---|---|---|---|---|')
foreach ($k in $reports.Keys) {
    $c = Measure-Findings $reports[$k]
    foreach ($l in $levels) { $totals[$l] += $c[$l] }
    $rows += "| $($roles[$k]) | $($c.CRITICAL) | $($c.HIGH) | $($c.MEDIUM) | $($c.LOW) |"
}
$rows += "| **Tổng** | **$($totals.CRITICAL)** | **$($totals.HIGH)** | **$($totals.MEDIUM)** | **$($totals.LOW)** |"
$blocking = $totals.CRITICAL + $totals.HIGH
$verdict = if ($blocking -gt 0) { "CHƯA ĐẠT — còn $($totals.CRITICAL) CRITICAL, $($totals.HIGH) HIGH" } else { 'ĐẠT — không còn CRITICAL/HIGH' }

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
foreach ($k in $reports.Keys) {
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("## Từ $($roles[$k])")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($reports[$k].Trim())
}
Write-TextUtf8 (Get-ProjectPath $summaryRel) $sb.ToString()
[void](Update-TaskState -TaskId $TaskId -Fields @{ last_review_summary = $summaryRel })

$rows | ForEach-Object { Write-Host $_ }
Write-Host "Kết luận: $verdict"
Write-Host "Báo cáo: $summaryRel"
if ($blocking -gt 0) { exit 1 }
exit 0
