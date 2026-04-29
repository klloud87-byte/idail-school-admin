@echo off
chcp 65001 >nul
cd /d "%~dp0"
title IDAIL School — local server
echo.
echo ========================================
echo   افتح المتصفح على:
echo   http://localhost:8080
echo.
echo   خلي هذي النافذة مفتوحة. أوقف الخادم: Ctrl+C
echo ========================================
echo.
where py >nul 2>&1
if %ERRORLEVEL%==0 (
  py -m http.server 8080
  goto :end
)
where python >nul 2>&1
if %ERRORLEVEL%==0 (
  python -m http.server 8080
  goto :end
)
where npx >nul 2>&1
if %ERRORLEVEL%==0 (
  npx --yes serve . -l 8080
  goto :end
)
echo لم يُعثر على py ولا python ولا npx. ثبّت Python أو Node.js.
pause
exit /b 1
:end
pause
