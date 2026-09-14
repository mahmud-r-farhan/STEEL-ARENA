@echo off
title Steel Arena Dedicated Server
echo ========================================================
echo Starting Steel Arena Dedicated Authoritative Server...
echo Default UDP port: 37555
echo ========================================================
"%~dp0steel-arena.exe" --server
if errorlevel 1 pause
