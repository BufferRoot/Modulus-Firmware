# Flash Tab5 hosted wireless: ESP32-C6 slave (COM6) then ESP32-P4 host (COM5).
#
# WHEN TO USE:
#   - First-time C6 modulus image install
#   - C6 slave stale/missing/wrong esp_hosted version
#   - SDIO 0x107 or "Wireless not ready" after cold boot
#   - Wireless/Kconfig/esp_hosted slave changes
#
# WHEN TO SKIP (use flash_tab5.ps1 COM5 instead):
#   - C6 already has matching 2.11.4 modulus slave + prior boot "Wireless ready"
#   - UI-only / Zig-only / P4 app changes with no C6 or hosted config changes
#
# Default C6 image: ESP-NOW/Wi-Fi hosted (Zigbee on NanoH2, NOT on C6).
# Pass -ZigbeeExclusive only for legacy ZBOSS-on-C6 experiments (kills ESP-NOW coex).
#
# C6 USB may need BOOT held during connect; power-cycle Tab5 after both flashes.
param(
    [string]$C6Port = "COM18",
    [string]$P4Port = "COM5",
    [string]$IdfPath = "",
    [switch]$SkipAscii,
    [switch]$SkipBuild,
    [switch]$Monitor,
    [switch]$P4Only,
    [switch]$ZigbeeExclusive
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
Write-Host "==> Workspace: $RepoRoot"
if ($RepoRoot -match 'Modulus Firmware') {
    Write-Warning "WRONG TREE: dual flash from 'Modulus Convert to ZIG' only."
}

function Resolve-ZigExe {
    $cmd = Get-Command zig -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Error "zig not found - install Zig 0.16+ and ensure it is on PATH"
    }
    return $cmd.Source
}

$c6BuildArgs = @{ Action = "build" }
$c6FlashArgs = @{ Action = "flash"; Port = $C6Port }
if ($ZigbeeExclusive) {
    Write-Warning 'ZigbeeExclusive: ZBOSS on C6 - ESP-NOW coex will suffer. Prefer NanoH2.'
    $c6BuildArgs.ZigbeeExclusive = $true
    $c6FlashArgs.ZigbeeExclusive = $true
}

if (-not $SkipAscii) {
    Write-Host "==> check_ui_ascii"
    & "$PSScriptRoot\check_ui_ascii.ps1"
}

Push-Location $RepoRoot
try {
    if (-not $SkipBuild) {
        $env:ZIG_EXE = Resolve-ZigExe
        Write-Host "==> zig build test"
        & $env:ZIG_EXE build test
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        Write-Host "==> zig build tab5-lib"
        & $env:ZIG_EXE build tab5-lib
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        if (-not $P4Only) {
            if ($ZigbeeExclusive) {
                Write-Host "==> build_tab5_c6_modulus.ps1 -ZigbeeExclusive -Action build"
            } else {
                Write-Host "==> build_tab5_c6_modulus.ps1 -Action build (ESP-NOW product image)"
            }
            & "$PSScriptRoot\build_tab5_c6_modulus.ps1" @c6BuildArgs
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }

        Write-Host "==> build_tab5.ps1"
        & "$PSScriptRoot\build_tab5.ps1" -IdfPath $IdfPath -SkipAscii
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    if (-not $P4Only) {
        if ($ZigbeeExclusive) {
            Write-Host "==> Flash C6 slave on $C6Port (-ZigbeeExclusive ZBOSS - hold BOOT if connect fails)"
        } else {
            Write-Host "==> Flash C6 slave on $C6Port (ESP-NOW product - hold BOOT if connect fails)"
        }
        & "$PSScriptRoot\build_tab5_c6_modulus.ps1" @c6FlashArgs
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Start-Sleep -Seconds 2
    } else {
        Write-Warning "P4Only: skipping C6 flash - SDIO 0x107 likely until C6 slave matches P4 esp_hosted 2.11.4"
    }

    $flashArgs = @{
        Port       = $P4Port
        IdfPath    = $IdfPath
        SkipAscii  = $true
        SkipBuild  = $true
    }
    if ($Monitor) { $flashArgs.Monitor = $true }

    Write-Host "==> Flash P4 host on $P4Port"
    & "$PSScriptRoot\flash_tab5.ps1" @flashArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host ''
    Write-Host 'Dual flash done. Cold-boot verify: WLAN_PWR_EN -> Card init success -> wireless_shim: Wireless ready'
    if ($ZigbeeExclusive) {
        Write-Host 'C6 ZigbeeExclusive: early log should include ZBOSS HUB PATH compiled'
    }
    Write-Host 'If checksum mismatch in monitor: rebuild from this repo (not Modulus Firmware/) and reflash both chips.'
}
finally {
    Pop-Location
}
