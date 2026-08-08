# sessionStart: inject Modulus Convert to ZIG pipeline context
$ErrorActionPreference = 'SilentlyContinue'
[void][Console]::In.ReadToEnd()

$lines = @(
    'Modulus Convert to ZIG — agent pipeline active.'
    'Read MEMORY.md before large edits.'
    'Tool order: CBM graph -> Token Savior symbols -> targeted Read -> RTK shell -> Ruflo memory/swarm.'
    'Project Ruflo DB: .swarm/memory.db (MCP cwd must be this repo).'
    'Evolver: memory/evolution/ — needs git commits for session-end recording.'
    '3+ file work: delegate via Task or Ruflo swarm_init.'
)

$gitOk = $false
try {
    $null = git -C (Get-Location) rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) {
        $commits = git -C (Get-Location) rev-list --count HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or [int]$commits -eq 0) {
            $lines += 'WARN: git has no commits — Evolver session-end memory inactive until first commit.'
        } else {
            $gitOk = $true
        }
    }
} catch {}

if (-not $gitOk) {
    $lines += 'WARN: not a git repo or no HEAD — run git init && first commit for Evolver.'
}

@{ additional_context = ($lines -join ' ') } | ConvertTo-Json -Compress
exit 0
