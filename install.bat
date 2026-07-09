@echo off
setlocal enabledelayedexpansion

echo ======================================================
echo VLC Infinity Enhanced - One-Click Installer (Windows)
echo ======================================================
echo.

:: Define source and destination
set "EXT_FILE=vlc-infinity-enhanced.lua"
set "DEST_DIR=%APPDATA%\vlc\lua\extensions"

:: Check if extension file exists in current directory
if not exist "%EXT_FILE%" (
    echo [ERROR] %EXT_FILE% not found in current directory.
    echo Please make sure you run this script from the extracted folder.
    pause
    exit /b 1
)

:: Create destination directory if it doesn't exist
if not exist "%DEST_DIR%" (
    echo [INFO] Creating VLC extensions directory...
    mkdir "%DEST_DIR%"
)

:: Copy the extension file
echo [INFO] Installing extension to %DEST_DIR%...
copy /y "%EXT_FILE%" "%DEST_DIR%\" >nul

if %ERRORLEVEL% equ 0 (
    echo.
    echo ======================================================
    echo [SUCCESS] VLC Infinity Enhanced installed successfully!
    echo ======================================================
    echo.
    echo To use the extension:
    echo 1. Open (or restart) VLC Media Player.
    echo 2. Go to 'View' menu.
    echo 3. Click on 'VLC Infinity Enhanced'.
    echo.
) else (
    echo.
    echo [ERROR] Installation failed. Please check your permissions.
    echo.
)

pause
exit /b 0
