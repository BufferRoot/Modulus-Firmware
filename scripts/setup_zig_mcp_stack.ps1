# Lean Zig MCP stack (zig-mcp + zigars) and C++ reference skills refresh.
# Usage:
#   .\scripts\setup_zig_mcp_stack.ps1
#   .\scripts\setup_zig_mcp_stack.ps1 -SkillsOnly
#   .\scripts\setup_zig_mcp_stack.ps1 -PrefetchNpm

param(
    [switch] $SkillsOnly,
    [switch] $PrefetchNpm,
    [switch] $Help
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$SkillsRoot = Join-Path $RepoRoot ".agents\skills"

function Show-Help {
    Write-Host @"
setup_zig_mcp_stack.ps1 — zig-mcp + zigars MCP + C++ reference skills

  -SkillsOnly     Refresh cpp-pro / modern-c-programming only
  -PrefetchNpm    npx cache warm for @zigars/mcp@0.2.0

Active MCP servers: zig-mcp (ZLS, build, test) + zigars (structured diagnostics).
Reload Cursor after .cursor/mcp.json changes.
See .agents/skills/zig-build/SKILL.md for zig-mcp + ZLS build.
"@
}

if ($Help) {
    Show-Help
    exit 0
}

function Require-Command($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required command not found on PATH: $name"
    }
}

function Install-SkillFromGit {
    param(
        [string] $Label,
        [string] $RepoUrl,
        [string] $SourceSubPath,
        [string] $DestDir
    )
    $tmpdir = Join-Path $env:TEMP "modulus-skill-$Label"
    if (Test-Path $tmpdir) {
        Remove-Item -Recurse -Force $tmpdir
    }
    New-Item -ItemType Directory -Path $tmpdir | Out-Null
    if ($SourceSubPath) {
        git clone --depth 1 --filter=blob:none --sparse $RepoUrl "$tmpdir\repo" | Out-Null
        Push-Location "$tmpdir\repo"
        git sparse-checkout set $SourceSubPath | Out-Null
        Pop-Location
        $src = Join-Path "$tmpdir\repo" $SourceSubPath
    } else {
        git clone --depth 1 $RepoUrl "$tmpdir\repo" | Out-Null
        $src = "$tmpdir\repo"
    }
    if (Test-Path $DestDir) {
        Remove-Item -Recurse -Force $DestDir
    }
    Copy-Item -Recurse $src $DestDir
    $nestedGit = Join-Path $DestDir ".git"
    if (Test-Path $nestedGit) {
        Remove-Item -Recurse -Force $nestedGit
    }
    Write-Host "Installed skill: $Label -> $DestDir"
}

Write-Host "Modulus Zig MCP stack setup (lean: zig-mcp + zigars)"
Require-Command git

Install-SkillFromGit -Label "cpp-pro" `
    -RepoUrl "https://github.com/Jeffallan/claude-skills.git" `
    -SourceSubPath "skills/cpp-pro" `
    -DestDir (Join-Path $SkillsRoot "cpp-pro")

Install-SkillFromGit -Label "modern-c-programming" `
    -RepoUrl "https://github.com/ElCapor/cpp-pro.git" `
    -SourceSubPath "" `
    -DestDir (Join-Path $SkillsRoot "modern-c-programming")

$modernSkill = Join-Path $SkillsRoot "modern-c-programming\SKILL.md"
if (Test-Path $modernSkill) {
    $content = Get-Content $modernSkill -Raw
    if ($content -match '^---\s*\r?\nname:\s*cpp-pro') {
        $content = $content -replace '(?s)^---\s*\r?\nname:\s*cpp-pro.*?---\s*\r?\n', @'
---
name: modern-c-programming
description: >-
  Modern C++ (C++11–C++23) for systems, embedded, and porting reference code to Zig.
  RAII, smart pointers, STL, templates, concurrency, Google style, debugging, and profiling.
  Use when reading or refactoring C++ reference firmware, ESP-IDF C++ shims, or porting
  patterns to Zig. Prefer CMake/ESP-IDF in this repo; use xmake guidance only when asked.
license: MIT
metadata:
  author: https://github.com/ElCapor/cpp-pro
  version: "1.0.0"
  domain: language
  source: https://mcpmarket.com/tools/skills/modern-c-programming
---

'@
        Set-Content -Path $modernSkill -Value $content -NoNewline
        Write-Host "Patched modern-c-programming SKILL.md frontmatter"
    }
}

if ($SkillsOnly) {
    Write-Host "Skills refreshed. Done."
    exit 0
}

if ($PrefetchNpm) {
    Require-Command npx
    Write-Host "Prefetching @zigars/mcp..."
    npx -y @zigars/mcp@0.2.0 --version
}

Write-Host @"

Next:
  1. Build zig-mcp + ZLS if needed (see .agents/skills/zig-build/SKILL.md)
  2. Reload Cursor window

MCP: zig-mcp (primary) + zigars (structured evidence)
Skills: cpp-pro, modern-c-programming
"@
