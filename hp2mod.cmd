@echo off
rem Windows launcher for the HP2 Language Randomizer tools.
rem Uses hp2mod.exe next to this file if present (release build), otherwise
rem Python 3 (the tools need nothing beyond the standard library).
setlocal
if exist "%~dp0hp2mod.exe" (
  "%~dp0hp2mod.exe" %*
  exit /b %errorlevel%
)
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 "%~dp0tools\hp2mod.py" %*
) else (
  python "%~dp0tools\hp2mod.py" %*
)
exit /b %errorlevel%
