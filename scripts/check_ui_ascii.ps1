# Enforce ASCII-only user-visible strings in the Tab5 UI.
# Covers the LVGL C shims (Montserrat) and the Zig UI engine, whose Noto bake
# stops at 0x7E — anything above it paints a blank cell at full advance width.
param(
    [string]$UiDir = "",
    [string]$ZigUiDir = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $UiDir) {
    $UiDir = Join-Path $RepoRoot "firmware\tab5\components\modulus_zig"
}
if (-not $ZigUiDir) {
    $ZigUiDir = Join-Path $RepoRoot "src\modulus\ui_engine"
}
$IncludeDir = Join-Path $UiDir "include"

function Remove-CComments {
    param([string]$Text)
    $Text = [regex]::Replace($Text, '/\*.*?\*/', '', 'Singleline')
    $Text = [regex]::Replace($Text, '//[^\n]*', '')
    return $Text
}

function Expand-CString {
    param([string]$Literal)
    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Literal.Length) {
        if ($Literal[$i] -ne '\') {
            [void]$sb.Append($Literal[$i])
            $i++
            continue
        }
        if ($i + 1 -ge $Literal.Length) { break }
        $esc = $Literal[$i + 1]
        switch ($esc) {
            'n' { [void]$sb.Append([char]0x0A); $i += 2 }
            'r' { [void]$sb.Append([char]0x0D); $i += 2 }
            't' { [void]$sb.Append([char]0x09); $i += 2 }
            '\' { [void]$sb.Append('\'); $i += 2 }
            '"' { [void]$sb.Append('"'); $i += 2 }
            '0' { [void]$sb.Append([char]0); $i += 2 }
            default {
                [void]$sb.Append('\')
                [void]$sb.Append($esc)
                $i += 2
            }
        }
    }
    return $sb.ToString()
}

function Test-DecodedAscii {
    param(
        [string]$Decoded,
        [string]$FilePath,
        [int]$Line,
        [string]$Literal
    )
    $bad = @()
    foreach ($ch in $Decoded.ToCharArray()) {
        $code = [int][char]$ch
        # Tab and newline appear in trim sets and sanitizer fixtures, never in
        # drawn copy. Everything else outside printable ASCII is a paint bug.
        $ok = ($code -ge 0x20 -and $code -le 0x7E) -or $code -eq 0x0A -or $code -eq 0x09
        if (-not $ok) {
            $bad += "U+{0:X4}" -f $code
        }
    }
    if ($bad.Count -gt 0) {
        return [pscustomobject]@{
            File = $FilePath
            Line = $Line
            Literal = $Literal
            Chars = ($bad -join ', ')
        }
    }
    return $null
}

function Should-SkipLiteral {
    param(
        [string]$ContextLine,
        [string]$Literal
    )
    if ($ContextLine -match '(#include|ESP_LOG|snprintf|sprintf|fprintf|vsnprintf|TAG\s*=|lv_font_|icon_assets|assets/icons|\.svg|CONFIG_)') {
        return $true
    }
    if ($Literal -match '%[0-9]*[diuoxXfsc]') { return $true }
    if ($Literal -match '^[A-Za-z0-9_./\\-]+$' -and $Literal -match '[/\\]|\.(c|h|svg|png|jpg)$') {
        return $true
    }
    return $false
}

function Get-UiStringLiterals {
    param(
        [string]$FilePath,
        [string]$Text
    )
    $results = [System.Collections.Generic.List[object]]::new()
    $lines = $Text -split "`n"
    for ($lineIdx = 0; $lineIdx -lt $lines.Count; $lineIdx++) {
        $line = $lines[$lineIdx]
        $lineNum = $lineIdx + 1
        $isUiContext = $false
        if ($line -match 'lv_\w+_set_(?:text(?:_static)?|placeholder_text|options)\s*\(') { $isUiContext = $true }
        if ($line -match 'MOD_UI_ICON_\w+,\s*"') { $isUiContext = $true }
        if ($line -match 'settings_(?:section|detail|action|destructive|toggle|slider|dropdown|note)_row\s*\(') { $isUiContext = $true }
        if ($line -match 'modulus_(?:ui_|pwr_)') { $isUiContext = $true }
        if ($line -match '=\s*"[A-Za-z]') { $isUiContext = $true }

        $matches = [regex]::Matches($line, '"((?:[^"\\]|\\.)*)"')
        foreach ($m in $matches) {
            $literal = $m.Groups[1].Value
            if (-not $isUiContext -and -not (Should-SkipLiteral $line $literal)) {
                continue
            }
            if (Should-SkipLiteral $line $literal) { continue }
            $decoded = Expand-CString $literal
            $hit = Test-DecodedAscii $decoded $FilePath $lineNum $literal
            if ($hit) { $results.Add($hit) }
        }
    }
    return $results
}

# Zig has no UI-context heuristic: every literal in the engine is either drawn,
# a format string, or an import path, and all three must be ASCII.
function Get-ZigStringLiterals {
    param(
        [string]$FilePath,
        [string]$Text
    )
    $results = [System.Collections.Generic.List[object]]::new()
    $lines = $Text -split "`n"
    for ($lineIdx = 0; $lineIdx -lt $lines.Count; $lineIdx++) {
        foreach ($m in [regex]::Matches($lines[$lineIdx], '"((?:[^"\\]|\\.)*)"')) {
            $literal = $m.Groups[1].Value
            $decoded = Expand-CString $literal
            $hit = Test-DecodedAscii $decoded $FilePath ($lineIdx + 1) $literal
            if ($hit) { $results.Add($hit) }
        }
    }
    return $results
}

$files = @()
$files += Get-ChildItem -LiteralPath $UiDir -Filter "ui_*.c" -File -ErrorAction SilentlyContinue
if (Test-Path $IncludeDir) {
    $files += Get-ChildItem -LiteralPath $IncludeDir -Filter "ui_*.h" -File -ErrorAction SilentlyContinue
}
if ($files.Count -eq 0) {
    Write-Error "No ui_*.c/h files under $UiDir"
}

$zigFiles = @()
if (Test-Path $ZigUiDir) {
    $zigFiles += Get-ChildItem -LiteralPath $ZigUiDir -Filter "*.zig" -File -ErrorAction SilentlyContinue
}
if ($zigFiles.Count -eq 0) {
    Write-Error "No *.zig files under $ZigUiDir"
}

$violations = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $stripped = Remove-CComments $raw
    foreach ($hit in (Get-UiStringLiterals $file.FullName $stripped)) {
        $violations.Add($hit)
    }
}
foreach ($file in $zigFiles) {
    # Generated font atlases are byte tables, not text.
    if ($file.Name -like "font_*.zig" -or $file.Name -like "icons_*.zig") { continue }
    $raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $stripped = Remove-CComments $raw
    foreach ($hit in (Get-ZigStringLiterals $file.FullName $stripped)) {
        $violations.Add($hit)
    }
}

if ($violations.Count -eq 0) {
    $total = $files.Count + $zigFiles.Count
    Write-Host "OK: $total UI files ($($zigFiles.Count) Zig) - all checked literals are ASCII."
    exit 0
}

Write-Host 'FAIL: non-ASCII UI string literals (ASCII printable only; see modulus-tab5-ui-ascii.mdc):' -ForegroundColor Red
foreach ($v in $violations) {
    $rel = $v.File
    if ($rel.StartsWith($RepoRoot)) {
        $rel = $rel.Substring($RepoRoot.Length).TrimStart('\', '/')
    }
    Write-Host ('  {0}:{1}: "{2}" -> {3}' -f $rel, $v.Line, $v.Literal, $v.Chars)
}
exit 1
