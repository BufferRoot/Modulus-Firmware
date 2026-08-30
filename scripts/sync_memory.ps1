# Sync Modulus engineering memory into the private knowledge repo + OneDrive.
#
# MEMORY.md, CLAUDE.md, memory/ and docs/ are .gitignored in the main repo on
# purpose (commit 839b520 kept agent tooling out of the published tree). That
# leaves the session rationale living only on this disk. This script mirrors it
# to a separate private git repo and takes a dated snapshot in OneDrive.
#
#   .\scripts\sync_memory.ps1                 # sync + commit
#   .\scripts\sync_memory.ps1 -Message "..."  # custom commit message
#   .\scripts\sync_memory.ps1 -NoSnapshot     # skip the OneDrive copy

param(
    [string]$KnowledgeRepo = "$env:USERPROFILE\Desktop\Modulus-Knowledge",
    [string]$SnapshotRoot  = "$env:USERPROFILE\OneDrive\Modulus-Knowledge-Snapshots",
    [string]$Message       = "",
    [switch]$NoSnapshot
)

$ErrorActionPreference = "Stop"
$src = Split-Path -Parent $PSScriptRoot

# What carries knowledge. Keep this list in sync with .gitignore lines 43-46.
# NOT README.md — that is the firmware readme, already tracked and public.
$items = @("MEMORY.md", "CLAUDE.md", "memory", "docs")

if (-not (Test-Path $KnowledgeRepo)) {
    New-Item -ItemType Directory -Force -Path $KnowledgeRepo | Out-Null
    Push-Location $KnowledgeRepo
    git init -q
    git branch -M main
    Pop-Location
    Write-Host "==> initialised $KnowledgeRepo"
}

foreach ($i in $items) {
    $from = Join-Path $src $i
    if (-not (Test-Path $from)) { continue }
    $to = Join-Path $KnowledgeRepo $i
    if (Test-Path $from -PathType Container) {
        # Mirror so deletions propagate; /NJH /NJS /NP keep the log readable.
        robocopy $from $to /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Error "robocopy failed for $i ($LASTEXITCODE)" }
    } else {
        Copy-Item $from $to -Force
    }
    Write-Host "==> synced $i"
}

# Record which firmware commit the notes describe — the two repos drift
# otherwise, and stale notes are worse than none.
Push-Location $src
$sha = (git rev-parse --short HEAD 2>$null)
$subject = (git log -1 --pretty=%s 2>$null)
Pop-Location
if ($sha) {
    @(
        "# Source revision",
        "",
        "These notes describe the main Modulus firmware repo at:",
        "",
        "    $sha  $subject",
        "",
        "Synced $(Get-Date -Format 'yyyy-MM-dd HH:mm')."
    ) | Set-Content (Join-Path $KnowledgeRepo "SOURCE_REV.md")
}

Push-Location $KnowledgeRepo
git add -A
$pending = git status --porcelain
if ($pending) {
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "Sync memory from firmware $sha ($(Get-Date -Format 'yyyy-MM-dd'))"
    }
    git commit -q -m $Message
    Write-Host "==> committed: $Message"
} else {
    Write-Host "==> no changes to commit"
}
$remote = git remote 2>$null
if (-not $remote) {
    Write-Host "==> NOTE: no git remote set. This is still local-only."
    Write-Host "    git -C `"$KnowledgeRepo`" remote add origin <private-url>"
    Write-Host "    git -C `"$KnowledgeRepo`" push -u origin main"
}
Pop-Location

if (-not $NoSnapshot) {
    if (Test-Path (Split-Path $SnapshotRoot -Parent)) {
        $stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
        $dest = Join-Path $SnapshotRoot $stamp
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($i in $items) {
            $from = Join-Path $src $i
            if (Test-Path $from) { Copy-Item $from $dest -Recurse -Force }
        }
        Write-Host "==> snapshot: $dest"
        # Keep the last 20; these are small text trees.
        Get-ChildItem $SnapshotRoot -Directory | Sort-Object Name -Descending |
            Select-Object -Skip 20 | Remove-Item -Recurse -Force
    } else {
        Write-Host "==> OneDrive not found at $SnapshotRoot — snapshot skipped"
    }
}
