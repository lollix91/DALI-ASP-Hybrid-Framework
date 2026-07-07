@echo off
setlocal enabledelayedexpansion
cls
title "Hybrid ASP/L-DINF Scheduling MAS"

:: ============================================================
:: DALI-ASP Hybrid Framework - Multi-Agent System Launcher
:: Implements the scheduling scenario from the paper:
::   "From Constraints to Cognition: A Hybrid Framework
::    for Adaptive, Explainable Scheduling"
:: ============================================================

:: Configuration - DALI is in the sibling folder
set dali_home=..\..\DALI\src
set conf_dir=conf

:: Search for spwin.exe
for %%I in (spwin.exe) do set prolog=%%~$PATH:I
if "%prolog%"=="" (
	for /d %%D in ("%PROGRAMFILES%\SICStus*") do (
		if exist "%%D\bin\spwin.exe" set "prolog=%%D\bin\spwin.exe"
	)
)
if "%prolog%"=="" (
	for /d %%D in ("%PROGRAMFILES(x86)%\SICStus*") do (
		if exist "%%D\bin\spwin.exe" set "prolog=%%D\bin\spwin.exe"
	)
)

if "%prolog%"=="" (
	echo ERROR: spwin.exe not found. Please install SICStus Prolog.
	exit /b 1
)
echo [INFO] spwin.exe found at: %prolog%

:: Cleanup
echo [INFO] Closing previous processes and cleaning folders...
taskkill /F /IM spwin.exe /T >nul 2>&1
taskkill /F /IM sprt.exe /T >nul 2>&1
taskkill /F /IM sicstus.exe /T >nul 2>&1
for /R work %%F in (*.*) do (if not "%%~nxF"==".gitkeep" del /q "%%F" >nul 2>&1)
for /R build %%F in (*.*) do (if not "%%~nxF"==".gitkeep" del /q "%%F" >nul 2>&1)
for /R conf\mas %%F in (*.*) do (if /I not "%%~nxF"==".gitkeep" if /I not "%%~nxF"=="communication.con" if /I not "%%~nxF"=="communication.conf" del /q "%%F" >nul 2>&1)
del /q server.txt >nul 2>&1
if not exist build mkdir build
if not exist work\log mkdir work\log
if not exist conf\mas mkdir conf\mas

:: Building agents from types + instances
echo [INFO] Building agents...
for %%I in (mas\instances\*.txt) do (
	for /f "usebackq delims=" %%T in (%%I) do set type=%%T
	copy /y mas\types\!type!.txt build\%%~nxI >nul
)
copy build\*.txt work\ >nul 2>nul

:: Starting LINDA server
echo [INFO] Starting LINDA server on port 3010...
start "MAS - Server" "%prolog%" --noinfo -l "%dali_home%\active_server_wi.pl" --goal "go(3010,'server.txt')."

:: Waiting for server
echo [INFO] Waiting for server.txt...
set server_ready=0
for /L %%i in (1,1,20) do (
    if exist "server.txt" (
        set server_ready=1
        goto :server_ok
    )
    timeout /t 1 /nobreak >nul
)
:server_ok

:: Starting user console
echo [INFO] Starting user console...
start "MAS - User" "%prolog%" --noinfo -l "%dali_home%\active_user_wi.pl" --goal "utente."
timeout /t 2 /nobreak >nul

:: Starting agents
echo [INFO] Starting agents...
echo [INFO]   Agents: alice, docJ, docS, mediator
set idx=1
for %%G in (build\*.txt) do (
	set "agent=%%~nG"
	call conf\makeconf.bat !agent! "%%G"
    start "MAS - !agent!" "%prolog%" --noinfo -l "%dali_home%\active_dali_wi.pl" --goal "start0('conf/mas/%%~nxG')."
    set /a idx+=1
	timeout /t 2 /nobreak >nul
)

echo.
echo ============================================================
echo  HYBRID SCHEDULING MAS STARTED
echo ============================================================
echo.
echo  Agents running: alice, docJ, docS, mediator
echo.
echo  To run the disruption scenario, use the User Console:
echo    1. docJ.                        (select target agent)
echo    2. user.                        (identify as user)
echo    3. send_message(emergency(urgent_call), user).
echo       ^(triggers docJ's disruption/emergency handler^)
echo.
echo  Press any key to shut down all agents.
echo ============================================================
pause >nul

:: Final cleanup
taskkill /F /IM spwin.exe /T >nul 2>&1
taskkill /F /IM sprt.exe /T >nul 2>&1
taskkill /F /IM sicstus.exe /T >nul 2>&1
del /q server.txt >nul 2>&1
exit /b 0
