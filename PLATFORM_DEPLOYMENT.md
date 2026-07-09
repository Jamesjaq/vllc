# VLC Infinity Enhanced - Platform Deployment Guide

## Overview

This guide provides platform-specific instructions for deploying VLC Infinity Enhanced v0.3 across Windows, Linux, macOS, Android, and iOS.

---

## Windows Deployment

### Installation Steps

1. **Download VLC Media Player**
   - Download from: https://www.videolan.org/vlc/
   - Recommended: VLC 3.0.0 or later
   - Install to default location or custom directory

2. **Locate VLC Extensions Directory**
   ```
   C:\Users\[YourUsername]\AppData\Roaming\vlc\lua\extensions\
   ```
   If directory doesn't exist, create it.

3. **Copy Extension File**
   ```
   Copy: vlc-infinity-enhanced.lua
   To: C:\Users\[YourUsername]\AppData\Roaming\vlc\lua\extensions\
   ```

4. **Restart VLC**
   - Close VLC completely
   - Reopen VLC
   - Go to View > VLC Infinity Enhanced

5. **Configure Settings**
   - Click Settings in the extension
   - Enter TMDB API key (provided in code)
   - Set your region if needed
   - Save settings

### Windows-Specific Notes

- File paths use backslash notation (handled automatically)
- Configuration files stored in AppData\Roaming\vlc\
- Supports Windows 7, 8, 10, 11
- 32-bit and 64-bit versions compatible
- UAC may require admin privileges for first run

### Troubleshooting Windows

**Extension not appearing:**
- Verify VLC version is 3.0.0+
- Check file is in correct directory
- Restart VLC completely
- Check VLC logs: Tools > Messages

**Playback issues:**
- Ensure Windows Firewall allows VLC network access
- Update graphics drivers
- Try different streaming provider in settings

---

## Linux Deployment

### Installation Steps (Ubuntu/Debian)

1. **Install VLC**
   ```bash
   sudo apt update
   sudo apt install vlc
   ```

2. **Locate VLC Extensions Directory**
   ```bash
   ~/.local/share/vlc/lua/extensions/
   ```
   Create if needed:
   ```bash
   mkdir -p ~/.local/share/vlc/lua/extensions/
   ```

3. **Copy Extension File**
   ```bash
   cp vlc-infinity-enhanced.lua ~/.local/share/vlc/lua/extensions/
   ```

4. **Set Permissions**
   ```bash
   chmod 644 ~/.local/share/vlc/lua/extensions/vlc-infinity-enhanced.lua
   ```

5. **Restart VLC**
   ```bash
   vlc &
   ```

### Installation Steps (Fedora/RHEL)

1. **Install VLC**
   ```bash
   sudo dnf install vlc
   ```

2. **Copy Extension**
   ```bash
   cp vlc-infinity-enhanced.lua ~/.local/share/vlc/lua/extensions/
   ```

3. **Restart VLC**

### Linux-Specific Notes

- File paths use forward slash notation
- Configuration stored in `~/.local/share/vlc/`
- Supports Ubuntu 18.04+, Fedora 30+, Debian 10+
- Both 32-bit and 64-bit architectures supported
- Headless mode supported for remote access

### Troubleshooting Linux

**Extension not loading:**
- Check file permissions: `ls -la ~/.local/share/vlc/lua/extensions/`
- Verify VLC version: `vlc --version`
- Check VLC logs: `~/.local/share/vlc/vlcrc`

**Network issues:**
- Check firewall: `sudo ufw status`
- Allow VLC through firewall if needed
- Test connectivity: `curl https://api.themoviedb.org/`

---

## macOS Deployment

### Installation Steps

1. **Install VLC**
   - Download from: https://www.videolan.org/vlc/
   - Drag VLC.app to Applications folder
   - Launch VLC

2. **Locate VLC Extensions Directory**
   ```bash
   ~/Library/Application Support/org.videolan.vlc/lua/extensions/
   ```
   Create if needed:
   ```bash
   mkdir -p ~/Library/Application\ Support/org.videolan.vlc/lua/extensions/
   ```

3. **Copy Extension File**
   ```bash
   cp vlc-infinity-enhanced.lua ~/Library/Application\ Support/org.videolan.vlc/lua/extensions/
   ```

4. **Set Permissions**
   ```bash
   chmod 644 ~/Library/Application\ Support/org.videolan.vlc/lua/extensions/vlc-infinity-enhanced.lua
   ```

5. **Restart VLC**
   - Quit VLC: Cmd+Q
   - Reopen VLC
   - Go to View > VLC Infinity Enhanced

### macOS-Specific Notes

- Supports macOS 10.13+
- Both Intel and Apple Silicon (M1/M2) supported
- Configuration stored in ~/Library/Application Support/
- Gatekeeper may require allowing VLC on first run
- Notarization: VLC is properly notarized for macOS

### Troubleshooting macOS

**"VLC cannot be opened" error:**
- Right-click VLC.app > Open
- Go to System Preferences > Security & Privacy
- Allow VLC to run

**Extension not appearing:**
- Check directory path carefully (spaces in path)
- Verify file permissions: `ls -la ~/Library/Application\ Support/org.videolan.vlc/lua/extensions/`
- Restart VLC completely

---

## Android Deployment

### Installation Steps

1. **Install VLC for Android**
   - Download from Google Play Store
   - Or download APK from: https://www.videolan.org/vlc/download-android.html
   - Minimum: Android 5.0 (API 21)

2. **Locate VLC Extensions Directory**
   ```
   /sdcard/Android/data/org.videolan.vlc/files/lua/extensions/
   ```
   Or using file manager:
   - Open file manager
   - Navigate to Android/data/org.videolan.vlc/files/
   - Create "lua/extensions/" if needed

3. **Copy Extension File**
   - Connect device to computer via USB
   - Enable USB debugging: Settings > Developer Options > USB Debugging
   - Copy file using ADB:
   ```bash
   adb push vlc-infinity-enhanced.lua /sdcard/Android/data/org.videolan.vlc/files/lua/extensions/
   ```
   Or use file manager to copy manually

4. **Restart VLC**
   - Close VLC completely
   - Reopen VLC
   - Go to More > VLC Infinity Enhanced

5. **Grant Permissions**
   - Allow storage access when prompted
   - Allow network access when prompted

### Android-Specific Notes

- Tested on Android 8.0+
- Requires internet connection
- Storage permission needed for config files
- Network permission needed for streaming
- Mobile UI optimized for touch
- Battery usage: Moderate (streaming dependent)

### Troubleshooting Android

**Extension not appearing:**
- Verify file is in correct directory
- Check VLC version is latest
- Restart device if needed
- Clear VLC cache: Settings > Apps > VLC > Storage > Clear Cache

**Playback issues:**
- Check WiFi/mobile connection
- Reduce video quality in settings
- Close other apps to free memory
- Update VLC to latest version

**Storage permission denied:**
- Go to Settings > Apps > VLC > Permissions
- Enable "Storage" permission
- Restart VLC

---

## iOS Deployment

### Installation Steps

1. **Install VLC for iOS**
   - Download from App Store
   - Minimum: iOS 13.0
   - iPad and iPhone compatible

2. **Access Files App**
   - Open Files app on iOS device
   - Navigate to "On My iPhone" > VLC

3. **Add Extension File**
   - Option A: Via iCloud Drive
     - Upload vlc-infinity-enhanced.lua to iCloud Drive
     - Open Files app > iCloud Drive
     - Copy file to VLC folder
   
   - Option B: Via iTunes File Sharing
     - Connect iPhone to Mac/PC
     - Open iTunes or Finder
     - Select device > Apps > VLC
     - Drag vlc-infinity-enhanced.lua to file list

4. **Restart VLC**
   - Force close VLC: Swipe up from bottom
   - Reopen VLC
   - Look for VLC Infinity Enhanced in menu

5. **Grant Permissions**
   - Allow network access when prompted
   - Allow local network access when prompted

### iOS-Specific Notes

- Tested on iOS 13.0+
- iPad and iPhone both supported
- Requires iOS 13 or later
- Local network permission required for some features
- Battery usage: Moderate to High (streaming dependent)
- Storage: ~5MB for extension + config files

### Troubleshooting iOS

**Extension not appearing:**
- Verify file is in VLC folder
- Check file extension is .lua
- Restart VLC app completely
- Force quit: Swipe up from bottom, hold, swipe up on VLC

**Playback issues:**
- Check WiFi connection strength
- Reduce video quality if available
- Close other apps
- Restart device if needed

**Permission denied errors:**
- Go to Settings > VLC
- Enable "Local Network" permission
- Enable "Network" permission
- Restart VLC

---

## Cross-Platform Configuration

### TMDB API Key Setup

The extension includes a pre-configured TMDB API key. To use your own:

1. Visit: https://www.themoviedb.org/settings/api
2. Create free account if needed
3. Generate API key
4. In VLC Infinity Enhanced Settings:
   - Paste your API key
   - Click Save Settings

### EPG Configuration

To enable Electronic Program Guide (EPG):

1. Find XMLTV format EPG URL
   - Example: `https://example.com/guide.xml`
2. In Settings:
   - Paste EPG URL
   - Click Save Settings
3. Go to EPG section to view programs

### Region Configuration

For geo-blocking or region-specific content:

1. In Settings:
   - Enter your region code (e.g., "US", "UK", "CA")
   - Click Save Settings
2. Extension will respect region restrictions

---

## Verification Checklist

After installation, verify functionality:

| Feature | Windows | Linux | macOS | Android | iOS |
|---------|---------|-------|-------|---------|-----|
| Movies search | ✓ | ✓ | ✓ | ✓ | ✓ |
| TV series | ✓ | ✓ | ✓ | ✓ | ✓ |
| Animation | ✓ | ✓ | ✓ | ✓ | ✓ |
| Cable TV | ✓ | ✓ | ✓ | ✓ | ✓ |
| Favorites | ✓ | ✓ | ✓ | ✓ | ✓ |
| Watch Later | ✓ | ✓ | ✓ | ✓ | ✓ |
| History | ✓ | ✓ | ✓ | ✓ | ✓ |
| Settings | ✓ | ✓ | ✓ | ✓ | ✓ |
| Playback | ✓ | ✓ | ✓ | ✓ | ✓ |

---

## Performance Optimization

### For All Platforms

- Clear cache regularly: Settings > Clear Cache
- Update VLC to latest version
- Close unused apps to free memory
- Use WiFi for better streaming
- Disable VPN if experiencing issues

### Windows Optimization

- Update graphics drivers
- Disable hardware acceleration if issues occur
- Use SSD for better performance

### Linux Optimization

- Install hardware acceleration packages
- Use latest kernel version
- Check system resources: `top` or `htop`

### macOS Optimization

- Update to latest macOS version
- Close unnecessary apps
- Check Activity Monitor for resource usage

### Android Optimization

- Keep device updated
- Close background apps
- Use WiFi instead of mobile data
- Restart device if performance degrades

### iOS Optimization

- Keep iOS updated
- Close background apps
- Restart device regularly
- Use WiFi for streaming

---

## Uninstallation

### Windows
1. Delete file from: `C:\Users\[YourUsername]\AppData\Roaming\vlc\lua\extensions\`
2. Restart VLC

### Linux
```bash
rm ~/.local/share/vlc/lua/extensions/vlc-infinity-enhanced.lua
```

### macOS
```bash
rm ~/Library/Application\ Support/org.videolan.vlc/lua/extensions/vlc-infinity-enhanced.lua
```

### Android
1. Open file manager
2. Navigate to Android/data/org.videolan.vlc/files/lua/extensions/
3. Delete vlc-infinity-enhanced.lua

### iOS
1. Open Files app
2. Navigate to VLC folder
3. Delete vlc-infinity-enhanced.lua

---

## Support

For platform-specific issues:
- GitHub Issues: https://github.com/Jamesjaq/vllc/issues
- VLC Forum: https://forum.videolan.org/
- Platform-specific forums

---

**Last Updated:** 2024
**Status:** Production Ready
