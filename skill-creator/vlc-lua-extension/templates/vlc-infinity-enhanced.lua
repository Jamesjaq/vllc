-- VLC Infinity Enhanced - Full Streaming Movie Browser
-- Integrates TMDB for metadata and VidSrc/2embed/RapidCloud for streaming
-- Version: 0.2

function descriptor()
    return {
        title = "VLC Infinity Enhanced",
        version = "0.2",
        author = "Manus AI",
        url = "https://github.com/Jamesjaq/vlc",
        description = "Advanced VLC plugin for free cable TV, movies, and streaming content.",
        capabilities = {"menu"}
    }
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local TMDB_API_KEY = "6b15c3bea7b76b7148a835dd50d99175"  -- Pre-configured TMDB API key
local TMDB_BASE_URL = "https://api.themoviedb.org/3"

-- Streaming providers (tried in order)
local STREAMING_PROVIDERS = {
    {
        name = "VidSrc",
        url_pattern = "https://vidsrc.dev/embed/movie/{imdb_id}",
        priority = 1,
        type = "embed"
    },
    {
        name = "2embed",
        url_pattern = "https://www.2embed.org/embed/{imdb_id}",
        priority = 2,
        type = "embed"
    },
    {
        name = "RapidCloud",
        url_pattern = "https://rapidcloud.co/embed-{imdb_id}",
        priority = 3,
        type = "embed"
    }
}

-- Geo-blocking configuration (set to true to block in region)
local GEO_BLOCKED_REGIONS = {
    -- ["US"] = true,  -- Uncomment to block in specific regions
    -- ["UK"] = true,
}

-- ============================================================================
-- GLOBAL STATE
-- ============================================================================

local main_dlg = nil
local config_file = vlc.config.path() .. "vlc-infinity-enhanced-config.json"
local favorites_file = vlc.config.path() .. "vlc-infinity-enhanced-favorites.json"
local history_file = vlc.config.path() .. "vlc-infinity-enhanced-history.json"

local favorites = {}
local watch_history = {}
local current_config = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function fetch_url(url)
    local http = vlc.net.get_http_session()
    if not http then
        vlc.msg.err("VLC Infinity: Failed to get HTTP session")
        return nil
    end
    
    local stream = http:get(url)
    if not stream then
        vlc.msg.err("VLC Infinity: Failed to fetch URL: " .. url)
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

local function check_stream_health(url)
    local timeout = 5
    local start_time = os.time()
    
    local http = vlc.net.get_http_session()
    if not http then return false end
    
    local stream = http:get(url)
    if stream then
        stream:release()
        http:release()
        return true
    end
    
    http:release()
    return false
end

local function save_data(filename, data)
    local file = vlc.io.open(filename, "w")
    if file then
        file:write(vlc.json.encode(data))
        file:close()
        return true
    end
    return false
end

local function load_data(filename)
    local file = vlc.io.open(filename, "r")
    if file then
        local content = file:read()
        file:close()
        if content then
            return vlc.json.decode(content)
        end
    end
    return nil
end

local function get_user_region()
    -- Try to detect user region (simplified - can be enhanced)
    -- Returns region code or nil
    return nil  -- User can configure in settings
end

local function is_geo_blocked()
    local region = current_config.user_region or get_user_region()
    if region and GEO_BLOCKED_REGIONS[region] then
        return true
    end
    return false
end

-- ============================================================================
-- TMDB INTEGRATION
-- ============================================================================

local function search_tmdb_movies(query, page)
    if not current_config.tmdb_api_key or current_config.tmdb_api_key == "" then
        vlc.msg.warn("VLC Infinity: TMDB API key not configured")
        return nil
    end
    
    page = page or 1
    local url = TMDB_BASE_URL .. "/search/movie?api_key=" .. current_config.tmdb_api_key ..
                "&query=" .. vlc.strings.url_encode(query) ..
                "&page=" .. page
    
    vlc.msg.info("VLC Infinity: Searching TMDB for: " .. query)
    local json_content = fetch_url(url)
    
    if json_content then
        local data = vlc.json.decode(json_content)
        if data and data.results then
            return data.results
        end
    end
    return nil
end

local function get_tmdb_movie_details(movie_id)
    if not current_config.tmdb_api_key or current_config.tmdb_api_key == "" then
        return nil
    end
    
    local url = TMDB_BASE_URL .. "/movie/" .. movie_id ..
                "?api_key=" .. current_config.tmdb_api_key ..
                "&append_to_response=external_ids"
    
    local json_content = fetch_url(url)
    if json_content then
        return vlc.json.decode(json_content)
    end
    return nil
end

local function get_tmdb_poster_url(poster_path)
    if poster_path then
        return "https://image.tmdb.org/t/p/w500" .. poster_path
    end
    return nil
end

-- ============================================================================
-- STREAMING LINK RESOLUTION
-- ============================================================================

local function get_streaming_links(imdb_id)
    local links = {}
    
    for i, provider in ipairs(STREAMING_PROVIDERS) do
        local url = provider.url_pattern:gsub("{imdb_id}", imdb_id)
        
        table.insert(links, {
            provider = provider.name,
            url = url,
            priority = provider.priority,
            type = provider.type,
            healthy = false
        })
    end
    
    return links
end

local function get_best_streaming_link(imdb_id)
    local links = get_streaming_links(imdb_id)
    
    -- Sort by priority
    table.sort(links, function(a, b) return a.priority < b.priority end)
    
    -- Check each link's health
    for i, link in ipairs(links) do
        vlc.msg.info("VLC Infinity: Checking " .. link.provider .. " stream...")
        
        if check_stream_health(link.url) then
            vlc.msg.info("VLC Infinity: Found working stream on " .. link.provider)
            link.healthy = true
            return link
        end
    end
    
    vlc.msg.warn("VLC Infinity: No working streams found for IMDb ID: " .. imdb_id)
    return nil
end

-- ============================================================================
-- CONFIGURATION MANAGEMENT
-- ============================================================================

local function load_config()
    local config = load_data(config_file)
    if config then
        return config
    end
    return {
        tmdb_api_key = TMDB_API_KEY,  -- Use pre-configured key
        user_region = "",
        enable_streaming = true,
        preferred_provider = "VidSrc"
    }
end

local function save_config(config)
    current_config = config
    return save_data(config_file, config)
end

-- ============================================================================
-- FAVORITES MANAGEMENT
-- ============================================================================

local function load_favorites()
    local fav = load_data(favorites_file)
    if fav then
        favorites = fav
    else
        favorites = {}
    end
    return favorites
end

local function save_favorites()
    return save_data(favorites_file, favorites)
end

local function add_to_favorites(movie)
    for i, fav in ipairs(favorites) do
        if fav.imdb_id == movie.imdb_id then
            return  -- Already in favorites
        end
    end
    
    table.insert(favorites, {
        title = movie.title,
        imdb_id = movie.imdb_id,
        poster = movie.poster_path,
        year = movie.release_date and movie.release_date:sub(1, 4) or "",
        added_at = os.time()
    })
    
    save_favorites()
    vlc.msg.info("VLC Infinity: Added to favorites: " .. movie.title)
end

-- ============================================================================
-- WATCH HISTORY MANAGEMENT
-- ============================================================================

local function load_history()
    local hist = load_data(history_file)
    if hist then
        watch_history = hist
    else
        watch_history = {}
    end
    return watch_history
end

local function save_history()
    return save_data(history_file, watch_history)
end

local function add_to_history(movie, provider)
    table.insert(watch_history, 1, {
        title = movie.title,
        imdb_id = movie.imdb_id,
        provider = provider,
        watched_at = os.time()
    })
    
    -- Keep only last 100 items
    if #watch_history > 100 then
        watch_history[101] = nil
    end
    
    save_history()
end

-- ============================================================================
-- DIALOG FUNCTIONS
-- ============================================================================

local function browse_movies_dialog(search_query, page)
    if is_geo_blocked() then
        main_dlg:clear()
        main_dlg:add_label("VLC Infinity is not available in your region.", 1, 1, 8, 1)
        main_dlg:show()
        return
    end
    
    search_query = search_query or ""
    page = page or 1
    
    main_dlg:clear()
    main_dlg:add_label("Search Movies (TMDB)", 1, 1, 8, 1)
    
    local search_input = main_dlg:add_text_input(search_query, 1, 2, 8, 1)
    local search_button = main_dlg:add_button("Search", function()
        local query = search_input:get_text()
        if query ~= "" then
            browse_movies_dialog(query, 1)
        end
    end, 1, 3, 4, 1)
    
    local prev_button = main_dlg:add_button("< Prev", function()
        if page > 1 then
            browse_movies_dialog(search_query, page - 1)
        end
    end, 5, 3, 2, 1)
    
    local next_button = main_dlg:add_button("Next >", function()
        browse_movies_dialog(search_query, page + 1)
    end, 7, 3, 2, 1)
    
    local movies = search_tmdb_movies(search_query, page)
    
    if movies and #movies > 0 then
        main_dlg:add_label("Results (" .. #movies .. " found on page " .. page .. "):", 1, 4, 8, 1)
        
        local movie_dropdown = main_dlg:add_dropdown(1, 5, 8, 1)
        local selected_movie_index = 0
        
        for i, movie in ipairs(movies) do
            local title = movie.title
            if movie.release_date then
                title = title .. " (" .. movie.release_date:sub(1, 4) .. ")"
            end
            movie_dropdown:add_value(title, i)
        end
        
        movie_dropdown:set_callback(function(index, value)
            selected_movie_index = index
        end)
        
        main_dlg:add_button("Play Movie", function()
            if selected_movie_index > 0 and movies[selected_movie_index] then
                local movie = movies[selected_movie_index]
                local details = get_tmdb_movie_details(movie.id)
                
                if details and details.external_ids and details.external_ids.imdb_id then
                    local imdb_id = details.external_ids.imdb_id
                    local stream = get_best_streaming_link(imdb_id)
                    
                    if stream then
                        vlc.msg.info("VLC Infinity: Playing " .. movie.title .. " from " .. stream.provider)
                        vlc.playlist.add({ { path = stream.url, name = movie.title } })
                        vlc.playlist.play()
                        
                        add_to_history(movie, stream.provider)
                    else
                        vlc.msg.err("VLC Infinity: No working streams found")
                    end
                end
            end
        end, 1, 6, 4, 1)
        
        main_dlg:add_button("Add to Favorites", function()
            if selected_movie_index > 0 and movies[selected_movie_index] then
                add_to_favorites(movies[selected_movie_index])
            end
        end, 5, 6, 4, 1)
        
        main_dlg:add_label("Powered by TMDB", 1, 7, 8, 1)
    else
        main_dlg:add_label("No movies found. Try a different search.", 1, 4, 8, 1)
    end
    
    main_dlg:show()
end

local function browse_favorites_dialog()
    if is_geo_blocked() then
        main_dlg:clear()
        main_dlg:add_label("VLC Infinity is not available in your region.", 1, 1, 8, 1)
        main_dlg:show()
        return
    end
    
    load_favorites()
    
    main_dlg:clear()
    main_dlg:add_label("Favorite Movies", 1, 1, 8, 1)
    
    if #favorites > 0 then
        local fav_dropdown = main_dlg:add_dropdown(1, 2, 8, 1)
        local selected_fav_index = 0
        
        for i, fav in ipairs(favorites) do
            local title = fav.title
            if fav.year and fav.year ~= "" then
                title = title .. " (" .. fav.year .. ")"
            end
            fav_dropdown:add_value(title, i)
        end
        
        fav_dropdown:set_callback(function(index, value)
            selected_fav_index = index
        end)
        
        main_dlg:add_button("Play Favorite", function()
            if selected_fav_index > 0 and favorites[selected_fav_index] then
                local fav = favorites[selected_fav_index]
                local stream = get_best_streaming_link(fav.imdb_id)
                
                if stream then
                    vlc.msg.info("VLC Infinity: Playing " .. fav.title .. " from " .. stream.provider)
                    vlc.playlist.add({ { path = stream.url, name = fav.title } })
                    vlc.playlist.play()
                    
                    add_to_history(fav, stream.provider)
                else
                    vlc.msg.err("VLC Infinity: No working streams found")
                end
            end
        end, 1, 3, 4, 1)
        
        main_dlg:add_button("Remove", function()
            if selected_fav_index > 0 then
                table.remove(favorites, selected_fav_index)
                save_favorites()
                browse_favorites_dialog()
            end
        end, 5, 3, 4, 1)
    else
        main_dlg:add_label("No favorites yet. Search for movies and add them!", 1, 2, 8, 1)
    end
    
    main_dlg:show()
end

local function browse_history_dialog()
    if is_geo_blocked() then
        main_dlg:clear()
        main_dlg:add_label("VLC Infinity is not available in your region.", 1, 1, 8, 1)
        main_dlg:show()
        return
    end
    
    load_history()
    
    main_dlg:clear()
    main_dlg:add_label("Watch History", 1, 1, 8, 1)
    
    if #watch_history > 0 then
        local hist_dropdown = main_dlg:add_dropdown(1, 2, 8, 1)
        local selected_hist_index = 0
        
        for i, hist in ipairs(watch_history) do
            hist_dropdown:add_value(hist.title .. " (" .. hist.provider .. ")", i)
        end
        
        hist_dropdown:set_callback(function(index, value)
            selected_hist_index = index
        end)
        
        main_dlg:add_button("Play from History", function()
            if selected_hist_index > 0 and watch_history[selected_hist_index] then
                local hist = watch_history[selected_hist_index]
                local stream = get_best_streaming_link(hist.imdb_id)
                
                if stream then
                    vlc.msg.info("VLC Infinity: Playing " .. hist.title .. " from " .. stream.provider)
                    vlc.playlist.add({ { path = stream.url, name = hist.title } })
                    vlc.playlist.play()
                else
                    vlc.msg.err("VLC Infinity: No working streams found")
                end
            end
        end, 1, 3, 4, 1)
        
        main_dlg:add_button("Clear History", function()
            watch_history = {}
            save_history()
            browse_history_dialog()
        end, 5, 3, 4, 1)
    else
        main_dlg:add_label("No watch history yet.", 1, 2, 8, 1)
    end
    
    main_dlg:show()
end

local function settings_dialog()
    main_dlg:clear()
    main_dlg:add_label("VLC Infinity Settings", 1, 1, 8, 1)
    
    current_config = load_config()
    
    main_dlg:add_label("TMDB API Key: Pre-configured", 1, 2, 8, 1)
    main_dlg:add_label("You can now search and stream movies!", 1, 3, 8, 1)
    main_dlg:add_label("(API key is already set up)", 1, 4, 8, 1)
    
    main_dlg:add_label("Your Region (for geo-blocking):", 1, 5, 8, 1)
    local region_input = main_dlg:add_text_input(current_config.user_region or "", 1, 6, 8, 1)
    
    main_dlg:add_button("Save Settings", function()
        current_config.user_region = region_input:get_text()
        save_config(current_config)
        vlc.msg.info("VLC Infinity: Settings saved!")
    end, 1, 7, 8, 1)
    
    main_dlg:show()
end

-- ============================================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================================

function activate()
    current_config = load_config()
    load_favorites()
    load_history()
    
    if not main_dlg then
        main_dlg = vlc.dialog("VLC Infinity Enhanced")
    end
    
    main_dlg:clear()
    main_dlg:add_label("VLC Infinity Enhanced v0.2", 1, 1, 8, 1)
    main_dlg:add_label("Select an option:", 1, 2, 8, 1)
    
    main_dlg:add_button("Search Movies", function()
        browse_movies_dialog()
    end, 1, 3, 4, 1)
    
    main_dlg:add_button("Favorites", function()
        browse_favorites_dialog()
    end, 5, 3, 4, 1)
    
    main_dlg:add_button("History", function()
        browse_history_dialog()
    end, 1, 4, 4, 1)
    
    main_dlg:add_button("Settings", function()
        settings_dialog()
    end, 5, 4, 4, 1)
    
    main_dlg:show()
end

function close()
    if main_dlg then
        main_dlg:delete()
        main_dlg = nil
    end
end

function menu()
    return {"VLC Infinity Enhanced"}
end

function trigger_menu(id)
    activate()
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

vlc.msg.info("VLC Infinity Enhanced v0.2 loaded")
