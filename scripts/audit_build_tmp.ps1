# Temporary audit build driver v3 — proper IDF env via export.ps1.
$ErrorActionPreference = 'Continue'
$env:PATHEXT = '.COM;.EXE;.BAT;.CMD;.PS1'
$env:IDF_TOOLS_PATH = 'C:\Espressif'
$env:IDF_PATH = 'C:\Espressif\frameworks\esp-idf-v6.0.1'
$env:PYTHONUTF8 = '1'
$env:ZIG_EXE = 'C:\Users\BEAST MODE\AppData\Local\Microsoft\WinGet\Packages\zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe\zig-x86_64-windows-0.16.0\zig.exe'
$zigEnvText = & $env:ZIG_EXE env 2>&1 | Out-String
if ($zigEnvText -match 'lib_dir = "(.+)"') { $env:ZIG_LIB_DIR = $Matches[1] }
Write-Host "==> ZIG_EXE=$env:ZIG_EXE"
Write-Host "==> ZIG_LIB_DIR=$env:ZIG_LIB_DIR"

Write-Host '==> export.ps1'
& "$env:IDF_PATH\export.ps1"
$idfpy = (Get-Command idf.py -ErrorAction SilentlyContinue).Source
Write-Host "==> export done (idf.py: $idfpy)"
if (-not $idfpy) { Write-Host '==> BUILD_EXIT=90 (export failed)'; exit 90 }

Set-Location 'C:\Users\BEAST MODE\Desktop\Modulus Convert to ZIG\firmware\tab5'
Remove-Item Env:SDKCONFIG_DEFAULTS -ErrorAction SilentlyContinue
& 'C:\Users\BEAST MODE\Desktop\Modulus Convert to ZIG\scripts\patch_tab5_idf6_deps.ps1'
Write-Host '==> idf.py build'
idf.py build
Write-Host "==> BUILD_EXIT=$LASTEXITCODE"
