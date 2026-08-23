@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  stock_app backend deploy script
REM  See DEPLOY.md for the Japanese explanation.
REM
REM  NOTE: keep this file ASCII-only.
REM        cmd.exe mis-parses Japanese text in .bat files.
REM
REM  Subdirectories are discovered automatically, so a newly
REM  added package is never left behind. Before restarting the
REM  service the script imports the app once; if that fails the
REM  deploy aborts and the running service is left untouched.
REM ============================================================

set KEY=C:\Users\s_mor\Downloads\keypea.pem
set REMOTE=ubuntu@13.114.75.49
set SRC=%~dp0backend
set DST=/home/ubuntu/stock_backend

echo.
echo [1/6] upload top-level files
scp -i "%KEY%" "%SRC%\main.py" "%SRC%\requirements.txt" %REMOTE%:%DST%/
if errorlevel 1 goto failed

echo.
echo [2/6] upload every subdirectory (auto-detected)
for /d %%D in ("%SRC%\*") do (
    set "NAME=%%~nxD"
    if /I not "!NAME!"=="__pycache__" (
        if /I not "!NAME!"=="venv" (
            echo     - !NAME!
            scp -i "%KEY%" -r "%%D" %REMOTE%:%DST%/
            if errorlevel 1 goto failed
        )
    )
)

echo.
echo [3/6] update deps and clean __pycache__
ssh -i "%KEY%" %REMOTE% "cd %DST% && source venv/bin/activate && pip install -r requirements.txt --quiet && find . -path ./venv -prune -o -name __pycache__ -type d -exec rm -rf {} +"
if errorlevel 1 goto failed

echo.
echo [4/6] smoke test (import the app before touching the service)
ssh -i "%KEY%" %REMOTE% "cd %DST% && source venv/bin/activate && python -c 'import main' > /dev/null"
if errorlevel 1 goto importfailed

echo.
echo [5/6] restart service (systemd)
ssh -i "%KEY%" %REMOTE% "sudo systemctl restart stockapp"
if errorlevel 1 goto failed

echo.
echo [6/6] verify
ssh -i "%KEY%" %REMOTE% "sleep 15; systemctl is-active stockapp; echo '--- health ---'; curl -s --max-time 60 http://127.0.0.1:8000/health; echo; echo '--- log ---'; sudo journalctl -u stockapp -n 12 --no-pager"
if errorlevel 1 goto failed

echo.
echo ============================================
echo  DEPLOY OK
echo ============================================
echo  tail log : ssh -i "%KEY%" %REMOTE% "sudo journalctl -u stockapp -f"
echo  restart  : ssh -i "%KEY%" %REMOTE% "sudo systemctl restart stockapp"
echo ============================================
goto end

:importfailed
echo.
echo ############################################
echo  IMPORT FAILED - the app could not be loaded
echo  The running service was NOT restarted.
echo  Fix the error above, then run deploy again.
echo ############################################
exit /b 1

:failed
echo.
echo ############################################
echo  DEPLOY FAILED - check the error above
echo ############################################
exit /b 1

:end
