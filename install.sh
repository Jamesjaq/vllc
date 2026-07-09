#!/bin/bash

echo "======================================================"
echo "VLC Infinity Enhanced - One-Click Installer (Unix)"
echo "======================================================"
echo ""

EXT_FILE="vlc-infinity-enhanced.lua"
OS_TYPE=$(uname)

# Determine destination directory based on OS
if [ "$OS_TYPE" == "Darwin" ]; then
    # macOS
    DEST_DIR="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"
else
    # Linux
    DEST_DIR="$HOME/.local/share/vlc/lua/extensions"
fi

# Check if extension file exists
if [ ! -f "$EXT_FILE" ]; then
    echo "[ERROR] $EXT_FILE not found in current directory."
    echo "Please run this script from the project root folder."
    exit 1
fi

# Create destination directory
if [ ! -d "$DEST_DIR" ]; then
    echo "[INFO] Creating VLC extensions directory..."
    mkdir -p "$DEST_DIR"
fi

# Copy the extension file
echo "[INFO] Installing extension to $DEST_DIR..."
cp "$EXT_FILE" "$DEST_DIR/"

if [ $? -eq 0 ]; then
    echo ""
    echo "======================================================"
    echo "[SUCCESS] VLC Infinity Enhanced installed successfully!"
    echo "======================================================"
    echo ""
    echo "To use the extension:"
    echo "1. Open (or restart) VLC Media Player."
    echo "2. Go to 'View' menu."
    echo "3. Click on 'VLC Infinity Enhanced'."
    echo ""
else
    echo ""
    echo "[ERROR] Installation failed. Please check your permissions."
    echo ""
fi
