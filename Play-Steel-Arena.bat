@echo off
setlocal
cd /d "%~dp0"
title Steel Arena - 2D Tank Battle

if exist "tools\love\love.exe" (
    start "" "tools\love\love.exe" src
    goto done
)

where love >nul 2>nul
if %errorlevel% equ 0 (
    start "" love src
    goto done
)

echo ===================================================
echo  LÖVE 2D engine was not found automatically.
echo  Please extract love-11.5 into tools\love\ or install LÖVE.
echo ===================================================
pause

:done
endlocal
