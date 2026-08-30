# Modulus Tab5 ESP32-C6 - Phase 8c combined esp_hosted 2.11.4 SDIO slave + Modulus Zig runtime.
# Hosted-only rollback: scripts/build_tab5_c6.ps1
# Zig-only dev (no SDIO Wi-Fi): -ZigOnly
param(
    [ValidateSet("build", "flash", "monitor", "menuconfig", "fullclean", "set-target", "flash-monitor")]
    [string]$Action = "build",
    [string]$Port = "COM18",
    [switch]$ZigOnly,
    [switch]$ZigbeeExclusive,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Tab5Dir = Join-Path $Root "firmware\tab5"
$C6Dir = Join-Path $Root "firmware\tab5-c6"
$HostedDir = Join-Path $Tab5Dir "managed_components\espressif__esp_hosted"
$SlaveSrc = Join-Path $HostedDir "slave"
$SlaveDir = "C:\modulus_tab5_c6_build\slave"
$ModulusHosted = Join-Path $C6Dir "hosted"
$ModulusZigC6 = Join-Path $C6Dir "components\modulus_zig_c6"

function Import-IdfEnv {
    if (-not $env:IDF_PATH) {
        $candidates = @(
            "$env:USERPROFILE\esp\esp-idf-v6.0.1"
            "C:\Espressif\frameworks\esp-idf-v6.0.1"
        )
        foreach ($p in $candidates) {
            $export = Join-Path $p "export.ps1"
            if (Test-Path $export) {
                Write-Host "Sourcing $export"
                . $export
                return
            }
        }
        throw "IDF_PATH not set. Install ESP-IDF 6.0.1+ and run export.ps1."
    }
    $export = Join-Path $env:IDF_PATH "export.ps1"
    if (Test-Path $export) { . $export }
}

function Test-ZigInPath {
    $zig = Get-Command zig -ErrorAction SilentlyContinue
    if (-not $zig) {
        throw "zig not in PATH - required for CONFIG_MODULUS_ZIG_C6_RUNTIME"
    }
    Write-Host "Using zig: $($zig.Source)"
}

function Ensure-EspHostedSlave {
    if (-not (Test-Path $SlaveSrc)) {
        Write-Host "Fetching esp_hosted via tab5 component manager..."
        Push-Location $Tab5Dir
        try { idf.py reconfigure 2>&1 | Out-Host } finally { Pop-Location }
    }
    if (-not (Test-Path $SlaveSrc)) {
        throw "Missing $SlaveSrc - build firmware/tab5 once or add esp_hosted to main/idf_component.yml"
    }
    $mirrorRoot = Split-Path $SlaveDir -Parent
    New-Item -ItemType Directory -Force -Path $mirrorRoot | Out-Null
    Write-Host "Sync esp_hosted slave -> $SlaveDir (space-free build mirror)"
    $roboEx = @("/XD", "build", "managed_components", "sdkconfig", "sdkconfig.old")
    robocopy $SlaveSrc $SlaveDir /MIR @roboEx /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    robocopy (Join-Path $HostedDir "common") (Join-Path $mirrorRoot "common") /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit $LASTEXITCODE" }
    $sdioApi = Join-Path $SlaveDir "main\sdio_slave_api.c"
    if (Test-Path $sdioApi) {
        $c = Get-Content $sdioApi -Raw
        if ($c -match 'soc/sdio_slave_periph\.h') {
            $c = $c -replace '#include "soc/sdio_slave_periph.h"', '#include "hal/sdio_slave_periph.h"'
            Set-Content -Path $sdioApi -Value $c -NoNewline
            Write-Host "Patched sdio_slave_api.c for IDF 6 hal include path"
        }
    }
}

function Inject-ModulusIntoHostedMirror {
    $destZig = Join-Path $SlaveDir "components\modulus_zig_c6"
    $destHookH = Join-Path $SlaveDir "main\modulus_c6_hosted_hook.h"
    $destModulusDefaults = Join-Path $SlaveDir "sdkconfig.defaults.modulus"
    $hookHSrc = Join-Path $ModulusZigC6 "include\modulus_c6_hosted_hook.h"

    Write-Host "Inject Modulus Zig component + hosted hook into mirror"
    if (Test-Path $destZig) { Remove-Item -Recurse -Force $destZig }
    robocopy $ModulusZigC6 $destZig /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Copy-Item $hookHSrc $destHookH -Force
    Copy-Item (Join-Path $ModulusHosted "sdkconfig.defaults.modulus") $destModulusDefaults -Force

    $zigbeeDefaultsSrc = Join-Path $ModulusHosted "sdkconfig.defaults.zigbee"
    $destZigbeeDefaults = Join-Path $SlaveDir "sdkconfig.defaults.zigbee"
    $zigbeePartsSrc = Join-Path $ModulusHosted "partitions_zigbee.csv"
    $destZigbeeParts = Join-Path $SlaveDir "partitions_zigbee.csv"
    if ($ZigbeeExclusive -and (Test-Path $zigbeeDefaultsSrc)) {
        Copy-Item $zigbeeDefaultsSrc $destZigbeeDefaults -Force
        Copy-Item $zigbeePartsSrc $destZigbeeParts -Force
        Write-Host "Zigbee exclusive: sdkconfig.defaults.zigbee + partitions_zigbee.csv -> slave mirror"
        # ZBOSS requires the zb_storage/zb_fct partitions. If a stale sdkconfig
        # predates the Zigbee partition table, defaults are never re-applied and
        # the broken table gets flashed again - force regeneration.
        $mirrorSdk = Join-Path $SlaveDir "sdkconfig"
        if ((Test-Path $mirrorSdk) -and
            -not (Select-String -Path $mirrorSdk -Pattern 'partitions_zigbee\.csv' -Quiet)) {
            Remove-Item $mirrorSdk -Force
            Write-Host "Stale sdkconfig without Zigbee partitions removed (will regenerate)"
        }
    } elseif (Test-Path $destZigbeeDefaults) {
        Remove-Item $destZigbeeDefaults -Force -ErrorAction SilentlyContinue
        Remove-Item $destZigbeeParts -Force -ErrorAction SilentlyContinue
    }

    $destIdfYml = Join-Path $destZig "idf_component.yml"
    $zigbeeYml = Join-Path $ModulusZigC6 "idf_component.zigbee.yml"
    if ($ZigbeeExclusive) {
        if (Test-Path $destIdfYml) {
            Remove-Item $destIdfYml -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Zigbee exclusive: esp-zigbee-lib via main/idf_component.yml (not modulus_zig_c6)"
    } elseif (Test-Path $zigbeeYml) {
        Copy-Item $zigbeeYml $destIdfYml -Force
    } elseif (Test-Path $destIdfYml) {
        Remove-Item $destIdfYml -Force -ErrorAction SilentlyContinue
    }

    $topCmake = Join-Path $SlaveDir "CMakeLists.txt"
    $top = Get-Content $topCmake -Raw
    if ($top -notmatch 'modulus_zig_c6') {
        $top = $top -replace ' bootloader main ', ' bootloader main modulus_zig_c6 '
        Set-Content -Path $topCmake -Value $top -NoNewline
        Write-Host "Patched slave CMakeLists.txt: added modulus_zig_c6 component"
    }

    $mainCmake = Join-Path $SlaveDir "main\CMakeLists.txt"
    $mc = Get-Content $mainCmake -Raw
    $mc = $mc -replace '\r?\n\t"modulus_c6_hosted_hook\.c"', ''
    $mc = $mc -replace '\r?\nlist\(APPEND COMPONENT_REQUIRES modulus_zig_c6\)', ''
    $mc = $mc -replace '\r?\nset\(COMPONENT_REQUIRES modulus_zig_c6\)', ''
    Set-Content -Path $mainCmake -Value $mc -NoNewline

    $copro = Join-Path $SlaveDir "main\esp_hosted_coprocessor.c"
    $cp = Get-Content $copro -Raw
    if ($cp -notmatch 'modulus_c6_hosted_after_init') {
        $incHook = "#include `"esp_hosted_coprocessor_fw_ver.h`"`n#include `"modulus_c6_hosted_hook.h`""
        $cp = $cp -replace '#include "esp_hosted_coprocessor_fw_ver.h"', $incHook
        $afterInit = "`${1}`n`n`tmodulus_c6_hosted_after_init();"
        $cp = $cp -replace '(\s+esp_hosted_coprocessor_init\(\);)', $afterInit
        Set-Content -Path $copro -Value $cp -NoNewline
        Write-Host "Patched esp_hosted_coprocessor.c: modulus_c6_hosted_after_init after init"
    }

    # ── ESP-NOW SDIO command handler (P4 host custom ESP_ESPNOW_IF protocol) ──
    # The upstream slave has no espnow_handler and no ESP_ESPNOW_IF routing, so
    # the host's ESPNOW_CMD_INIT/PROBE were dropped as "unknown type 8" and the
    # P4 timed out. Inject the handler + dispatch + enum into the slave mirror.
    Write-Host "Inject ESP-NOW SDIO command handler into mirror"
    Copy-Item (Join-Path $C6Dir "main\espnow_handler.c") (Join-Path $SlaveDir "main\espnow_handler.c") -Force
    Copy-Item (Join-Path $C6Dir "main\espnow_handler.h") (Join-Path $SlaveDir "main\espnow_handler.h") -Force

    $mainCmake2 = Join-Path $SlaveDir "main\CMakeLists.txt"
    $mc2 = Get-Content $mainCmake2 -Raw
    if ($mc2 -notmatch 'espnow_handler\.c') {
        $mc2 = $mc2 -replace '(set\(COMPONENT_SRCS\r?\n\t"slave_control\.c")', "`$1`r`n`t`"espnow_handler.c`""
        Set-Content -Path $mainCmake2 -Value $mc2 -NoNewline
        Write-Host "Patched slave main CMakeLists.txt: added espnow_handler.c"
    }

    $cp2 = Get-Content $copro -Raw
    if ($cp2 -notmatch 'espnow_process_host_cmd') {
        $cp2 = $cp2 -replace '(#include "slave_control.h")', "`$1`r`n#include `"espnow_handler.h`""
        $espnowBranch = "`r`n`r`n`telse if (buf_handle->if_type == ESP_ESPNOW_IF) {`r`n`t`tespnow_process_host_cmd(payload, payload_len);`r`n`t}`r`n`r`n`t/* Free buffer handle */"
        $cp2 = $cp2 -replace '\r?\n\r?\n\t/\* Free buffer handle \*/', $espnowBranch
        Set-Content -Path $copro -Value $cp2 -NoNewline
        Write-Host "Patched esp_hosted_coprocessor.c: ESP_ESPNOW_IF -> espnow_process_host_cmd"
    }

    $slaveIface = Join-Path $SlaveDir "main\common\esp_hosted_interface.h"
    if (Test-Path $slaveIface) {
        $si = Get-Content $slaveIface -Raw
        if ($si -notmatch 'ESP_ESPNOW_IF') {
            $si2 = $si -replace '(\s+ESP_ETH_IF,\r?\n)(\s+ESP_MAX_IF,)', "`$1`tESP_ESPNOW_IF,`r`n`tESP_ZIGBEE_IF,`r`n`tESP_THREAD_IF,`r`n`$2"
            if ($si -ne $si2) {
                Set-Content -Path $slaveIface -Value $si2 -NoNewline
                Write-Host "Patched slave esp_hosted_interface.h: ESP_ESPNOW_IF/ZIGBEE/THREAD enum (host-aligned)"
            }
        }
    }

    # ── Zigbee / Thread SDIO handlers (P4 ESP_ZIGBEE_IF / ESP_THREAD_IF) ──
    # Without these, P4 permit-join / hub-start RPCs are dropped on the slave.
    Write-Host "Inject Zigbee + Thread SDIO command handlers into mirror"
    foreach ($f in @("zigbee_handler.c", "zigbee_handler.h", "thread_handler.c", "thread_handler.h")) {
        Copy-Item (Join-Path $C6Dir "main\$f") (Join-Path $SlaveDir "main\$f") -Force
    }

    $mainCmake3 = Join-Path $SlaveDir "main\CMakeLists.txt"
    $mc3 = Get-Content $mainCmake3 -Raw
    if ($mc3 -notmatch 'zigbee_handler\.c') {
        $mc3 = $mc3 -replace '(\t"espnow_handler\.c")', "`$1`r`n`t`"zigbee_handler.c`"`r`n`t`"thread_handler.c`""
        Set-Content -Path $mainCmake3 -Value $mc3 -NoNewline
        Write-Host "Patched slave main CMakeLists.txt: added zigbee_handler.c + thread_handler.c"
    }

    $cp3 = Get-Content $copro -Raw
    if ($cp3 -notmatch 'zigbee_process_host_cmd') {
        if ($cp3 -notmatch 'espnow_handler\.h') {
            $cp3 = $cp3 -replace '(#include "slave_control.h")', "`$1`r`n#include `"espnow_handler.h`"`r`n#include `"zigbee_handler.h`"`r`n#include `"thread_handler.h`""
        } else {
            $cp3 = $cp3 -replace '(#include "espnow_handler.h")', "`$1`r`n#include `"zigbee_handler.h`"`r`n#include `"thread_handler.h`""
        }
        $wirelessBranch = "`r`n`telse if (buf_handle->if_type == ESP_ZIGBEE_IF) {`r`n`t`tzigbee_process_host_cmd(payload, payload_len);`r`n`t}`r`n`telse if (buf_handle->if_type == ESP_THREAD_IF) {`r`n`t`tthread_process_host_cmd(payload, payload_len);`r`n`t}`r`n`r`n`t/* Free buffer handle */"
        $cp3 = $cp3 -replace '\r?\n\r?\n\t/\* Free buffer handle \*/', $wirelessBranch
        Set-Content -Path $copro -Value $cp3 -NoNewline
        Write-Host "Patched esp_hosted_coprocessor.c: ESP_ZIGBEE_IF/ESP_THREAD_IF dispatch"
    }

    if ($ZigbeeExclusive) {
        $mainIdfYml = Join-Path $SlaveDir "main\idf_component.yml"
        Copy-Item (Join-Path $C6Dir "main\idf_component.yml") $mainIdfYml -Force
        Write-Host "Zigbee exclusive: main/idf_component.yml (esp-zigbee-lib + esp-zboss-lib)"
    }
}

function Build-ZigOnly {
    param([string]$Act, [string]$SerialPort)
    $env:SDKCONFIG_DEFAULTS = "sdkconfig.defaults"
    $env:IDF_CCACHE_ENABLE = "0"
    $env:MODULUS_REPO_ROOT = $Root
    Push-Location $C6Dir
    try {
        if ($Act -in @("set-target", "fullclean")) {
            Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path "sdkconfig") -or $Act -eq "set-target") {
            Write-Host "set-target esp32c6 (Modulus Zig-only coprocessor)"
            idf.py set-target esp32c6
        }
        switch ($Act) {
            "build" { idf.py build }
            "flash" { idf.py -p $SerialPort flash }
            "monitor" { idf.py -p $SerialPort monitor }
            "flash-monitor" { idf.py -p $SerialPort flash monitor }
            "menuconfig" { idf.py menuconfig }
            "fullclean" { idf.py fullclean }
            "set-target" { }
        }
    } finally {
        Pop-Location
    }
}

Import-IdfEnv
Test-ZigInPath

if ($ZigOnly) {
    Write-Host "Zig-only C6 build (no esp_hosted SDIO Wi-Fi)"
    Build-ZigOnly -Act $Action -SerialPort $Port
    Write-Host ""
    Write-Host "NOTE: Zig-only image - NOT network_adapter. Production: omit -ZigOnly."
    exit 0
}

Ensure-EspHostedSlave
Inject-ModulusIntoHostedMirror

$env:MODULUS_REPO_ROOT = $Root
$defaults = "sdkconfig.defaults;sdkconfig.defaults.esp32c6;sdkconfig.defaults.modulus"
if ($ZigbeeExclusive) {
    $defaults += ";sdkconfig.defaults.zigbee"
    Write-Host "Zigbee exclusive build: Thread off, esp-zigbee-lib (802.15.4)"
}
$env:SDKCONFIG_DEFAULTS = $defaults
$env:IDF_CCACHE_ENABLE = "0"

Push-Location $SlaveDir
try {
    if ($Action -in @("set-target", "fullclean")) {
        Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path "sdkconfig") -or $Action -eq "set-target") {
        Write-Host "set-target esp32c6 (esp_hosted 2.11.x + Modulus Zig Phase 8c)"
        idf.py set-target esp32c6
    }
    switch ($Action) {
        "build" {
            idf.py build
            if ($LASTEXITCODE -ne 0) { throw "idf.py build failed with exit $LASTEXITCODE" }
        }
        "flash" {
            if (-not (Test-Path (Join-Path $SlaveDir "build\network_adapter.bin"))) {
                Write-Host "C6 build missing - building before flash"
                idf.py build
                if ($LASTEXITCODE -ne 0) { throw "idf.py build failed with exit $LASTEXITCODE" }
            }
            if ($Force) {
                $bld = Join-Path $SlaveDir "build"
                Get-ChildItem $bld -Recurse -Filter "*_flashed.bin" -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Host "Force flash: esptool write-flash (no incremental diff) on $Port"
                Push-Location $bld
                try {
                    python -m esptool --chip esp32c6 -p $Port -b 460800 `
                        --before default-reset --after hard-reset write-flash `
                        --flash-mode dio --flash-freq 80m --flash-size 4MB `
                        0x0 bootloader/bootloader.bin `
                        0x8000 partition_table/partition-table.bin `
                        0xd000 ota_data_initial.bin `
                        0x10000 network_adapter.bin
                    if ($LASTEXITCODE -ne 0) { throw "esptool flash failed with exit $LASTEXITCODE" }
                } finally {
                    Pop-Location
                }
            } else {
                idf.py -p $Port flash
            }
        }
        "monitor" { idf.py -p $Port monitor }
        "flash-monitor" { idf.py -p $Port flash monitor }
        "menuconfig" { idf.py menuconfig }
        "fullclean" { idf.py fullclean }
        "set-target" { }
    }
} finally {
    Pop-Location
    Remove-Item Env:SDKCONFIG_DEFAULTS -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Phase 8c combined C6: esp_hosted SDIO slave + Modulus Zig task."
Write-Host "  Hosted-only rollback: .\scripts\build_tab5_c6.ps1 -Action flash -Port $Port"
Write-Host "  Zig-only dev: .\scripts\build_tab5_c6_modulus.ps1 -ZigOnly"
Write-Host "  Zigbee device pairing: .\scripts\build_tab5_c6_modulus.ps1 -ZigbeeExclusive -Action flash -Port $Port"
