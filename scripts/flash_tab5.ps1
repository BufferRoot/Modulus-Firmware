# Flash Modulus Tab5 - zig tab5-lib from repo root, idf.py flash from firmware/tab5
param(
    [string]$Port = "COM5",
    [switch]$Monitor,
    [string]$IdfPath = "",
    [switch]$SkipAscii,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
Write-Host "==> Workspace: $RepoRoot"
if ($RepoRoot -match 'Modulus Firmware') {
    Write-Warning "WRONG TREE: flash from 'Modulus Convert to ZIG' - stale ELF causes Checksum mismatch in monitor."
}

function Resolve-ZigExe {
    $cmd = Get-Command zig -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Error "zig not found - install Zig 0.16+ and ensure it is on PATH"
    }
    return $cmd.Source
}

function Ensure-IdfEnv {
    param([string]$PathOverride)
    if ($PathOverride) { $env:IDF_PATH = $PathOverride }
    if ([string]::IsNullOrWhiteSpace($env:IDF_PATH)) {
        $default = "C:\Espressif\frameworks\esp-idf-v6.0.1"
        if (Test-Path -LiteralPath $default) {
            $env:IDF_PATH = $default
            Write-Host "==> IDF_PATH default: $env:IDF_PATH"
        }
    }
    if ([string]::IsNullOrWhiteSpace($env:IDF_PATH)) {
        Write-Error "IDF_PATH not set - pass -IdfPath or run ESP-IDF export.ps1"
    }
    Write-Host "==> IDF_PATH: $env:IDF_PATH"
    if ($env:IDF_PATH -match 'Modulus Firmware') {
        Write-Warning "IDF_PATH points at 'Modulus Firmware' tree - use ESP-IDF framework path only."
    }
    $export = Join-Path -Path $env:IDF_PATH -ChildPath "export.ps1"
    if (-not (Test-Path -LiteralPath $export)) {
        Write-Error "Missing export.ps1 at $export"
    }
    & $export | Out-Null
}

if (-not $SkipAscii) {
    Write-Host "==> check_ui_ascii"
    & "$PSScriptRoot\check_ui_ascii.ps1"
}

Push-Location $RepoRoot
try {
    if (-not $SkipBuild) {
        $env:ZIG_EXE = Resolve-ZigExe
        $zigEnvText = & $env:ZIG_EXE env 2>&1 | Out-String
        if ($zigEnvText -match 'lib_dir = "(.+)"') {
            $env:ZIG_LIB_DIR = $Matches[1]
        }
        Write-Host "==> ZIG_EXE=$env:ZIG_EXE"
        Write-Host "==> zig build tab5-lib"
        & $env:ZIG_EXE build tab5-lib
    }

    Ensure-IdfEnv -PathOverride $IdfPath
    $env:ZIG_EXE = Resolve-ZigExe

    Push-Location "$RepoRoot\firmware\tab5"
    try {
        & "$PSScriptRoot\patch_tab5_idf6_deps.ps1"
        Write-Host "==> idf.py build"
        idf.py build
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }

        $elfPath = Join-Path $RepoRoot "firmware\tab5\build\modulus_tab5.elf"
        if (Test-Path -LiteralPath $elfPath) {
            $sha = (Get-FileHash -LiteralPath $elfPath -Algorithm SHA256).Hash.ToLower()
            Write-Host "==> P4 ELF SHA256: $sha"
            Write-Host "==> Compare with boot log 'Checksum mismatch' line before trusting serial output."
            Write-Host "==> Open monitor from: $RepoRoot\firmware\tab5 (idf.py -p $Port monitor). Wrong-tree monitor (Modulus Firmware/) shows bogus checksum - close it before flash."
        }
        Write-Host "==> P4-only flash (normal for UI/Zig/P4 work). Use scripts\flash_tab5_dual.ps1 only if cold boot shows SDIO 0x107, Wireless not ready, or C6/esp_hosted changed."

        if ($Monitor) {
            Write-Host "==> idf.py -p $Port flash monitor"
            idf.py -p $Port flash monitor
        } else {
            Write-Host "==> idf.py -p $Port flash"
            idf.py -p $Port flash
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    Pop-Location
}
