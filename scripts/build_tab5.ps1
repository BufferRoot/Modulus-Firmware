# Build Modulus Tab5 firmware (requires ESP-IDF 6.0 + Zig 0.16 on PATH)
param(
    [switch]$LibOnly,
    [switch]$Flash,
    [string]$Port = "",
    [string]$IdfPath = "",
    [switch]$SkipAscii
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
Write-Host "==> Workspace: $RepoRoot"
if ($RepoRoot -match 'Modulus Firmware') {
    Write-Warning "WRONG TREE: build from 'Modulus Convert to ZIG' - stale ELF causes Checksum mismatch in monitor."
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
    $env:ZIG_EXE = Resolve-ZigExe
    $zigEnvText = & $env:ZIG_EXE env 2>&1 | Out-String
    if ($zigEnvText -match 'lib_dir = "(.+)"') {
        $env:ZIG_LIB_DIR = $Matches[1]
    }
    Write-Host "==> ZIG_EXE=$env:ZIG_EXE"
    Write-Host "==> ZIG_LIB_DIR=$env:ZIG_LIB_DIR"
    Write-Host "==> gen_ui_palettes"
    python "$PSScriptRoot\gen_ui_palettes.py"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "==> zig build tab5-lib"
    & $env:ZIG_EXE build tab5-lib
    if ($LibOnly) { exit 0 }

    Ensure-IdfEnv -PathOverride $IdfPath
    $env:ZIG_EXE = Resolve-ZigExe

    Push-Location "$RepoRoot\firmware\tab5"
    Remove-Item Env:SDKCONFIG_DEFAULTS -ErrorAction SilentlyContinue
    & "$PSScriptRoot\patch_tab5_idf6_deps.ps1"
    if (-not (Test-Path -LiteralPath "sdkconfig") -or -not (Select-String -Path "sdkconfig" -Pattern 'CONFIG_IDF_TARGET="esp32p4"' -Quiet)) {
        Write-Host "==> idf.py set-target esp32p4"
        idf.py set-target esp32p4
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    } else {
        Write-Host "==> skip set-target (esp32p4 sdkconfig present)"
    }
    Write-Host "==> idf.py build"
    idf.py build
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $binPath = Join-Path $RepoRoot "firmware\tab5\build\modulus_tab5.bin"
    if (Test-Path -LiteralPath $binPath) {
        $appBytes = (Get-Item -LiteralPath $binPath).Length
        $factoryBytes = 0x500000
        $usedPct = [math]::Round(100.0 * $appBytes / $factoryBytes, 1)
        $freePct = [math]::Round(100.0 - $usedPct, 1)
        Write-Host ("==> App size: 0x{0:x} ({1:N0} bytes, {2}% factory used, {3}% free)" -f `
            $appBytes, $appBytes, $usedPct, $freePct)
        if ($usedPct -ge 85.0) {
            Write-Warning ("Factory partition headroom low: {0}% used (threshold 85%). Review fonts/icon ROM before adding assets." -f $usedPct)
        }
        $elfPath = Join-Path $RepoRoot "firmware\tab5\build\modulus_tab5.elf"
        if (Test-Path -LiteralPath $elfPath) {
            $sha = (Get-FileHash -LiteralPath $elfPath -Algorithm SHA256).Hash.ToLower()
            Write-Host "==> P4 ELF SHA256: $sha"
            Write-Host "==> Flash from this workspace only; compare with boot log Checksum mismatch line."
        }
    } else {
        Write-Warning "modulus_tab5.bin not found after build; skip partition headroom check"
    }

    if ($Flash) {
        if (-not $Port) {
            Write-Error "Pass -Port COMx to flash (e.g. -Flash -Port COM5)"
        }
        Write-Host "==> idf.py -p $Port flash"
        idf.py -p $Port flash
    }
}
finally {
    Pop-Location
}
