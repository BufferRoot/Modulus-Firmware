# Build Modulus Tab5 ESP32-C6 ESP-Hosted slave (separate from P4 host image)
param(
    [switch]$Flash,
    [string]$Port = "COM6",
    [switch]$Monitor,
    [string]$IdfPath = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$C6Dir = Join-Path $RepoRoot "firmware\tab5-c6"

function Ensure-IdfEnv {
    param([string]$PathOverride)
    if ($PathOverride) { $env:IDF_PATH = $PathOverride }
    if (-not $env:IDF_PATH) {
        $default = "C:\Espressif\frameworks\esp-idf-v6.0.1"
        if (Test-Path $default) {
            $env:IDF_PATH = $default
            Write-Host "==> IDF_PATH default: $env:IDF_PATH"
        }
    }
    if (-not $env:IDF_PATH) {
        Write-Error "IDF_PATH not set - pass -IdfPath or run ESP-IDF export.ps1"
    }
    $export = Join-Path $env:IDF_PATH "export.ps1"
    if (-not (Test-Path $export)) { Write-Error "Missing export.ps1 at $export" }
    & $export | Out-Null
}

if (-not (Test-Path $C6Dir)) {
    Write-Error "Missing $C6Dir - copy from Modulus Firmware C6/slave reference first"
}

Ensure-IdfEnv -PathOverride $IdfPath
Push-Location $C6Dir
try {
    Write-Host "==> idf.py set-target esp32c6"
    idf.py set-target esp32c6
    Write-Host "==> idf.py build"
    idf.py build
    if ($Flash) {
        Write-Host "==> idf.py -p $Port flash"
        idf.py -p $Port flash
    }
    if ($Monitor) {
        Write-Host "==> idf.py -p $Port monitor"
        idf.py -p $Port monitor
    }
}
finally {
    Pop-Location
}
