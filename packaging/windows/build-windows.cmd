@echo off
cd /d "%~dp0..\..\app"
set SCUI_DEFAULT_BACKEND=WinUIBackend
swift build -c release --product Rufus
for /f "delims=" %%i in ('swift build -c release --show-bin-path') do set BIN_PATH=%%i
copy "%BIN_PATH%\Rufus.exe" "%~dp0rufuswift.exe"
copy "%BIN_PATH%\*.dll" "%~dp0"
echo Built Windows binary: %~dp0rufuswift.exe
