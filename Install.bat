@echo off
REM Author: siavash.golchoobian@gmail.com
cd /D "%~dp0"
powershell.exe -executionpolicy bypass -File .\SqlDeepAudit.ps1 -UI
pause