@echo off
rem Rollback everything the fixer changed
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Rollback-Topaz444.ps1"
if errorlevel 1 pause
