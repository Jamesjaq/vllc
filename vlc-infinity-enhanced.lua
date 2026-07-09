-- VLC Infinity Enhanced - Full Streaming Movie & TV Browser
-- Integrates TMDB for metadata and multiple streaming sources
-- Version: 0.3 (Fixed & Enhanced)
-- Supports: Movies, TV Series, Animation, Cable TV, EPG

function descriptor()
    return {
        title = "VLC Infinity Enhanced",
        version = "0.3",
        author = "Manus AI",
        url = "https://github.com/Jamesjaq/vlc",
        description = "Advanced VLC plugin for free cable TV, movies, TV series, and streaming content.",
        capabilities = {"menu"}
    }
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local TMDB_API_KEY = "6b15c3bea7b76b7148a835dd50d99175"
local TMDB_BASE_URL = "https://api.themoviedb.org/3"

-- Streaming providers with working direct stream extraction
local STREAMING_PROVIDERS = {
    {
        name = "VidSrc",
        base_url = "https://vidsrc.me/embed/movie/{imdb_id}",
        priority = 1,
        type = "embed"
    },
    {
        name = "VidSrc Pro",
        base_url = "https://vidsrc.pro/embed/movie/{imdb_id}",
        priority = 2,
        type = "embed"
    },
    {
        name = "2embed",
        base_url = "https://www.2embed.cc/embed/{imdb_id}",
        priority = 3,
        type = "embed"
    },
    {
        name = "Multiembed",
        base_url = "https://multiembed.mov/embed/movie/{imdb_id}",
        priority = 4,
        type = "embed"
    }
}

-- TV Series streaming providers
local TV_STREAMING_PROVIDERS = {
    {
        name = "VidSrc TV",
        base_url = "https://vidsrc.me/embed/tv/{imdb_id}/{season}/{episode}",
        priority = 1,
        type = "embed"
    },
    {
        name = "2embed TV",
        base_url = "https://www.2embed.cc/embed/tv/{imdb_id}/{season}/{episode}",
        priority = 2,
        type = "embed"
    }
}

-- Animation genres
local ANIMATION_GENRES = {
    16,  -- Animation
    35,  -- Comedy (often animated)
    10751  -- Family (often animated)
}

-- Geo-blocking configuration
local GEO_BLOCKED_REGIONS = {}

-- ============================================================================
-- GLOBAL STATE
-- ============================================================================

local main_dlg = nil
local function get_config_dir()
    local dir = vlc.config.userdatadir()
    if not dir then
        dir = vlc.config.configdir()
    end
    if not dir then
        dir = vlc.config.homedir()
    end
    
    local sep = (vlc.config.homedir():find("\\") and "\\") or "/"
    if dir:sub(-1) ~= sep then
        dir = dir .. sep
    end
    return dir
end

local config_dir = get_config_dir()
local config_file = config_dir .. "vlc-infinity-enhanced-config.json"
local favorites_file = config_dir .. "vlc-infinity-enhanced-favorites.json"
local history_file = config_dir .. "vlc-infinity-enhanced-history.json"
local watch_later_file = config_dir .. "vlc-infinity-enhanced-watchlater.json"
local epg_file = config_dir .. "vlc-infinity-enhanced-epg.json"

local favorites = {}
local watch_history = {}
local watch_later = {}
local current_config = {}
local epg_data = {}
local all_channels = {}

-- Platform detection
local function get_platform()
    local os_name = vlc.config.homedir():find("\\") and "windows" or "unix"
    if os_name == "unix" then
        -- Further distinguish between Linux, macOS, iOS, Android
        if vlc.config.homedir():find("Android") then
            return "android"
        elseif vlc.config.homedir():find("iPhone") or vlc.config.homedir():find("iPad") then
            return "ios"
        else
            return "linux"
        end
    end
    return os_name
end

local PLATFORM = "linux"
pcall(function() PLATFORM = get_platform() end)

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function fetch_url(url, timeout_ms)
    timeout_ms = timeout_ms or 10000
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
    local success, err = pcall(function()
        while true do
            local chunk = stream:read(4096)
            if not chunk or chunk == "" then break end
            content = content .. chunk
        end
    end)

    stream:release()
    http:release()

    if not success then
        vlc.msg.err("VLC Infinity: Error reading stream: " .. tostring(err))
        return nil
    end
    
    return content
end

local function check_stream_health(url)
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

local function is_geo_blocked()
    local region = current_config.user_region or ""
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
    
    vlc.msg.info("VLC Infinity: Searching TMDB movies for: " .. query)
    local json_content = fetch_url(url)
    
    if json_content then
        local data = vlc.json.decode(json_content)
        if data and data.results then
            return data.results
        end
    end
    return nil
end

local function search_tmdb_tv(query, page)
    if not current_config.tmdb_api_key or current_config.tmdb_api_key == "" then
        vlc.msg.warn("VLC Infinity: TMDB API key not configured")
        return nil
    end
    
    page = page or 1
    local url = TMDB_BASE_URL .. "/search/tv?api_key=" .. current_config.tmdb_api_key ..
                "&query=" .. vlc.strings.url_encode(query) ..
                "&page=" .. page
    
    vlc.msg.info("VLC Infinity: Searching TMDB TV for: " .. query)
    local json_content = fetch_url(url)
    
    if json_content then
        local data = vlc.json.decode(json_content)
        if data and data.results then
            return data.results
        end
    end
    return nil
end

local function search_tmdb_animation(page)
    if not current_config.tmdb_api_key or current_config.tmdb_api_key == "" then
        return nil
    end
    
    page = page or 1
    local url = TMDB_BASE_URL .. "/discover/movie?api_key=" .. current_config.tmdb_api_key ..
                "&with_genres=16&page=" .. page .. "&sort_by=popularity.desc"
    
    vlc.msg.info("VLC Infinity: Fetching animated movies from TMDB")
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

local function get_tmdb_tv_details(tv_id)
    if not current_config.tmdb_api_key or current_config.tmdb_api_key == "" then
        return nil
    end
    
    local url = TMDB_BASE_URL .. "/tv/" .. tv_id ..
                "?api_key=" .. current_config.tmdb_api_key ..
                "&append_to_response=external_ids"
    
    local json_content = fetch_url(url)
    if json_content then
        return vlc.json.decode(json_content)
    end
    return nil
end

local function get_tmdb_tv_season(tv_id, season)
    if not current_config.tmdb_api_key or current_config.tmdb_api_key == "" then
        return nil
    end
    
    local url = TMDB_BASE_URL .. "/tv/" .. tv_id .. "/season/" .. season ..
                "?api_key=" .. current_config.tmdb_api_key
    
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

local function get_movie_streaming_links(imdb_id)
    local links = {}
    
    for i, provider in ipairs(STREAMING_PROVIDERS) do
        local url = provider.base_url:gsub("{imdb_id}", imdb_id)
        
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

local function get_tv_streaming_links(imdb_id, season, episode)
    local links = {}
    season = season or 1
    episode = episode or 1
    
    for i, provider in ipairs(TV_STREAMING_PROVIDERS) do
        local url = provider.base_url:gsub("{imdb_id}", imdb_id)
                                      :gsub("{season}", tostring(season))
                                      :gsub("{episode}", tostring(episode))
        
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

local function get_best_streaming_link(imdb_id, is_tv, season, episode)
    if not imdb_id or imdb_id == "" then
        vlc.msg.err("VLC Infinity: Invalid IMDb ID")
        return nil
    end
    
    local links
    if is_tv then
        links = get_tv_streaming_links(imdb_id, season, episode)
    else
        links = get_movie_streaming_links(imdb_id)
    end
    
    table.sort(links, function(a, b) return a.priority < b.priority end)
    
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
        tmdb_api_key = TMDB_API_KEY,
        user_region = "",
        enable_streaming = true,
        preferred_provider = "VidSrc",
        epg_url = ""
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

local function add_to_favorites(item)
    for i, fav in ipairs(favorites) do
        if fav.imdb_id == item.imdb_id then
            return
        end
    end
    
    table.insert(favorites, {
        title = item.title,
        imdb_id = item.imdb_id,
        poster = item.poster_path,
        year = item.release_date and item.release_date:sub(1, 4) or item.first_air_date and item.first_air_date:sub(1, 4) or "",
        type = item.type or "movie",
        added_at = os.time()
    })
    
    save_favorites()
    vlc.msg.info("VLC Infinity: Added to favorites: " .. item.title)
end

-- ============================================================================
-- WATCH LATER MANAGEMENT
-- ============================================================================

local function load_watch_later()
    local wl = load_data(watch_later_file)
    if wl then
        watch_later = wl
    else
        watch_later = {}
    end
    return watch_later
end

local function save_watch_later()
    return save_data(watch_later_file, watch_later)
end

local function add_to_watch_later(item)
    for i, wl in ipairs(watch_later) do
        if wl.imdb_id == item.imdb_id then
            return
        end
    end
    
    table.insert(watch_later, {
        title = item.title,
        imdb_id = item.imdb_id,
        poster = item.poster_path,
        year = item.release_date and item.release_date:sub(1, 4) or item.first_air_date and item.first_air_date:sub(1, 4) or "",
        type = item.type or "movie",
        added_at = os.time()
    })
    
    save_watch_later()
    vlc.msg.info("VLC Infinity: Added to Watch Later: " .. item.title)
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

local function add_to_history(item, provider)
    table.insert(watch_history, 1, {
        title = item.title,
        imdb_id = item.imdb_id,
        provider = provider,
        watched_at = os.time()
    })
    
    if #watch_history > 100 then
        watch_history[101] = nil
    end
    
    save_history()
end

-- ============================================================================
-- EPG MANAGEMENT
-- ============================================================================

local function load_epg_data()
    local epg = load_data(epg_file)
    if epg then
        epg_data = epg
    else
        epg_data = {}
    end
    return epg_data
end

local function save_epg_data()
    return save_data(epg_file, epg_data)
end

local function fetch_epg_data(epg_url)
    if not epg_url or epg_url == "" then
        vlc.msg.warn("VLC Infinity: EPG URL not configured")
        return
    end
    
    vlc.msg.info("VLC Infinity: Fetching EPG data from " .. epg_url)
    local xml_content = fetch_url(epg_url)
    if xml_content then
        local parsed_epg = {}
        
        for channel_id, display_name in xml_content:gmatch("<channel id=\"([^\"]+)\">[^<]*<display%-name>([^<]+)</display%-name>") do
            parsed_epg[channel_id] = {display_name = display_name, programs = {}}
        end
        
        for start_time, stop_time, channel_id, title in xml_content:gmatch("<programme start=\"([^\"]+)\" stop=\"([^\"]+)\" channel=\"([^\"]+)\">[^<]*<title>([^<]+)</title>") do
            if parsed_epg[channel_id] then
                table.insert(parsed_epg[channel_id].programs, {
                    start_time = start_time,
                    stop_time = stop_time,
                    title = title
                })
            end
        end
        
        epg_data = parsed_epg
        save_epg_data()
        vlc.msg.info("VLC Infinity: EPG data fetched successfully")
    else
        vlc.msg.err("VLC Infinity: Failed to fetch EPG data")
    end
end

-- ============================================================================
-- M3U PARSING FOR CABLE TV
-- ============================================================================

local function parse_m3u(m3u_content)
    local channels = {}
    local lines = {}
    for line in m3u_content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local current_channel = nil
    for i, line in ipairs(lines) do
        if line:match("#EXTINF:") then
            current_channel = {
                name = line:match("#EXTINF:.-,(.+)") or "Unknown",
                url = "",
                logo = "",
                group = "",
                id = "",
                country = ""
            }
            
            local logo_match = line:match("tvg%-logo=\"([^\"]+)\"")
            if logo_match then
                current_channel.logo = logo_match
            end
            
            local group_match = line:match("group%-title=\"([^\"]+)\"")
            if group_match then
                current_channel.group = group_match
            end
            
            local id_match = line:match("tvg%-id=\"([^\"]+)\"")
            if id_match then
                current_channel.id = id_match
            end
            
            local country_match = line:match("tvg%-country=\"([^\"]+)\"")
            if country_match then
                current_channel.country = country_match
            end
        elseif line:match("^https?://") and current_channel then
            current_channel.url = line
            table.insert(channels, current_channel)
            current_channel = nil
        end
    end
    return channels
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
    main_dlg:add_button("Search", function()
        local query = search_input:get_text()
        if query ~= "" then
            browse_movies_dialog(query, 1)
        end
    end, 1, 3, 4, 1)
    
    main_dlg:add_button("< Prev", function()
        if page > 1 then
            browse_movies_dialog(search_query, page - 1)
        end
    end, 5, 3, 2, 1)
    
    main_dlg:add_button("Next >", function()
        browse_movies_dialog(search_query, page + 1)
    end, 7, 3, 2, 1)
    
    local movies = search_tmdb_movies(search_query, page)
    
    if movies and #movies > 0 then
        main_dlg:add_label("Results (" .. #movies .. " on page " .. page .. "):", 1, 4, 8, 1)
        
        local movie_dropdown = main_dlg:add_dropdown(1, 5, 8, 1)
        local selected_movie_index = 0
        
        for i, movie in ipairs(movies) do
            local title = movie.title or "Unknown"
            if movie.release_date then
                title = title .. " (" .. movie.release_date:sub(1, 4) .. ")"
            end
            movie_dropdown:add_value(title, i)
        end
        
        movie_dropdown:set_callback(function(index, value)
            selected_movie_index = index
        end)
        
        main_dlg:add_button("Play", function()
            if selected_movie_index > 0 and movies[selected_movie_index] then
                local movie = movies[selected_movie_index]
                local details = get_tmdb_movie_details(movie.id)
                
                if details and details.external_ids and details.external_ids.imdb_id then
                    local imdb_id = details.external_ids.imdb_id
                    local stream = get_best_streaming_link(imdb_id, false)
                    
                    if stream then
                        vlc.msg.info("VLC Infinity: Playing " .. movie.title .. " from " .. stream.provider)
                        vlc.playlist.add({ { path = stream.url, name = movie.title } })
                        vlc.playlist.play()
                        add_to_history(movie, stream.provider)
                    else
                        vlc.msg.err("VLC Infinity: No working streams found")
                    end
                else
                    vlc.msg.err("VLC Infinity: Could not get IMDb ID for movie")
                end
            end
        end, 1, 6, 2, 1)
        
        main_dlg:add_button("Favorites", function()
            if selected_movie_index > 0 and movies[selected_movie_index] then
                movies[selected_movie_index].type = "movie"
                add_to_favorites(movies[selected_movie_index])
            end
        end, 3, 6, 2, 1)
        
        main_dlg:add_button("Watch Later", function()
            if selected_movie_index > 0 and movies[selected_movie_index] then
                movies[selected_movie_index].type = "movie"
                add_to_watch_later(movies[selected_movie_index])
            end
        end, 5, 6, 2, 1)
        
        main_dlg:add_label("Powered by TMDB", 1, 7, 8, 1)
    else
        main_dlg:add_label("No movies found. Try a different search.", 1, 4, 8, 1)
    end
    
    main_dlg:show()
end

local function browse_tv_dialog(search_query, page)
    if is_geo_blocked() then
        main_dlg:clear()
        main_dlg:add_label("VLC Infinity is not available in your region.", 1, 1, 8, 1)
        main_dlg:show()
        return
    end
    
    search_query = search_query or ""
    page = page or 1
    
    main_dlg:clear()
    main_dlg:add_label("Search TV Series (TMDB)", 1, 1, 8, 1)
    
    local search_input = main_dlg:add_text_input(search_query, 1, 2, 8, 1)
    main_dlg:add_button("Search", function()
        local query = search_input:get_text()
        if query ~= "" then
            browse_tv_dialog(query, 1)
        end
    end, 1, 3, 4, 1)
    
    main_dlg:add_button("< Prev", function()
        if page > 1 then
            browse_tv_dialog(search_query, page - 1)
        end
    end, 5, 3, 2, 1)
    
    main_dlg:add_button("Next >", function()
        browse_tv_dialog(search_query, page + 1)
    end, 7, 3, 2, 1)
    
    local tv_shows = search_tmdb_tv(search_query, page)
    
    if tv_shows and #tv_shows > 0 then
        main_dlg:add_label("Results (" .. #tv_shows .. " on page " .. page .. "):", 1, 4, 8, 1)
        
        local tv_dropdown = main_dlg:add_dropdown(1, 5, 8, 1)
        local selected_tv_index = 0
        
        for i, tv in ipairs(tv_shows) do
            local title = tv.name or "Unknown"
            if tv.first_air_date then
                title = title .. " (" .. tv.first_air_date:sub(1, 4) .. ")"
            end
            tv_dropdown:add_value(title, i)
        end
        
        tv_dropdown:set_callback(function(index, value)
            selected_tv_index = index
        end)
        
        main_dlg:add_button("Play S1E1", function()
            if selected_tv_index > 0 and tv_shows[selected_tv_index] then
                local tv = tv_shows[selected_tv_index]
                local details = get_tmdb_tv_details(tv.id)
                
                if details and details.external_ids and details.external_ids.imdb_id then
                    local imdb_id = details.external_ids.imdb_id
                    local stream = get_best_streaming_link(imdb_id, true, 1, 1)
                    
                    if stream then
                        vlc.msg.info("VLC Infinity: Playing " .. tv.name .. " S1E1 from " .. stream.provider)
                        vlc.playlist.add({ { path = stream.url, name = tv.name .. " S1E1" } })
                        vlc.playlist.play()
                        add_to_history(tv, stream.provider)
                    else
                        vlc.msg.err("VLC Infinity: No working streams found")
                    end
                else
                    vlc.msg.err("VLC Infinity: Could not get IMDb ID for TV series")
                end
            end
        end, 1, 6, 2, 1)
        
        main_dlg:add_button("Favorites", function()
            if selected_tv_index > 0 and tv_shows[selected_tv_index] then
                tv_shows[selected_tv_index].type = "tv"
                add_to_favorites(tv_shows[selected_tv_index])
            end
        end, 3, 6, 2, 1)
        
        main_dlg:add_button("Watch Later", function()
            if selected_tv_index > 0 and tv_shows[selected_tv_index] then
                tv_shows[selected_tv_index].type = "tv"
                add_to_watch_later(tv_shows[selected_tv_index])
            end
        end, 5, 6, 2, 1)
        
        main_dlg:add_label("Powered by TMDB", 1, 7, 8, 1)
    else
        main_dlg:add_label("No TV series found. Try a different search.", 1, 4, 8, 1)
    end
    
    main_dlg:show()
end

local function browse_animation_dialog(page)
    if is_geo_blocked() then
        main_dlg:clear()
        main_dlg:add_label("VLC Infinity is not available in your region.", 1, 1, 8, 1)
        main_dlg:show()
        return
    end
    
    page = page or 1
    
    main_dlg:clear()
    main_dlg:add_label("Animated Movies (TMDB)", 1, 1, 8, 1)
    
    main_dlg:add_button("< Prev", function()
        if page > 1 then
            browse_animation_dialog(page - 1)
        end
    end, 1, 3, 2, 1)
    
    main_dlg:add_button("Refresh", function()
        browse_animation_dialog(page)
    end, 3, 3, 2, 1)
    
    main_dlg:add_button("Next >", function()
        browse_animation_dialog(page + 1)
    end, 5, 3, 2, 1)
    
    local animations = search_tmdb_animation(page)
    
    if animations and #animations > 0 then
        main_dlg:add_label("Results (" .. #animations .. " on page " .. page .. "):", 1, 4, 8, 1)
        
        local anim_dropdown = main_dlg:add_dropdown(1, 5, 8, 1)
        local selected_anim_index = 0
        
        for i, anim in ipairs(animations) do
            local title = anim.title or "Unknown"
            if anim.release_date then
                title = title .. " (" .. anim.release_date:sub(1, 4) .. ")"
            end
            anim_dropdown:add_value(title, i)
        end
        
        anim_dropdown:set_callback(function(index, value)
            selected_anim_index = index
        end)
        
        main_dlg:add_button("Play", function()
            if selected_anim_index > 0 and animations[selected_anim_index] then
                local anim = animations[selected_anim_index]
                local details = get_tmdb_movie_details(anim.id)
                
                if details and details.external_ids and details.external_ids.imdb_id then
                    local imdb_id = details.external_ids.imdb_id
                    local stream = get_best_streaming_link(imdb_id, false)
                    
                    if stream then
                        vlc.msg.info("VLC Infinity: Playing " .. anim.title .. " from " .. stream.provider)
                        vlc.playlist.add({ { path = stream.url, name = anim.title } })
                        vlc.playlist.play()
                        add_to_history(anim, stream.provider)
                    else
                        vlc.msg.err("VLC Infinity: No working streams found")
                    end
                else
                    vlc.msg.err("VLC Infinity: Could not get IMDb ID")
                end
            end
        end, 1, 6, 2, 1)
        
        main_dlg:add_button("Favorites", function()
            if selected_anim_index > 0 and animations[selected_anim_index] then
                animations[selected_anim_index].type = "animation"
                add_to_favorites(animations[selected_anim_index])
            end
        end, 3, 6, 2, 1)
        
        main_dlg:add_button("Watch Later", function()
            if selected_anim_index > 0 and animations[selected_anim_index] then
                animations[selected_anim_index].type = "animation"
                add_to_watch_later(animations[selected_anim_index])
            end
        end, 5, 6, 2, 1)
        
        main_dlg:add_label("Powered by TMDB", 1, 7, 8, 1)
    else
        main_dlg:add_label("No animated movies found.", 1, 4, 8, 1)
    end
    
    main_dlg:show()
end

local function browse_channels_dialog(search_query, country_filter, category_filter)
    if is_geo_blocked() then
        main_dlg:clear()
        main_dlg:add_label("VLC Infinity is not available in your region.", 1, 1, 8, 1)
        main_dlg:show()
        return
    end

    main_dlg:clear()
    main_dlg:add_label("Browse Cable TV Channels", 1, 1, 8, 1)

    local iptv_url = "https://iptv-org.github.io/iptv/index.m3u"
    vlc.msg.info("VLC Infinity: Fetching IPTV playlist from " .. iptv_url)
    local m3u_content = fetch_url(iptv_url)

    if m3u_content then
        local parsed_channels = parse_m3u(m3u_content)
        all_channels = {}
        local unique_countries = {}
        local unique_categories = {}

        for i, channel in ipairs(parsed_channels) do
            if channel.country and not unique_countries[channel.country] then
                unique_countries[channel.country] = true
            end
            if channel.group and not unique_categories[channel.group] then
                unique_categories[channel.group] = true
            end

            local matches_search = not search_query or channel.name:lower():find(search_query:lower())
            local matches_country = not country_filter or channel.country == country_filter
            local matches_category = not category_filter or channel.group == category_filter

            if matches_search and matches_country and matches_category then
                table.insert(all_channels, channel)
            end
        end
        vlc.msg.info("VLC Infinity: Found " .. #all_channels .. " channels")

        local search_input = main_dlg:add_text_input(search_query or "", 1, 2, 8, 1)
        main_dlg:add_button("Search", function()
            local query = search_input:get_text()
            browse_channels_dialog(query, country_filter, category_filter)
        end, 1, 3, 4, 1)

        local country_dropdown = main_dlg:add_dropdown(1, 4, 4, 1)
        country_dropdown:add_value("All Countries", "")
        for country, _ in pairs(unique_countries) do
            country_dropdown:add_value(country, country)
        end
        country_dropdown:set_callback(function(index, value)
            browse_channels_dialog(search_query, value, category_filter)
        end)

        local category_dropdown = main_dlg:add_dropdown(5, 4, 4, 1)
        category_dropdown:add_value("All Categories", "")
        for category, _ in pairs(unique_categories) do
            category_dropdown:add_value(category, category)
        end
        category_dropdown:set_callback(function(index, value)
            browse_channels_dialog(search_query, country_filter, value)
        end)

        if #all_channels > 0 then
            main_dlg:add_label("Select Channel (" .. #all_channels .. " found):", 1, 5, 8, 1)
            local channel_dropdown = main_dlg:add_dropdown(1, 6, 8, 1)
            local selected_channel_index = 0

            for i, channel in ipairs(all_channels) do
                local channel_display = channel.name
                if channel.group and channel.group ~= "" then
                    channel_display = channel_display .. " [" .. channel.group .. "]"
                end
                channel_dropdown:add_value(channel_display, i)
            end

            channel_dropdown:set_callback(function(index, value)
                selected_channel_index = index
            end)

            main_dlg:add_button("Play Channel", function()
                if selected_channel_index > 0 and all_channels[selected_channel_index] then
                    local channel = all_channels[selected_channel_index]
                    vlc.msg.info("VLC Infinity: Playing " .. channel.name)
                    if check_stream_health(channel.url) then
                        vlc.playlist.add({ { path = channel.url, name = channel.name } })
                        vlc.playlist.play()
                        add_to_history({title = channel.name, imdb_id = channel.id or channel.name}, "IPTV")
                    else
                        vlc.msg.err("VLC Infinity: Stream not available")
                    end
                end
            end, 1, 7, 4, 1)

            main_dlg:add_button("Add Favorite", function()
                if selected_channel_index > 0 and all_channels[selected_channel_index] then
                    local channel = all_channels[selected_channel_index]
                    add_to_favorites({
                        title = channel.name,
                        imdb_id = channel.id or channel.name,
                        type = "channel"
                    })
                end
            end, 5, 7, 4, 1)
        else
            main_dlg:add_label("No channels found.", 1, 5, 8, 1)
        end
    else
        main_dlg:add_label("Failed to fetch IPTV playlist.", 1, 2, 8, 1)
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
    main_dlg:add_label("Favorite Movies & Shows", 1, 1, 8, 1)
    
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
        
        main_dlg:add_button("Play", function()
            if selected_fav_index > 0 and favorites[selected_fav_index] then
                local fav = favorites[selected_fav_index]
                local stream = get_best_streaming_link(fav.imdb_id, fav.type == "tv")
                
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
        main_dlg:add_label("No favorites yet.", 1, 2, 8, 1)
    end
    
    main_dlg:show()
end

local function browse_watch_later_dialog()
    if is_geo_blocked() then
        main_dlg:clear()
        main_dlg:add_label("VLC Infinity is not available in your region.", 1, 1, 8, 1)
        main_dlg:show()
        return
    end
    
    load_watch_later()
    
    main_dlg:clear()
    main_dlg:add_label("Watch Later", 1, 1, 8, 1)
    
    if #watch_later > 0 then
        local wl_dropdown = main_dlg:add_dropdown(1, 2, 8, 1)
        local selected_wl_index = 0
        
        for i, wl_item in ipairs(watch_later) do
            local title = wl_item.title
            if wl_item.year and wl_item.year ~= "" then
                title = title .. " (" .. wl_item.year .. ")"
            end
            wl_dropdown:add_value(title, i)
        end
        
        wl_dropdown:set_callback(function(index, value)
            selected_wl_index = index
        end)
        
        main_dlg:add_button("Play", function()
            if selected_wl_index > 0 and watch_later[selected_wl_index] then
                local wl_item = watch_later[selected_wl_index]
                local stream = get_best_streaming_link(wl_item.imdb_id, wl_item.type == "tv")
                
                if stream then
                    vlc.msg.info("VLC Infinity: Playing " .. wl_item.title .. " from " .. stream.provider)
                    vlc.playlist.add({ { path = stream.url, name = wl_item.title } })
                    vlc.playlist.play()
                    add_to_history(wl_item, stream.provider)
                else
                    vlc.msg.err("VLC Infinity: No working streams found")
                end
            end
        end, 1, 3, 4, 1)
        
        main_dlg:add_button("Remove", function()
            if selected_wl_index > 0 then
                table.remove(watch_later, selected_wl_index)
                save_watch_later()
                browse_watch_later_dialog()
            end
        end, 5, 3, 4, 1)
    else
        main_dlg:add_label("No items in Watch Later.", 1, 2, 8, 1)
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
            local title = hist.title .. " (" .. hist.provider .. ")"
            hist_dropdown:add_value(title, i)
        end
        
        hist_dropdown:set_callback(function(index, value)
            selected_hist_index = index
        end)
        
        main_dlg:add_button("Play Again", function()
            if selected_hist_index > 0 and watch_history[selected_hist_index] then
                local hist = watch_history[selected_hist_index]
                local stream = get_best_streaming_link(hist.imdb_id)
                
                if stream then
                    vlc.msg.info("VLC Infinity: Playing " .. hist.title)
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
    
    main_dlg:add_label("TMDB API Key:", 1, 2, 4, 1)
    local tmdb_key_input = main_dlg:add_text_input(current_config.tmdb_api_key or "", 5, 2, 4, 1)

    main_dlg:add_label("User Region:", 1, 3, 4, 1)
    local region_input = main_dlg:add_text_input(current_config.user_region or "", 5, 3, 4, 1)

    main_dlg:add_label("EPG URL:", 1, 4, 4, 1)
    local epg_url_input = main_dlg:add_text_input(current_config.epg_url or "", 5, 4, 4, 1)

    main_dlg:add_button("Save Settings", function()
        current_config.tmdb_api_key = tmdb_key_input:get_text()
        current_config.user_region = region_input:get_text()
        current_config.epg_url = epg_url_input:get_text()
        save_config(current_config)
        vlc.msg.info("VLC Infinity: Settings saved!")
    end, 1, 5, 8, 1)

    main_dlg:show()
end

-- ============================================================================
-- LIFECYCLE FUNCTIONS
-- ============================================================================

function activate()
    current_config = load_config()
    load_favorites()
    load_history()
    load_watch_later()
    load_epg_data()
    
    if not main_dlg then
        main_dlg = vlc.dialog("VLC Infinity Enhanced v0.3")
    end
    
    main_dlg:clear()
    main_dlg:add_label("VLC Infinity Enhanced v0.3", 1, 1, 8, 1)
    main_dlg:add_label("Platform: " .. PLATFORM:upper(), 1, 2, 8, 1)
    
    main_dlg:add_button("Movies", function()
        browse_movies_dialog()
    end, 1, 3, 4, 1)

    main_dlg:add_button("TV Series", function()
        browse_tv_dialog()
    end, 5, 3, 4, 1)

    main_dlg:add_button("Animation", function()
        browse_animation_dialog()
    end, 1, 4, 4, 1)

    main_dlg:add_button("Cable TV", function()
        browse_channels_dialog()
    end, 5, 4, 4, 1)

    main_dlg:add_button("Watch Later", function()
        browse_watch_later_dialog()
    end, 1, 5, 4, 1)

    main_dlg:add_button("Favorites", function()
        browse_favorites_dialog()
    end, 5, 5, 4, 1)

    main_dlg:add_button("History", function()
        browse_history_dialog()
    end, 1, 6, 4, 1)

    main_dlg:add_button("Settings", function()
        settings_dialog()
    end, 5, 6, 4, 1)
    
    main_dlg:show()
end

function close()
    if main_dlg then
        main_dlg:delete()
        main_dlg = nil
    end
end

function menu()
    return {"Home", "Movies", "TV Series", "Animation", "Cable TV", "Watch Later", "Favorites", "History", "Settings"}
end

function trigger_menu(id)
    if not main_dlg then
        main_dlg = vlc.dialog("VLC Infinity Enhanced v0.3")
    else
        main_dlg:clear()
    end

    if id == 1 then
        activate()
    elseif id == 2 then
        browse_movies_dialog()
    elseif id == 3 then
        browse_tv_dialog()
    elseif id == 4 then
        browse_animation_dialog()
    elseif id == 5 then
        browse_channels_dialog()
    elseif id == 6 then
        browse_watch_later_dialog()
    elseif id == 7 then
        browse_favorites_dialog()
    elseif id == 8 then
        browse_history_dialog()
    elseif id == 9 then
        settings_dialog()
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

vlc.msg.info("VLC Infinity Enhanced v0.3 loaded (Platform: " .. PLATFORM .. ")")
