#!/bin/bash

echo "======================================================"
echo "VLC Infinity Enhanced - Universal Installer (Unix)"
echo "======================================================"
echo ""

EXT_FILE="vlc_inf.lua"
OS_TYPE=$(uname)

# Check if extension file exists
if [ ! -f "$EXT_FILE" ]; then
    echo "[ERROR] $EXT_FILE not found in current directory."
    echo "Please run this script from the project root folder."
    exit 1
fi

install_to() {
    local DEST_DIR="$1"
    local TYPE="$2"
    
    echo "[INFO] Checking $TYPE path: $DEST_DIR"
    
    # Create directory
    mkdir -p "$DEST_DIR"
    
    # Copy file
    cp "$EXT_FILE" "$DEST_DIR/"
    if [ $? -eq 0 ]; then
        echo "[SUCCESS] Installed to $TYPE."
        return 0
    else
        echo "[ERROR] Failed to install to $TYPE."
        return 1
    fi
}

if [ "$OS_TYPE" == "Darwin" ]; then
    # macOS
    install_to "$HOME/Library/Application Support/org.videolan.vlc/lua/extensions" "macOS Standard"
else
    # Linux - Try multiple common paths
    
    # 1. Standard Path
    install_to "$HOME/.local/share/vlc/lua/extensions" "Linux Standard"
    
    # 2. Snap Path
    if [ -d "$HOME/snap/vlc" ]; then
        # Check for multiple versions in snap
        for d in "$HOME/snap/vlc/"*/; do
            if [ -d "$d" ]; then
                install_to "${d}.local/share/vlc/lua/extensions" "VLC Snap (!)"
            fi
        done
    fi
    
    # 3. Flatpak Path
    if [ -d "$HOME/.var/app/org.videolan.VLC" ]; then
        install_to "$HOME/.var/app/org.videolan.VLC/data/vlc/lua/extensions" "VLC Flatpak"
    fi
fi

echo ""
echo "======================================================"
echo "Installation process completed!"
echo "======================================================"
echo ""
echo "IMPORTANT:"
echo "1. COMPLETELY CLOSE and RESTART VLC Media Player."
echo "2. Go to 'View' menu -> 'VLC Infinity Enhanced'."
echo ""
echo "If it still doesn't appear:"
echo "- Go to 'Tools' -> 'Plugins and extensions'."
echo "- Click 'Reload extensions'."
echo "- Check 'Tools' -> 'Messages' (Verbosity 2) for errors."
echo ""
