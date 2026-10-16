@echo off
rem Terra Shader: one command build. See build.sh for usage.
cd /d "%~dp0"
where python >nul 2>nul || (echo Python 3.11+ not found. & exit /b 1)
python tool %*
