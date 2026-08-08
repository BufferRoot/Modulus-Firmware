# Part F6 — Tab5 performance / scroll soak helper (manual operator pass on device)
# Builds (optional), records ELF SHA256, writes Part E template, opens serial monitor.
param(
    [string]$Port = "COM5",
    [int]$IdleSeconds = 55,
    [switch]$SkipBuild,
    [string]$LogDir = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
$Tab5Dir = Join-Path $RepoRoot "firmware\tab5"
$ElfPath = Join-Path $Tab5Dir "build\modulus_tab5.elf"
$BinPath = Join-Path $Tab5Dir "build\modulus_tab5.bin"

if (-not $LogDir) {
    $LogDir = Join-Path $RepoRoot "docs\verify"
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Get-ElfSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

Write-Host "==> Modulus Tab5 Part F6 performance soak"
Write-Host "    Workspace: $RepoRoot"
Write-Host ""

if (-not $SkipBuild) {
    & "$RepoRoot\scripts\build_tab5.ps1" -SkipAscii
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$sha = Get-ElfSha256 -Path $ElfPath
$appSize = $null
if (Test-Path -LiteralPath $BinPath) {
    $appSize = (Get-Item -LiteralPath $BinPath).Length
}

$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$templatePath = Join-Path $LogDir "soak_f6_template_${stamp}.txt"

Write-Host ""
Write-Host "=== Part F6 measurement protocol ==="
Write-Host ""
Write-Host "ELF: $ElfPath"
Write-Host "SHA256: $sha"
if ($appSize) {
    Write-Host ("App size: 0x{0:x} ({1:N0} bytes)" -f $appSize, $appSize)
}
Write-Host ""
Write-Host "Operator steps:"
Write-Host "  1. Idle WDT — dashboard $IdleSeconds s, no touch (PASS = no IDLE0/taskLVGL WDT)"
Write-Host "  2. LVGL CPU — menuconfig: CONFIG_LV_USE_PERF_MONITOR=y; idle dashboard avg < 70%"
Write-Host "  3. Scroll hitch — F2 fling: Power (battery), Storage (I2C scan), Wireless WiFi (>=8 APs)"
Write-Host "  4. Frame time — perf monitor: idle >=25 FPS; settings scroll >=20 FPS"
Write-Host "  5. Heap — compare display init log vs after settings close (PSRAM max block stable)"
Write-Host ""
Write-Host "Fill template: $templatePath"
Write-Host ""

$template = @"
Date: $(Get-Date -Format "yyyy-MM-dd")
P4 ELF SHA256: $sha
C6 image version:
Flash: COM5 only / dual COM6->COM5
Cold boot: Wireless ready Y/N  SDIO errors:
Idle dashboard ${IdleSeconds}s WDT: PASS/FAIL
LVGL CPU idle (perf monitor): ___%
Scroll soak (F2): PASS/FAIL
Frame FPS idle / scroll: ___ / ___
Heap PSRAM largest blk (init / settings close): ___ / ___
Notes:
"@

Set-Content -LiteralPath $templatePath -Value $template -Encoding UTF8

& "$RepoRoot\scripts\flash_tab5.ps1" -Port $Port -Monitor -SkipBuild
