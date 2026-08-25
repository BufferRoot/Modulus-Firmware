# ESP32-S3 ESP-NOW UART bridge (field grblHAL relay - separate from Tab5 P4/C6).
# Path: firmware/s3-bridge/
# XIAO: .\scripts\build_s3_bridge.ps1 -Board xiao -Action fullclean
#       .\scripts\build_s3_bridge.ps1 -Board xiao
#       .\scripts\build_s3_bridge.ps1 -Board xiao -Action flash -Port COM9
param(
    [ValidateSet("build", "flash", "monitor", "fullclean", "set-target", "flash-monitor")]
    [string]$Action = "build",
    [ValidateSet("mini1", "xiao")]
    [string]$Board = "mini1",
    [string]$Port = "COM8",
    [string]$IdfPath = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$S3Dir = Join-Path $RepoRoot "firmware\s3-bridge"

function Get-IdfDefaultsArgs {
    if ($Board -eq "xiao") {
        return @("-D", "SDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.xiao")
    }
    return @()
}

function Ensure-IdfEnv {
    param([string]$PathOverride)
    if ($PathOverride) { $env:IDF_PATH = $PathOverride }
    if (-not $env:IDF_PATH) {
        $candidates = @(
            "$env:USERPROFILE\esp\esp-idf-v6.0.1"
            "C:\Espressif\frameworks\esp-idf-v6.0.1"
        )
        foreach ($p in $candidates) {
            if (Test-Path $p) {
                $env:IDF_PATH = $p
                Write-Host "==> IDF_PATH default: $env:IDF_PATH"
                break
            }
        }
    }
    if (-not $env:IDF_PATH) {
        Write-Error "IDF_PATH not set - pass -IdfPath or run ESP-IDF export.ps1"
    }
    $export = Join-Path $env:IDF_PATH "export.ps1"
    if (-not (Test-Path $export)) { Write-Error "Missing export.ps1 at $export" }
    & $export | Out-Null
}

if (-not (Test-Path $S3Dir)) {
    Write-Error "Missing $S3Dir"
}

Ensure-IdfEnv -PathOverride $IdfPath
Write-Host "==> S3 bridge: $S3Dir  board=$Board"
$IdfDefaults = Get-IdfDefaultsArgs

Push-Location $S3Dir
try {
    switch ($Action) {
        "set-target" {
            idf.py @IdfDefaults set-target esp32s3
        }
        "fullclean" {
            idf.py fullclean
        }
        "build" {
            if (-not (Test-Path "sdkconfig")) {
                Write-Host "==> idf.py set-target esp32s3 (first build, board=$Board)"
                idf.py @IdfDefaults set-target esp32s3
            } elseif ($Board -eq "xiao") {
                $cfg = Get-Content "sdkconfig" -Raw
                if ($cfg -notmatch "CONFIG_S3_BRIDGE_BOARD_XIAO=y") {
                    Write-Error "sdkconfig is not XIAO. Run: .\scripts\build_s3_bridge.ps1 -Board xiao -Action fullclean"
                }
            }
            idf.py @IdfDefaults build
            $bin = Join-Path $S3Dir "build\s3_espnow_uart_bridge.bin"
            if (Test-Path $bin) {
                $bytes = (Get-Item $bin).Length
                Write-Host ('==> s3_espnow_uart_bridge.bin 0x{0:X} ({1} bytes)' -f $bytes, $bytes)
            }
        }
        "flash" {
            idf.py -p $Port flash
        }
        "monitor" {
            idf.py -p $Port monitor
        }
        "flash-monitor" {
            idf.py -p $Port flash monitor
        }
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
