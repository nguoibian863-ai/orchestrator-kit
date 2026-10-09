# Kiem tra tinh cua moi file .ps1 trong repo: cu phap parse duoc, va file co ky tu non-ASCII phai co UTF-8 BOM
# (PowerShell 5.1 doc file khong BOM theo ANSI nen tieng Viet bi hong).
# Ma thoat: 0 = dat | 1 = co loi
param([string]$Root = (Join-Path $PSScriptRoot '..\..'))
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$Root = (Resolve-Path -LiteralPath $Root).Path
$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1' |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
if ($files.Count -eq 0) { Write-Host "LOI: khong tim thay file .ps1 nao trong $Root"; exit 1 }

$parseErrors = 0
$bomErrors = 0
foreach ($f in $files) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    foreach ($e in $errors) {
        $parseErrors++
        Write-Host "PARSE $($f.FullName):$($e.Extent.StartLineNumber) $($e.Message)"
    }

    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $hasNonAscii = $false
    foreach ($b in $bytes) { if ($b -ge 0x80) { $hasNonAscii = $true; break } }
    if ($hasNonAscii -and -not $hasBom) {
        $bomErrors++
        Write-Host "BOM   $($f.FullName) co ky tu non-ASCII nhung thieu UTF-8 BOM"
    }
}

Write-Host "Da kiem $($files.Count) file .ps1: $parseErrors loi cu phap, $bomErrors loi BOM."
if ($parseErrors -gt 0 -or $bomErrors -gt 0) { exit 1 }
exit 0
