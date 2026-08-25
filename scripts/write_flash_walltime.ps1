# Stamp host local date/time into flash_walltime.h for Tab5 RTC apply-on-boot.
param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
}

$now = Get-Date
$epoch = [DateTimeOffset]::Now.ToUnixTimeSeconds()
if ($epoch -lt 0) { $epoch = 0 }
if ($epoch -gt [uint32]::MaxValue) { $epoch = [uint32]::MaxValue }

$out = Join-Path $RepoRoot "firmware\tab5\components\modulus_zig\include\flash_walltime.h"
$body = @"
#pragma once
/* Generated $($now.ToString('yyyy-MM-dd HH:mm:ss')) local — do not hand-edit. */
#define MODULUS_FLASH_WALL_ID ${epoch}u
#define MODULUS_FLASH_WALL_YEAR $($now.Year)
#define MODULUS_FLASH_WALL_MON $($now.Month)
#define MODULUS_FLASH_WALL_DAY $($now.Day)
#define MODULUS_FLASH_WALL_HOUR $($now.Hour)
#define MODULUS_FLASH_WALL_MIN $($now.Minute)
#define MODULUS_FLASH_WALL_SEC $($now.Second)
"@
[System.IO.File]::WriteAllText($out, $body)

Write-Host ("==> flash walltime {0:yyyy-MM-dd HH:mm:ss} (id={1}) -> RTC on next boot" -f $now, $epoch)
