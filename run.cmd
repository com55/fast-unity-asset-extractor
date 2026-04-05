@echo off
setlocal EnableExtensions EnableDelayedExpansion

call :main %*
set "RUN_EXIT=%ERRORLEVEL%"
if not "!RUN_EXIT!"=="0" (
    echo.
    echo [run] Script failed with exit code !RUN_EXIT!
    echo Press any key to exit . . .
    pause >nul
)
exit /b %RUN_EXIT%

:main

rem ====================
rem Project configuration
rem ====================
set "CFG_ENTRY_SCRIPT=asset_extracter.py"
set "CFG_REQUIREMENTS_FILE=requirements.txt"
set "CFG_VENV_DIR=.venv"
set "CFG_CACHE_FILE=.run-cache.json"
set "CFG_MIN_PY=3.7"
set "CFG_PREFERRED_UV_PYTHON=3.11"
set "CFG_ENABLE_CACHE=1"
set "CFG_AUTO_INSTALL_UV=1"

set "PROJECT_ROOT=%~dp0"
if not defined PROJECT_ROOT set "PROJECT_ROOT=%CD%\"

set "ENTRY_SCRIPT=%PROJECT_ROOT%%CFG_ENTRY_SCRIPT%"
set "REQUIREMENTS_FILE=%PROJECT_ROOT%%CFG_REQUIREMENTS_FILE%"
set "CACHE_FILE=%PROJECT_ROOT%%CFG_CACHE_FILE%"
set "VENV_DIR=%PROJECT_ROOT%%CFG_VENV_DIR%"
set "VENV_PYTHON=%VENV_DIR%\Scripts\python.exe"
set "RUN_USER_ARGS=%*"
set "PREFERRED_UV_PYTHON=%CFG_PREFERRED_UV_PYTHON%"

for /f "tokens=1,2 delims=." %%A in ("%CFG_MIN_PY%") do (
    set "MIN_PY_MAJOR=%%A"
    set "MIN_PY_MINOR=%%B"
)
if not defined MIN_PY_MAJOR set "MIN_PY_MAJOR=3"
if not defined MIN_PY_MINOR set "MIN_PY_MINOR=7"
if /I not "%CFG_ENABLE_CACHE%"=="1" set "CFG_ENABLE_CACHE=0"
if /I not "%CFG_AUTO_INSTALL_UV%"=="1" set "CFG_AUTO_INSTALL_UV=0"

if not exist "%ENTRY_SCRIPT%" (
    echo [run] Entry script not found: "%ENTRY_SCRIPT%"
    exit /b 1
)

if not exist "%REQUIREMENTS_FILE%" (
    echo [run] requirements.txt not found: "%REQUIREMENTS_FILE%"
    exit /b 1
)

if "%CFG_ENABLE_CACHE%"=="1" (
    if not exist "%CACHE_FILE%" (
        >"%CACHE_FILE%" echo {}
    )
    call :get_requirements_hash "%REQUIREMENTS_FILE%" REQ_HASH
    if errorlevel 1 exit /b 1
) else (
    set "REQ_HASH=cache-disabled"
)

rem 1) Prefer existing .venv first.
if exist "%VENV_PYTHON%" (
    call :check_python_version "%VENV_PYTHON%" VENV_OK VENV_VERSION
    if "!VENV_OK!"=="1" (
        set "VF=venv|%VENV_PYTHON%|!VENV_VERSION!|%REQ_HASH%"
        call :is_cache_hit "venv" "!VF!" CACHE_HIT
        if "!CACHE_HIT!"=="1" (
            echo [run] Cache hit for existing .venv, verifying requirements
        )

        echo [run] Checking requirements in existing .venv
        call :requirements_satisfied "%VENV_PYTHON%" "%REQUIREMENTS_FILE%" VENV_REQ_OK
        if "!VENV_REQ_OK!"=="1" (
            call :save_cache "venv" "!VF!"
            call :run_python "%VENV_PYTHON%"
            exit /b !errorlevel!
        )

        echo [run] Existing .venv found but requirements differ, installing requirements
        call :install_requirements "%VENV_PYTHON%" "%REQUIREMENTS_FILE%"
        if errorlevel 1 (
            echo [run] Failed to update existing .venv, continuing with other runtime checks
        ) else (
            call :save_cache "venv" "!VF!"
            call :run_python "%VENV_PYTHON%"
            exit /b !errorlevel!
        )
    ) else (
        echo [run] Existing .venv python version ^(!VENV_VERSION!^) is lower than %MIN_PY_MAJOR%.%MIN_PY_MINOR%
    )
)

call :find_python PY_EXE
if defined PY_EXE (
    call :check_python_version "%PY_EXE%" PY_OK PY_VERSION

    rem 2) Use system python directly when version and requirements match.
    if "!PY_OK!"=="1" (
        set "PF=python|%PY_EXE%|!PY_VERSION!|%REQ_HASH%"
        call :is_cache_hit "python" "!PF!" CACHE_HIT
        if "!CACHE_HIT!"=="1" (
            echo [run] Cache hit for system python, verifying requirements
        )

        echo [run] Checking installed requirements on system python !PY_VERSION!
        call :requirements_satisfied "%PY_EXE%" "%REQUIREMENTS_FILE%" PY_REQ_OK
        if "!PY_REQ_OK!"=="1" (
            call :save_cache "python" "!PF!"
            call :run_python "%PY_EXE%"
            exit /b !errorlevel!
        )

        echo [run] System python version is OK but requirements differ, creating/updating .venv
        call :ensure_venv_from_python "%PY_EXE%" "%VENV_DIR%" "%REQUIREMENTS_FILE%"
        if errorlevel 1 exit /b 1
        call :get_python_version "%VENV_PYTHON%" VENV_VERSION
        if errorlevel 1 exit /b 1
        set "VF=venv|%VENV_PYTHON%|!VENV_VERSION!|%REQ_HASH%"
        call :save_cache "venv" "!VF!"
        call :run_python "%VENV_PYTHON%"
        exit /b !errorlevel!
    )

    rem 3) Python exists but version is not aligned.
    echo [run] Python found ^(!PY_VERSION!^) but version is lower than %MIN_PY_MAJOR%.%MIN_PY_MINOR%
    call :find_uv UV_EXE
    if defined UV_EXE (
        rem 3.1) uv exists -> use uv to create venv with preferred python version.
        echo [run] uv is available, creating .venv using uv python %PREFERRED_UV_PYTHON%
        call :ensure_venv_from_uv "!UV_EXE!" "%VENV_DIR%" "%REQUIREMENTS_FILE%"
        if errorlevel 1 (
            echo [run] uv venv setup failed, falling back to system python venv
            call :ensure_venv_from_python "%PY_EXE%" "%VENV_DIR%" "%REQUIREMENTS_FILE%"
            if errorlevel 1 exit /b 1
        )
    ) else (
        rem 3.2) uv missing -> use installed python to create venv and install required deps.
        echo [run] uv not found, creating .venv using installed python
        call :ensure_venv_from_python "%PY_EXE%" "%VENV_DIR%" "%REQUIREMENTS_FILE%"
        if errorlevel 1 exit /b 1
    )

    call :get_python_version "%VENV_PYTHON%" VENV_VERSION
    if errorlevel 1 exit /b 1
    set "VF=venv|%VENV_PYTHON%|!VENV_VERSION!|%REQ_HASH%"
    call :save_cache "venv" "!VF!"
    call :run_python "%VENV_PYTHON%"
    exit /b !errorlevel!
)

rem 4) No python available -> install/check uv and run with uv.
echo [run] Python command not found, using uv fallback
call :ensure_uv UV_EXE
if errorlevel 1 exit /b 1

set "UF=uv|%UV_EXE%|%REQ_HASH%|%PREFERRED_UV_PYTHON%"
call :is_cache_hit "uv" "!UF!" CACHE_HIT
if "!CACHE_HIT!"=="1" (
    echo [run] Cache hit: using uv
) else (
    call :save_cache "uv" "!UF!"
)

pushd "%PROJECT_ROOT%"
echo [run] Running "%ENTRY_SCRIPT%" with uv python %PREFERRED_UV_PYTHON% %*
"%UV_EXE%" run --python %PREFERRED_UV_PYTHON% --with-requirements "%REQUIREMENTS_FILE%" "%ENTRY_SCRIPT%" %*
set "RUN_EXIT=%ERRORLEVEL%"
popd
exit /b %RUN_EXIT%

:find_python
set "%~1="
for /f "delims=" %%P in ('where python 2^>nul') do (
    if not defined %~1 set "%~1=%%P"
)
exit /b 0

:find_uv
set "%~1="
for /f "delims=" %%U in ('where uv 2^>nul') do (
    if not defined %~1 set "%~1=%%U"
)
exit /b 0

:check_python_version
set "%~2=0"
set "%~3="
set "PY_VER="
for /f "tokens=2 delims= " %%V in ('"%~1" --version 2^>^&1') do set "PY_VER=%%V"
if not defined PY_VER exit /b 0

set "MAJOR="
set "MINOR="
for /f "tokens=1,2 delims=." %%A in ("%PY_VER%") do (
    set "MAJOR=%%A"
    set "MINOR=%%B"
)
if not defined MAJOR exit /b 0
if not defined MINOR exit /b 0

set "MAJOR_NUM=0"
set "MINOR_NUM=0"
set /a MAJOR_NUM=%MAJOR% >nul 2>nul
if errorlevel 1 exit /b 0
set /a MINOR_NUM=%MINOR% >nul 2>nul
if errorlevel 1 exit /b 0

if %MAJOR_NUM% GTR %MIN_PY_MAJOR% (
    set "%~2=1"
) else if %MAJOR_NUM% EQU %MIN_PY_MAJOR% if %MINOR_NUM% GEQ %MIN_PY_MINOR% (
    set "%~2=1"
)
set "%~3=%PY_VER%"
exit /b 0

:get_python_version
set "%~2="
set "LOCAL_PY_VER="
for /f "tokens=2 delims= " %%V in ('"%~1" --version 2^>^&1') do set "LOCAL_PY_VER=%%V"
if not defined LOCAL_PY_VER exit /b 1
set "%~2=%LOCAL_PY_VER%"
exit /b 0

:get_requirements_hash
set "%~2="
set "RUN_REQ_PATH=%~1"
for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "$p=$env:RUN_REQ_PATH; try { if(-not $p){ exit 1 }; (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash } catch { exit 1 }"`) do (
    set "%~2=%%H"
)
if not defined %~2 (
    echo [run] Failed to hash requirements file.
    exit /b 1
)
exit /b 0

:requirements_satisfied
set "%~3=0"
set "RUN_REQ_PY=%~1"
set "RUN_REQ_FILE=%~2"
set "REQ_CHECK_RESULT="
for /f "usebackq delims=" %%R in (`powershell -NoProfile -Command "$py=$env:RUN_REQ_PY;$req=$env:RUN_REQ_FILE; if(-not $py -or -not $req){ '0'; exit }; $ok=$true; foreach($raw in Get-Content -LiteralPath $req){ $line=$raw.Trim(); if(-not $line -or $line.StartsWith('#')){ continue }; if($line -match '^([^=\s]+)\s*==\s*([^\s]+)$'){ $name=$matches[1]; $want=$matches[2]; $got=& $py -c 'import importlib.metadata as m,sys;print(m.version(sys.argv[1]))' $name 2^> $null; if($LASTEXITCODE -ne 0){ $ok=$false; break }; if((($got -join '')).Trim() -ne $want){ $ok=$false; break } } elseif($line -match '^([^=\s]+)$'){ $name=$matches[1]; & $py -c 'import importlib.metadata as m,sys;print(m.version(sys.argv[1]))' $name 2^> $null 1^> $null; if($LASTEXITCODE -ne 0){ $ok=$false; break } } else { $ok=$false; break } }; if($ok){ '1' } else { '0' }" 2^>nul`) do (
    set "REQ_CHECK_RESULT=%%R"
)
if "%REQ_CHECK_RESULT%"=="1" set "%~3=1"
exit /b 0

:install_requirements
echo [run] Installing requirements with "%~1"
call :is_uv_managed_python "%~1" UV_MANAGED
if "%UV_MANAGED%"=="1" (
    call :ensure_uv UV_EXE
    if errorlevel 1 exit /b 1
    if not defined UV_EXE (
        echo [run] uv is required for this virtual environment but was not found.
        exit /b 1
    )
    pushd "%PROJECT_ROOT%"
    "!UV_EXE!" pip install -r "%~2"
    set "UV_PIP_EXIT=!ERRORLEVEL!"
    popd
    if not "!UV_PIP_EXIT!"=="0" (
        echo [run] uv pip install -r failed, retrying with explicit python target
        "!UV_EXE!" pip install --python "%~1" -r "%~2"
        exit /b !ERRORLEVEL!
    )
    exit /b 0
)

call :ensure_pip "%~1"
if errorlevel 1 exit /b 1
"%~1" -m pip --disable-pip-version-check install -r "%~2"
exit /b %ERRORLEVEL%

:is_uv_managed_python
set "%~2=0"
set "PY_DIR="
set "VENV_ROOT="
set "CFG_PATH="
for %%I in ("%~1") do set "PY_DIR=%%~dpI"
if not defined PY_DIR exit /b 0
for %%J in ("%PY_DIR%..") do set "VENV_ROOT=%%~fJ"
if not defined VENV_ROOT exit /b 0
set "CFG_PATH=%VENV_ROOT%\pyvenv.cfg"
if not exist "%CFG_PATH%" exit /b 0

findstr /R /I /C:"^[ ]*uv[ ]*=" "%CFG_PATH%" >nul 2>nul
if not errorlevel 1 set "%~2=1"
exit /b 0

:ensure_pip
"%~1" -m pip --version >nul 2>nul
if not errorlevel 1 exit /b 0

echo [run] pip not found, trying ensurepip for "%~1"
"%~1" -m ensurepip --upgrade >nul 2>nul
if errorlevel 1 (
    echo [run] Failed to bootstrap pip for "%~1"
    exit /b 1
)

"%~1" -m pip --version >nul 2>nul
if errorlevel 1 (
    echo [run] pip is still unavailable for "%~1"
    exit /b 1
)
exit /b 0

:ensure_venv_from_python
if not exist "%~2\Scripts\python.exe" (
    echo [run] Creating venv at "%~2"
    "%~1" -m venv "%~2"
    if errorlevel 1 exit /b 1
)
call :install_requirements "%~2\Scripts\python.exe" "%~3"
exit /b %ERRORLEVEL%

:ensure_venv_from_uv
echo [run] Creating venv at "%~2" with uv
pushd "%PROJECT_ROOT%"
"%~1" venv --python %PREFERRED_UV_PYTHON% "%~2"
set "UV_VENV_EXIT=%ERRORLEVEL%"
popd
if not "%UV_VENV_EXIT%"=="0" exit /b 1
call :install_requirements "%~2\Scripts\python.exe" "%~3"
exit /b %ERRORLEVEL%

:ensure_uv
call :find_uv %~1
if defined %~1 exit /b 0

if "%CFG_AUTO_INSTALL_UV%"=="0" (
    echo [run] uv not found and CFG_AUTO_INSTALL_UV=0
    exit /b 1
)

echo [run] uv not found, attempting to install with official installer
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 ^| iex"
if errorlevel 1 (
    echo [run] Failed to install uv using official installer.
    exit /b 1
)

call :find_uv %~1
if not defined %~1 (
    echo [run] uv was installed but command is not in PATH yet. Open a new terminal and run again.
    exit /b 1
)
exit /b 0

:is_cache_hit
set "%~3=0"
if "%CFG_ENABLE_CACHE%"=="0" exit /b 0
set "CACHE_MATCH="
set "RUN_CACHE_MODE=%~1"
set "RUN_CACHE_FP=%~2"
set "RUN_CACHE_FILE=%CACHE_FILE%"
for /f "usebackq delims=" %%C in (`powershell -NoProfile -Command "$cache=$env:RUN_CACHE_FILE;$mode=$env:RUN_CACHE_MODE;$fp=$env:RUN_CACHE_FP; if(-not $cache){ '0'; exit }; if(-not (Test-Path -LiteralPath $cache)){ '0'; exit }; try { $obj=Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json } catch { '0'; exit }; if($obj.mode -eq $mode -and $obj.fingerprint -eq $fp){ '1' } else { '0' }"`) do (
    set "CACHE_MATCH=%%C"
)
if "%CACHE_MATCH%"=="1" set "%~3=1"
exit /b 0

:save_cache
if "%CFG_ENABLE_CACHE%"=="0" exit /b 0
set "RUN_CACHE_MODE=%~1"
set "RUN_CACHE_FP=%~2"
set "RUN_CACHE_FILE=%CACHE_FILE%"
powershell -NoProfile -Command "$cache=$env:RUN_CACHE_FILE;$mode=$env:RUN_CACHE_MODE;$fp=$env:RUN_CACHE_FP; if(-not $cache){ exit 1 }; $obj=@{mode=$mode; fingerprint=$fp; updatedAt=(Get-Date).ToString('o')}; $json=ConvertTo-Json -InputObject $obj; Set-Content -LiteralPath $cache -Value $json -Encoding UTF8"
exit /b 0

:run_python
set "RUN_PY=%~1"
pushd "%PROJECT_ROOT%"
echo [run] Running "%ENTRY_SCRIPT%" with "%RUN_PY%" %RUN_USER_ARGS%
"%RUN_PY%" "%ENTRY_SCRIPT%" %RUN_USER_ARGS%
set "RUN_EXIT=%ERRORLEVEL%"
popd
exit /b %RUN_EXIT%