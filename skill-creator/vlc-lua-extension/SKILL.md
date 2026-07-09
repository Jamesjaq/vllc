---
name: vlc-lua-extension
description: "Guide for developing, debugging, and packaging VLC Media Player Lua extensions. Use for: creating custom VLC extensions, understanding the VLC Lua API, integrating streaming services, building UI dialogs, and handling cross-platform deployment."
---

# VLC Lua Extension Development Guide

This skill provides comprehensive instructions for building, testing, and deploying Lua extensions for VLC Media Player.

## Overview

VLC Media Player supports powerful extensions written in Lua that can manipulate the playlist, create custom UI dialogs, parse network streams, and integrate external APIs directly into the native player interface.

## Core Capabilities

VLC Lua extensions can:
1. **Create UI Dialogs:** Build custom menus, inputs, buttons, and dropdowns natively in VLC.
2. **Manage Playlist:** Add, remove, and play items programmatically.
3. **Fetch Network Data:** Make HTTP requests to external APIs or fetch streaming manifests (M3U).
4. **Parse Data:** Process JSON and XML responses.
5. **Persist Data:** Save and load configuration or history locally.

## Basic Structure

Every VLC extension must include a `descriptor()` function and standard lifecycle callbacks.

```lua
-- Required descriptor function
function descriptor()
    return {
        title = "My Extension",
        version = "1.0",
        author = "Author Name",
        url = "https://github.com/example/repo",
        description = "Description of the extension",
        capabilities = {"menu"} -- Enables the View menu item
    }
end

-- Called when extension starts
function activate()
    vlc.msg.info("Extension activated")
    -- Initialization code
end

-- Called when extension stops
function deactivate()
    vlc.msg.info("Extension deactivated")
    -- Cleanup code
end

-- Called when VLC closes
function close()
    vlc.deactivate()
end

-- Defines menu options (if 'menu' capability is set)
function menu()
    return {"Option 1", "Option 2"}
end

-- Handles menu clicks
function trigger_menu(id)
    if id == 1 then
        -- Handle Option 1
    end
end
```

## Creating Dialogs

VLC allows creating native dialogs using `vlc.dialog()`.

```lua
local dlg = nil

function show_dialog()
    dlg = vlc.dialog("My Custom Dialog")
    
    -- Add elements (text, col, row, col_span, row_span)
    dlg:add_label("Welcome!", 1, 1, 2, 1)
    
    -- Add interactive elements
    local input = dlg:add_text_input("Default text", 1, 2, 2, 1)
    
    dlg:add_button("Click Me", function()
        local text = input:get_text()
        vlc.msg.info("User entered: " .. text)
    end, 1, 3, 1, 1)
    
    dlg:show()
end
```

## Making HTTP Requests

VLC provides a network session API to fetch data.

```lua
local function fetch_url(url)
    local http = vlc.net.get_http_session()
    if not http then return nil end
    
    local stream = http:get(url)
    if not stream then 
        http:release()
        return nil 
    end
    
    local content = ""
    while true do
        local chunk = stream:read(4096)
        if not chunk or chunk == "" then break end
        content = content .. chunk
    end
    
    stream:release()
    http:release()
    return content
end
```

## Managing the Playlist

Add items and control playback:

```lua
-- Add item to playlist
vlc.playlist.add({
    { path = "https://example.com/stream.m3u8", name = "Live Stream" }
})

-- Start playback
vlc.playlist.play()
```

## Data Persistence

Save and load user data in the VLC config directory.

```lua
local config_file = vlc.config.path() .. "my-extension-config.json"

local function save_data(data)
    local file = vlc.io.open(config_file, "w")
    if file then
        file:write(vlc.json.encode(data))
        file:close()
        return true
    end
    return false
end

local function load_data()
    local file = vlc.io.open(config_file, "r")
    if file then
        local content = file:read()
        file:close()
        return vlc.json.decode(content)
    end
    return nil
end
```

## Installation Locations

VLC looks for extensions in specific directories depending on the OS:

- **Windows:** `%APPDATA%\\vlc\\lua\\extensions\\` or `C:\\Program Files\\VideoLAN\\VLC\\lua\\extensions\\`
- **macOS:** `~/Library/Application Support/org.videolan.vlc/lua/extensions/`
- **Linux:** `~/.local/share/vlc/lua/extensions/`

## Troubleshooting and Logs

To debug extensions, open VLC and navigate to **Tools > Messages**. Set the verbosity to **2 (Debug)**. Use `vlc.msg.info()`, `vlc.msg.warn()`, and `vlc.msg.err()` in your Lua code to output logs here.
