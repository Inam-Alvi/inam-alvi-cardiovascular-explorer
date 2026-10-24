@echo off
setlocal
cd /d "%~dp0"
title Cardiovascular Explorer - Offline Launcher
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0OfflineServer.ps1"
if errorlevel 1 (
  echo.
  echo The offline server stopped or could not start.
  echo Please contact your teacher or IT support.
  pause
)
