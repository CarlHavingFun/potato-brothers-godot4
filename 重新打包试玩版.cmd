@echo off
setlocal

set "PROJECT_ROOT=%~dp0"
set "POWERSHELL_BINARY=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "GODOT_BINARY=%PROJECT_ROOT%..\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe"
set "BUILD_SCRIPT=%PROJECT_ROOT%tools\build_windows_release.ps1"
set "PLAYTEST_ARCHIVE=%PROJECT_ROOT%dist\game-prototype\GamePrototype-Windows-x86_64.zip"

if not exist "%POWERSHELL_BINARY%" (
	echo [ERROR] Windows PowerShell was not found:
	echo         %POWERSHELL_BINARY%
	set "BUILD_EXIT_CODE=2"
	goto finish
)
if not exist "%GODOT_BINARY%" (
	echo [ERROR] The required Godot 4.7.1 tool was not found:
	echo         %GODOT_BINARY%
	set "BUILD_EXIT_CODE=3"
	goto finish
)
if not exist "%BUILD_SCRIPT%" (
	echo [ERROR] The Windows build script was not found:
	echo         %BUILD_SCRIPT%
	set "BUILD_EXIT_CODE=4"
	goto finish
)

echo Building the Windows playtest with Godot 4.7.1...
echo.
pushd "%PROJECT_ROOT%"
"%POWERSHELL_BINARY%" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%BUILD_SCRIPT%" -GodotBinary "%GODOT_BINARY%"
set "BUILD_EXIT_CODE=%ERRORLEVEL%"
popd

:finish
echo.
if "%BUILD_EXIT_CODE%"=="0" (
	echo [SUCCESS] Playtest package created:
	echo           %PLAYTEST_ARCHIVE%
) else (
	echo [FAILED] Packaging stopped with exit code %BUILD_EXIT_CODE%.
)
echo.
pause
exit /b %BUILD_EXIT_CODE%
