@echo off
rem zaevis — Windows launcher. Finds Node.js 24+ (bundled in the app folder, else on PATH) and runs
rem server\src\zaevis.ts, the same command implementation as on macOS and Linux.
setlocal
set "ROOT=%~dp0.."
if exist "%ROOT%\node\node.exe" (
  set "NODE=%ROOT%\node\node.exe"
) else (
  where node >nul 2>nul || (echo Node.js 24 이상이 필요합니다: https://nodejs.org & exit /b 1)
  set "NODE=node"
)
"%NODE%" "%ROOT%\server\src\zaevis.ts" %*
endlocal & exit /b %ERRORLEVEL%
