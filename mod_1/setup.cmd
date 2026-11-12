@echo off
chcp 65001 >nul
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start\setup.ps1"
set "setup_exit=%errorlevel%"
if not "%setup_exit%"=="0" echo Установка прервана. Причина указана выше и в файле start\setup.log.
echo Нажмите любую клавишу, чтобы закрыть окно.
pause >nul
exit /b %setup_exit%
