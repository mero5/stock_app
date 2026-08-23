@echo off
setlocal

REM ============================================================
REM  stock_app backend deploy script
REM  See DEPLOY.md for the Japanese explanation.
REM
REM  NOTE: keep this file ASCII-only.
REM        cmd.exe mis-parses Japanese text in .bat files.
REM ============================================================

set KEY=C:\Users\s_mor\Downloads\keypea.pem
set REMOTE=ubuntu@13.114.75.49
set SRC=%~dp0backend
set DST=/home/ubuntu/stock_backend

echo.
echo [1/5] upload main.py / requirements.txt
scp -i "%KEY%" "%SRC%\main.py" "%SRC%\requirements.txt" %REMOTE%:%DST%/
if errorlevel 1 goto failed

echo.
echo [2/5] upload routers / services
scp -i "%KEY%" -r "%SRC%\routers" "%SRC%\services" %REMOTE%:%DST%/
if errorlevel 1 goto failed

echo.
echo [3/5] update deps and clean __pycache__
ssh -i "%KEY%" %REMOTE% "cd %DST% && source venv/bin/activate && pip install -r requirements.txt --quiet && find . -path ./venv -prune -o -name __pycache__ -type d -exec rm -rf {} +"
if errorlevel 1 goto failed

echo.
echo [4/5] restart service (systemd)
ssh -i "%KEY%" %REMOTE% "sudo systemctl restart stockapp"
if errorlevel 1 goto failed

echo.
echo [5/5] verify
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

:failed
echo.
echo ############################################
echo  DEPLOY FAILED - check the error above
echo ############################################
exit /b 1

:end
