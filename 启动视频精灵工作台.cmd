@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\video_sprite_studio\start_studio.ps1"
if errorlevel 1 pause
endlocal
