# Package prebuilt flash images from local IDF build dirs into dist/flash-images/.
# Run after a successful full build. Does not rebuild.
param(
    [string]$Version = "3.0.0",
    [string]$OutRoot = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
if (-not $OutRoot) { $OutRoot = Join-Path $RepoRoot "dist\flash-images\v$Version" }

function Copy-FlashSet {
    param(
        [string]$Name,
        [string]$BuildDir,
        [string]$Chip,
        [hashtable]$Files,  # destName -> relative path under BuildDir
        [string]$FlashCmd
    )
    if (-not (Test-Path -LiteralPath $BuildDir)) {
        Write-Warning "Skip $Name — missing build dir: $BuildDir"
        return $null
    }
    $dest = Join-Path $OutRoot $Name
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    foreach ($kv in $Files.GetEnumerator()) {
        $src = Join-Path $BuildDir $kv.Value
        if (-not (Test-Path -LiteralPath $src)) {
            throw "Missing $src for $Name"
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $dest $kv.Key) -Force
    }
    Copy-Item -LiteralPath (Join-Path $BuildDir "flasher_args.json") -Destination (Join-Path $dest "flasher_args.json") -Force -ErrorAction SilentlyContinue

    $readme = @"
# Modulus $Name — flash package v$Version

Chip: **$Chip**

## esptool (from this folder)

``````text
$FlashCmd
``````

Requires esptool or ESP-IDF ``idf.py -p COMx flash`` from the matching ``firmware/`` tree after build.

SHA256 of each ``.bin`` is listed in ``../SHA256SUMS.txt``.
"@
    Set-Content -Path (Join-Path $dest "FLASH.md") -Value $readme -Encoding utf8
    return $dest
}

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
Write-Host "==> Packaging -> $OutRoot"

$c6Build = "C:\modulus_tab5_c6_build\slave\build"
if (-not (Test-Path -LiteralPath (Join-Path $c6Build "network_adapter.bin"))) {
    $c6Build = Join-Path $RepoRoot "firmware\tab5-c6\build"
}

$sets = @()
$sets += Copy-FlashSet -Name "tab5-p4" -BuildDir (Join-Path $RepoRoot "firmware\tab5\build") -Chip "esp32p4" -Files @{
    "bootloader.bin"        = "bootloader\bootloader.bin"
    "partition-table.bin"   = "partition_table\partition-table.bin"
    "modulus_tab5.bin"      = "modulus_tab5.bin"
} -FlashCmd @'
esptool.py --chip esp32p4 -p COM5 --before default-reset --after hard-reset write_flash --flash-mode dio --flash-freq 40m --flash-size 16MB ^
  0x2000 bootloader.bin ^
  0x8000 partition-table.bin ^
  0x10000 modulus_tab5.bin
'@

$c6Files = @{
    "bootloader.bin"      = "bootloader\bootloader.bin"
    "partition-table.bin" = "partition_table\partition-table.bin"
    "network_adapter.bin" = "network_adapter.bin"
}
if (Test-Path -LiteralPath (Join-Path $c6Build "ota_data_initial.bin")) {
    $c6Files["ota_data_initial.bin"] = "ota_data_initial.bin"
}
$sets += Copy-FlashSet -Name "tab5-c6" -BuildDir $c6Build -Chip "esp32c6" -Files $c6Files -FlashCmd @'
esptool.py --chip esp32c6 -p COM6 --before default-reset --after hard-reset write_flash --flash-mode dio --flash-freq 80m --flash-size 4MB ^
  0x0 bootloader.bin ^
  0x8000 partition-table.bin ^
  0xd000 ota_data_initial.bin ^
  0x10000 network_adapter.bin
'@

$sets += Copy-FlashSet -Name "nanoh2" -BuildDir (Join-Path $RepoRoot "firmware\nanoh2\build") -Chip "esp32h2" -Files @{
    "bootloader.bin"      = "bootloader\bootloader.bin"
    "partition-table.bin" = "partition_table\partition-table.bin"
    "modulus_nanoh2.bin"  = "modulus_nanoh2.bin"
} -FlashCmd @'
esptool.py --chip esp32h2 -p COM7 --before default-reset --after hard-reset write_flash --flash-mode dio --flash-freq 48m --flash-size 4MB ^
  0x0 bootloader.bin ^
  0x8000 partition-table.bin ^
  0x10000 modulus_nanoh2.bin
'@

$sets += Copy-FlashSet -Name "s3-bridge" -BuildDir (Join-Path $RepoRoot "firmware\s3-bridge\build") -Chip "esp32s3" -Files @{
    "bootloader.bin"              = "bootloader\bootloader.bin"
    "partition-table.bin"         = "partition_table\partition-table.bin"
    "s3_espnow_uart_bridge.bin"   = "s3_espnow_uart_bridge.bin"
} -FlashCmd @'
esptool.py --chip esp32s3 -p COM8 --before default-reset --after hard-reset write_flash --flash-mode dio --flash-freq 80m --flash-size 8MB ^
  0x0 bootloader.bin ^
  0x8000 partition-table.bin ^
  0x10000 s3_espnow_uart_bridge.bin
'@

$sums = Join-Path $OutRoot "SHA256SUMS.txt"
Remove-Item -LiteralPath $sums -ErrorAction SilentlyContinue
Get-ChildItem -Path $OutRoot -Recurse -Filter "*.bin" | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $_.FullName.Substring($OutRoot.Length).TrimStart('\','/') -replace '\\','/'
    Add-Content -Path $sums -Value "$hash  $rel"
}

$zips = @()
Get-ChildItem -Path $OutRoot -Directory | ForEach-Object {
    $zip = Join-Path $OutRoot ("modulus-{0}-v{1}.zip" -f $_.Name, $Version)
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $_.FullName '*') -DestinationPath $zip -Force
    $zips += $zip
    Write-Host "==> $zip"
}

Write-Host "==> Done. Zips:"
$zips | ForEach-Object { Write-Host "  $_" }
Write-Host "==> SHA256SUMS: $sums"
