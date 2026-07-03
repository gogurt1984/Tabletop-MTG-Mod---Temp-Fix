@echo off
title Gogurt's 6 Player MTG Table - Installer
echo Fetching the latest installer from GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $s = Invoke-RestMethod ('https://raw.githubusercontent.com/gogurt1984/Tabletop-MTG---Gogurts-DIY-Table/main/installer.ps1?nocache=' + (Get-Random)); Invoke-Expression $s } catch { Write-Host ('Failed to fetch the installer: ' + $_.Exception.Message) -ForegroundColor Red }"
pause
