@echo off
setlocal
cd /d "%~dp0"
title Steel Arena - Dedicated UDP Server

if exist "tools\love\lovec.exe" (
    "tools\love\lovec.exe" src --server
    goto done
)

if exist "tools\love\love.exe" (
    "tools\love\love.exe" src --server
    goto done
)

where lovec >nul 2>nul
if %errorlevel% equ 0 (
    lovec src --server
    goto done
)

where love >nul 2>nul
if %errorlevel% equ 0 (
    love src --server
    goto done
)

echo LÖVE 2D engine not found. Please install LÖVE or extract into tools\love\.
pause

:done
endlocal
