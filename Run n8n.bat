@echo off
setlocal ENABLEDELAYEDEXPANSION

REM ======== CONFIG ========
set "COMPOSE_FILE=C:\Users\ers51\self-hosted-ai-starter-kit\docker-compose.yml"
set "UPDATE_SCRIPT=C:\Users\ers51\self-hosted-ai-starter-kit\update-n8n-url-auto.ps1"
set "DOCKER_DESKTOP_EXE=C:\Program Files\Docker\Docker\Docker Desktop.exe"
set "CLOUDflared_SERVICE=cloudflared-quick"
set "OPEN_ON_ENTER=1"
REM =========================

echo.
echo [0/5] Checking Docker CLI...
where docker >nul 2>nul
if errorlevel 1 (
  echo ❌ docker CLI not found in PATH. Make sure Docker Desktop is installed.
  pause
  exit /b 1
)

echo.
echo [1/5] Checking Docker Desktop process...
tasklist /FI "IMAGENAME eq Docker Desktop.exe" | find /I "Docker Desktop.exe" >nul
if errorlevel 1 (
  echo   - Docker Desktop is NOT running. Launching...
  if not exist "%DOCKER_DESKTOP_EXE%" (
    echo ❌ Docker Desktop not found at:
    echo    "%DOCKER_DESKTOP_EXE%"
    echo    Please adjust DOCKER_DESKTOP_EXE path in this .bat
    pause
    exit /b 1
  )
  start "" "%DOCKER_DESKTOP_EXE%"
) else (
  echo   - Docker Desktop is running.
)

echo.
echo [2/5] Waiting for Docker Engine to be ready...
set /a _retries=120
:wait_engine
docker info >nul 2>nul
if errorlevel 1 (
  set /a _retries-=1
  if !_retries! LEQ 0 (
    echo ❌ Timed out waiting for Docker Engine.
    pause
    exit /b 1
  )
  >nul ping -n 3 127.0.0.1
  goto :wait_engine
)
echo   - Docker Engine is ready.

echo.
echo [3/5] Starting containers with compose...
docker compose -f "%COMPOSE_FILE%" up -d
if errorlevel 1 (
  echo ❌ docker compose up failed.
  pause
  exit /b 1
)

echo.
echo [4/5] Running update script (updates WEBHOOK_URL and restarts n8n)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%UPDATE_SCRIPT%"
if errorlevel 1 (
  echo ❌ update script failed.
  pause
  exit /b 1
)

REM Read WEBHOOK_URL from compose file
set "N8N_URL="
for /f "usebackq tokens=1,2 delims==" %%A in (`findstr /C:"WEBHOOK_URL=" "%COMPOSE_FILE%"`) do (
  set "key=%%A"
  set "val=%%B"
  if /I "!key!"=="      - WEBHOOK_URL" set "N8N_URL=!val!"
  if /I "!key!"=="- WEBHOOK_URL" set "N8N_URL=!val!"
  if /I "!key!"=="WEBHOOK_URL" set "N8N_URL=!val!"
)
REM Trim quotes/spaces
set "N8N_URL=%N8N_URL: =%"
set "N8N_URL=%N8N_URL:"=%"

echo.
echo [5/5] Press ENTER to open n8n in your browser...
if "%OPEN_ON_ENTER%"=="1" (
  pause >nul
)

REM if not defined N8N_URL (
REM REM REM   echo ⚠ Could not detect WEBHOOK_URL from compose file.
REM REM   echo   You can open n8n manually if you know the URL.
REM   pause
REM   exit /b 0
REM )

REM echo Opening %N8N_URL% ...
REM start "" "%N8N_URL%"
start http://localhost:56789/home/workflows
endlocal
