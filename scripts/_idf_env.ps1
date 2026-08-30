# Shared ESP-IDF python-env pin. Dot-source before calling export.ps1.
#
# export.ps1 picks its venv from whichever `python` resolves first on PATH.
# On a box with Python 3.15 installed that lands on an env where IDF 6's
# pinned tree_sitter / bitarray have no wheels and cannot build from source,
# so activation dies at "Checking python dependencies ... FAILED".
# Pin the env idf_tools built against a supported interpreter instead.

function Set-IdfPythonEnv {
    if (-not [string]::IsNullOrWhiteSpace($env:IDF_PYTHON_ENV_PATH)) { return }
    $envRoot = Join-Path $env:USERPROFILE ".espressif\python_env"
    $pinned = Get-ChildItem -Path $envRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '_py3\.(9|10|11|12)_env$' -and
            (Test-Path (Join-Path $_.FullName "Scripts\python.exe"))
        } |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($pinned) {
        $env:IDF_PYTHON_ENV_PATH = $pinned.FullName
        Write-Host "==> IDF_PYTHON_ENV_PATH: $env:IDF_PYTHON_ENV_PATH"
    } else {
        Write-Warning "No py3.9-3.12 IDF venv under $envRoot - export.ps1 may pick a broken one. Fix: python C:\Espressif\tools\idf-python\<ver>\python.exe `$env:IDF_PATH\tools\idf_tools.py install-python-env"
    }
    # idf.py warns and emits mojibake on a non-UTF8 console.
    if ([string]::IsNullOrWhiteSpace($env:PYTHONUTF8)) { $env:PYTHONUTF8 = "1" }
}
