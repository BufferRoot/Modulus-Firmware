@echo off
set "IDF_PATH=C:\Espressif\frameworks\esp-idf-v6.0.1"
set "IDF_TOOLS_PATH=C:\Espressif"
set "IDF_PYTHON_ENV_PATH=C:\Espressif\python_env\idf6.0_py3.11_env"
set "PATH=C:\Espressif\python_env\idf6.0_py3.11_env\Scripts;C:\Espressif\tools\idf-git\2.44.0\cmd;%PATH%"
cd /d "C:\Users\BEAST MODE\Desktop\Modulus Convert to ZIG\firmware\tab5"
"C:\Espressif\python_env\idf6.0_py3.11_env\Scripts\python.exe" "%IDF_PATH%\tools\idf.py" build
