# VLC Infinity Enhanced v0.3

VLC Infinity Enhanced is a comprehensive media streaming extension for VLC Media Player that brings movies, TV series, animated content, and global cable TV channels into a single, unified interface.

---

## 🎬 Key Features

- **Movies & TV Series:** Search and stream thousands of titles via TMDB integration.
- **Animation Category:** Dedicated section for animated movies and shows.
- **Cable TV (IPTV):** Access to thousands of live channels worldwide with country and category filtering.
- **EPG Support:** Electronic Program Guide for TV channels with search and schedule viewing.
- **Watch Later & Favorites:** Save your favorite content for quick access later.
- **Watch History:** Keep track of what you've watched across all categories.
- **Cross-Platform:** Fully optimized for Windows, Linux, macOS, Android, and iOS.

---

## 🚀 Quick Start

1. **Download the Extension:**
   Download the [vlc-infinity-enhanced.lua](./vlc-infinity-enhanced.lua) file from this repository.

2. **Install to VLC:**
   Move the file to your VLC extensions folder:
   - **Windows:** `%APPDATA%\vlc\lua\extensions\`
   - **Linux:** `~/.local/share/vlc/lua/extensions/`
   - **macOS:** `~/Library/Application Support/org.videolan.vlc/lua/extensions/`
   - **Android:** `/sdcard/Android/data/org.videolan.vlc/files/lua/extensions/`
   - **iOS:** Move to the VLC folder via the Files app.

3. **Restart VLC:**
   Open VLC and navigate to `View > VLC Infinity Enhanced` to start streaming.

---

## 🛠️ Configuration

The extension comes pre-configured with a TMDB API key. You can customize your experience in the **Settings** menu:
- Set your **Region** for localized content.
- Add a custom **EPG URL** for your favorite TV guides.
- Update the **TMDB API Key** if you have your own.

---

## 📚 Documentation

For detailed information, please refer to the following guides:
- [Installation & Deployment Guide](./PLATFORM_DEPLOYMENT.md)
- [Features & Improvements](./FIXES_AND_IMPROVEMENTS.md)
- [Testing & Verification Results](./TESTING_GUIDE.md)
- [Release Notes v0.3](./RELEASE_NOTES_v0.3.md)

---

## 👨‍💻 Developer Resources (Manus Skill)

This repository is built using the **Manus Skill Framework**. If you are an AI agent or a developer looking to extend this project, you can find the development "skill" package here:

- **Skill Path:** [`./skill-creator/vlc-lua-extension/`](./skill-creator/vlc-lua-extension/)
- **Purpose:** Contains the API references, UI patterns, and templates used to build this extension. Loading the `SKILL.md` file into an AI context allows for seamless expansion of the project.

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.

---

**Developed with ❤️ by Manus AI**
