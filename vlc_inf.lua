-- VLC Infinity v0.3.2 (Persistent UI Edition)
-- Redesigned for maximum compatibility with Kali/Debian VLC

function descriptor()
    return {
        title = "VLC Infinity",
        version = "0.3.2",
        author = "Manus AI",
        url = "https://github.com/Jamesjaq/vlc",
        description = "Advanced streaming for movies, TV, and Cable TV.",
        capabilities = {"menu"}
    }
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local TMDB_API_KEY = "6b15c3bea7b76b7148a835dd50d99175"
local TMDB_BASE_URL = "https://api.themoviedb.org/3"

local STREAMING_PROVIDERS = {
    { name = "VidSrc", base_url = "https://vidsrc.me/embed/movie/{imdb_id}", priority = 1 },
    { name = "VidSrc Pro", base_url = "https://vidsrc.pro/embed/movie/{imdb_id}", priority = 2 },
    { name = "2embed", base_url = "https://www.2embed.cc/embed/{imdb_id}", priority = 3 }
}

local TV_PROVIDERS = {
    { name = "VidSrc TV", base_url = "https://vidsrc.me/embed/tv/{imdb_id}/{season}/{episode}", priority = 1 },
    { name = "2embed TV", base_url = "https://www.2embed.cc/embed/tv/{imdb_id}/{season}/{episode}", priority = 2 }
}

-- ============================================================================
-- GLOBAL STATE
-- ============================================================================

local main_dlg = nil
local search_input = nil
local results_list = nil
local current_results = {}
local current_mode = "movies"

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function get_http_content(url)
    local stream = vlc.stream(url)
    if not stream then return nil end
    local content = ""
    local count = 0
    while count < 100 do
        local chunk = stream:read(4096)
        if not chunk or chunk == "" then break end
        content = content .. chunk
        count = count + 1
    end
    return content
end

-- ============================================================================
-- CORE FUNCTIONS
-- ============================================================================

function activate()
    create_dialog()
end

function deactivate()
    if main_dlg then main_dlg:delete() end
end

function close()
    deactivate()
end

function create_dialog()
    if main_dlg then main_dlg:delete() end
    main_dlg = vlc.dialog("VLC Infinity")
    
    -- ROW 1: TITLE
    main_dlg:add_label("<b>VLC Infinity v0.3.2</b>", 1, 1, 10, 1)
    
    -- ROW 2: MODE SELECTOR
    main_dlg:add_button("🎬 Movies", function() current_mode = "movies"; update_ui() end, 1, 2, 2, 1)
    main_dlg:add_button("📺 TV", function() current_mode = "tv"; update_ui() end, 3, 2, 2, 1)
    main_dlg:add_button("🦄 Anime", function() current_mode = "animation"; update_ui() end, 5, 2, 2, 1)
    main_dlg:add_button("📡 Cable", function() current_mode = "iptv"; update_ui() end, 7, 2, 2, 1)
    
    -- ROW 3: SEARCH LABEL
    main_dlg:add_label("<b>Search:</b>", 1, 3, 2, 1)
    search_input = main_dlg:add_input("", 3, 3, 6, 1)
    main_dlg:add_button("🔍 GO", perform_search, 9, 3, 2, 1)
    
    -- ROW 4: RESULTS LIST
    main_dlg:add_label("<b>Results:</b>", 1, 4, 10, 1)
    results_list = main_dlg:add_list(1, 5, 10, 5)
    
    -- ROW 5: PLAY BUTTON
    main_dlg:add_button("▶️ PLAY SELECTED", play_selected, 1, 10, 10, 1)
    
    update_ui()
end

function update_ui()
    if main_dlg then
        vlc.msg.info("VLC Infinity: Mode switched to " .. current_mode)
    end
end

function perform_search()
    local query = search_input:get_text()
    if not query or query == "" then return end
    
    vlc.msg.info("VLC Infinity: Searching for " .. query)
    
    local url = ""
    if current_mode == "movies" or current_mode == "animation" then
        url = TMDB_BASE_URL .. "/search/movie?api_key=" .. TMDB_API_KEY .. "&query=" .. vlc.strings.url_encode(query)
    elseif current_mode == "tv" then
        url = TMDB_BASE_URL .. "/search/tv?api_key=" .. TMDB_API_KEY .. "&query=" .. vlc.strings.url_encode(query)
    else
        -- IPTV logic placeholder
        results_list:add("Global Cable TV - Coming Soon", 1)
        return
    end
    
    local content = get_http_content(url)
    if content then
        local data = vlc.json.decode(content)
        if data and data.results then
            current_results = data.results
            results_list:clear()
            for i, item in ipairs(current_results) do
                if i > 20 then break end
                local title = item.title or item.name or "Unknown"
                local year = (item.release_date or item.first_air_date or ""):sub(1,4)
                results_list:add(title .. " (" .. year .. ")", i)
            end
        end
    end
end

function play_selected()
    local selection = results_list:get_selection()
    if not selection then return end
    
    -- Get the first key from selection table
    local idx = nil
    for i, _ in pairs(selection) do idx = i; break end
    if not idx then return end
    
    local item = current_results[idx]
    if not item then return end
    
    vlc.msg.info("VLC Infinity: Resolving " .. (item.title or item.name))
    
    local item_type = (current_mode == "tv") and "tv" or "movie"
    local detail_url = TMDB_BASE_URL .. "/" .. item_type .. "/" .. item.id .. "?api_key=" .. TMDB_API_KEY .. "&append_to_response=external_ids"
    
    local content = get_http_content(detail_url)
    if content then
        local details = vlc.json.decode(content)
        local imdb_id = details.external_ids and details.external_ids.imdb_id
        if imdb_id then
            local play_url = ""
            if current_mode == "tv" then
                play_url = TV_PROVIDERS[1].base_url:gsub("{imdb_id}", imdb_id):gsub("{season}", "1"):gsub("{episode}", "1")
            else
                play_url = STREAMING_PROVIDERS[1].base_url:gsub("{imdb_id}", imdb_id)
            end
            
            vlc.playlist.add({{path = play_url, name = "VLC Infinity: " .. (item.title or item.name)}})
            vlc.playlist.play()
        end
    end
end
