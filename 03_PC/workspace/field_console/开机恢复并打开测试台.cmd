@echo off
chcp 65001 >nul
"E:\develop\python\python.exe" -B -X utf8 "%~dp0prepare_board.py"
if errorlevel 1 (
 echo 恢复未完成，请保留上述错误信息。
 pause
 exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_console.ps1"
if errorlevel 1 pause
