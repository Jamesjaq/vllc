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
local watch_later_file = vlc.config.path() .. "vlc-infinity-enhanced-watchlater.json"
local epg_file = vlc.config.path() .. "vlc-infinity-enhanced-epg.json"

local favorites = {}
local watch_history = {}
local watch_later = {}
local current_config = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function fetch_url(url)
    local http = vlc.net.get_http_session()
    if not http then
        vlc.msg.err("VLC Infinity: fetch_url: Failed to get HTTP session.")
        return nil
    end
    
    local stream = http:get(url)
    if not stream then
        vlc.msg.err("VLC Infinity: fetch_url: Failed to fetch URL: " .. url .. ". Check URL or network connection.")
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
        vlc.msg.err("VLC Infinity: fetch_url: Error reading stream from " .. url .. ": " .. tostring(err))
        return nil
    end
    
    return content
end

local function check_stream_health(url)
    local timeout_seconds = 5 -- Increased timeout for more robust checks
    local http = vlc.net.get_http_session()
    if not http then
        vlc.msg.err("VLC Infinity: check_stream_health: Failed to get HTTP session.")
        return false
    end

    local stream = http:get(url, { timeout = timeout_seconds * 1000 }) -- Timeout in milliseconds
    if stream then
        stream:release()
        http:release()
        vlc.msg.info("VLC Infinity: check_stream_health: Stream is healthy: " .. url)
        return true
    else
        vlc.msg.warn("VLC Infinity: check_stream_health: Stream is NOT healthy or timed out: " .. url)
        http:release()
        return false
    end
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
    if not imdb_id or imdb_id == "" then
        vlc.msg.err("VLC Infinity: get_best_streaming_link: Invalid IMDb ID provided.")
        return nil
    end
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

local function add_to_watch_later(movie)
    for i, item in ipairs(watch_later) do
        if item.imdb_id == movie.imdb_id then
            return  -- Already in watch later
        end
    end
    
    table.insert(watch_later, {
        title = movie.title,
        imdb_id = movie.imdb_id,
        poster = movie.poster_path,
        year = movie.release_date and movie.release_date:sub(1, 4) or "",
        added_at = os.time()
    })
    
    save_watch_later()
    vlc.msg.info("VLC Infinity: Added to Watch Later: " .. movie.title)
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

local epg_data = {}

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
    vlc.msg.info("VLC Infinity: Fetching EPG data from " .. epg_url)
    local xml_content = fetch_url(epg_url)
    if xml_content then
        -- A very basic XML parser for EPG data. This will need to be more robust for production.
        local parsed_epg = {}
        -- Regex to extract channel information
        for channel_id, display_name in xml_content:gmatch("<channel id=\"([^"]+)\">\s*<display-name>([^<]+)</display-name>") do
            parsed_epg[channel_id] = {display_name = display_name, programs = {}}
        end
        -- Regex to extract program information
        for start_time, stop_time, channel_id, title, desc in xml_content:gmatch("<programme start=\"([^"]+)\" stop=\"([^"]+)\" channel=\"([^"]+)\">\s*<title>([^<]+)</title>\s*<desc>([^<]+)</desc>") do
            if parsed_epg[channel_id] then
                table.insert(parsed_epg[channel_id].programs, {start_time = start_time, stop_time = stop_time, title = title, description = desc})
            end
        end
        epg_data = parsed_epg
        save_epg_data()
        vlc.msg.info("VLC Infinity: EPG data fetched and parsed.")
    else
        vlc.msg.err("VLC Infinity: Failed to fetch EPG data.")
    end
end

local all_channels = {}

local function parse_m3u(m3u_content)
    local channels = {}
    local lines = {}
    for line in m3u_content:gmatch("[^\\r\\n]+") do
        table.insert(lines, line)
    end

    local current_channel = nil
    for i, line in ipairs(lines) do
        if line:match("#EXTINF:.-,(.+)") then
            current_channel = { name = line:match("#EXTINF:.-,(.+)"), url = "", logo = "", group = "", id = "", country = "" }
            local logo_match = line:match("tvg-logo=\\"([^\"]+)\\"")
            if logo_match then
                current_channel.logo = logo_match
            end
            local group_match = line:match("group-title=\\"([^\"]+)\\"")
            if group_match then
                current_channel.group = group_match
            end
            local id_match = line:match("tvg-id=\\"([^\"]+)\\"")
            if id_match then
                current_channel.id = id_match
            end
            local country_match = line:match("tvg-country=\\"([^\"]+)\\"")
            if country_match then
                current_channel.country = country_match
            end
        elseif line:match("^(http|https)://") and current_channel then
            current_channel.url = line
            table.insert(channels, current_channel)
            current_channel = nil
        end
    end
    return channels
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

local function epg_dialog(search_query)
    main_dlg:clear()
    main_dlg:add_label("EPG (Electronic Program Guide)", 1, 1, 8, 1)

    if current_config.epg_url and current_config.epg_url ~= "" and next(epg_data) == nil then
        main_dlg:add_label("Fetching EPG data... Please wait.", 1, 2, 8, 1)
        main_dlg:show()
        vlc.timer.call_later(0.1, function() -- Delay to allow dialog to show
            fetch_epg_data(current_config.epg_url)
            epg_dialog(search_query) -- Re-open dialog after fetching
        end)
        return
    elseif next(epg_data) == nil then
        main_dlg:add_label("No EPG data loaded. Configure EPG URL in Settings.", 1, 2, 8, 1)
        main_dlg:show()
        return
    end

    local search_input = main_dlg:add_text_input(search_query or "", 1, 2, 8, 1)
    local search_button = main_dlg:add_button("Search", function()
        local query = search_input:get_text()
        epg_dialog(query)
    end, 1, 3, 4, 1)

    local refresh_button = main_dlg:add_button("Refresh EPG", function()
        if current_config.epg_url and current_config.epg_url ~= "" then
            fetch_epg_data(current_config.epg_url)
            epg_dialog(search_query)
        else
            vlc.msg.warn("VLC Infinity: EPG URL not configured. Cannot refresh.")
        end
    end, 5, 3, 4, 1)

    local row = 4
    local found_programs = {}

    for channel_id, channel_info in pairs(epg_data) do
        for i, program in ipairs(channel_info.programs) do
            local program_text = os.date("%H:%M", vlc.date.parse(program.start_time)) .. " - " .. os.date("%H:%M", vlc.date.parse(program.stop_time)) .. " | " .. channel_info.display_name .. ": " .. program.title
            if not search_query or program_text:lower():find(search_query:lower()) then
                table.insert(found_programs, program_text)
            end
        end
    end

    if #found_programs > 0 then
        main_dlg:add_label("Programs found: " .. #found_programs, 1, row, 8, 1)
        row = row + 1
        local program_dropdown = main_dlg:add_dropdown(1, row, 8, 1)
        for i, program_text in ipairs(found_programs) do
            program_dropdown:add_value(program_text, i)
        end
        row = row + 1
    else
        main_dlg:add_label("No programs found.", 1, row, 8, 1)
        row = row + 1
    end

    main_dlg:show()
end

local function display_epg_for_channel(channel_id)
    main_dlg:clear()
    main_dlg:add_label("EPG for Channel: " .. (epg_data[channel_id] and epg_data[channel_id].display_name or channel_id), 1, 1, 8, 1)

    if epg_data[channel_id] and #epg_data[channel_id].programs > 0 then
        local row = 2
        for i, program in ipairs(epg_data[channel_id].programs) do
            if row < 10 then -- Limit displayed programs to fit dialog
                main_dlg:add_label(program.title .. " (" .. program.start_time:sub(9,12) .. "-" .. program.stop_time:sub(9,12) .. ")", 1, row, 8, 1)
                row = row + 1
            else
                main_dlg:add_label("... and more programs.", 1, row, 8, 1)
                break
            end
        end
    else
        main_dlg:add_label("No EPG data available for this channel.", 1, 2, 8, 1)
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
    main_dlg:add_label("Browse TV Channels", 1, 1, 8, 1)

    local iptv_url = "https://iptv-org.github.io/iptv/index.m3u"
    vlc.msg.info("VLC Infinity: Fetching IPTV playlist from " .. iptv_url)
    local m3u_content = fetch_url(iptv_url)

    if m3u_content then
        local parsed_channels = parse_m3u(m3u_content)
        all_channels = {}
        local unique_countries = {}
        local unique_categories = {}

        for i, channel in ipairs(parsed_channels) do
            -- Populate unique countries and categories for filters
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
        vlc.msg.info("VLC Infinity: Found " .. #all_channels .. " channels after filtering.")

        local search_input = main_dlg:add_text_input(search_query or "", 1, 2, 8, 1)
        local search_button = main_dlg:add_button("Search", function()
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
            main_dlg:add_label("Select a Channel (" .. #all_channels .. " found):", 1, 5, 8, 1)
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
                    vlc.msg.info("VLC Infinity: Attempting to play channel: " .. channel.name .. " (" .. channel.url .. ")")
                    if check_stream_health(channel.url) then
                        vlc.playlist.add({ { path = channel.url, name = channel.name } })
                        vlc.playlist.play()
                        add_to_history({title = channel.name, imdb_id = channel.id or channel.name, provider = "IPTV"}, "IPTV")
                    else
                        vlc.msg.err("VLC Infinity: Stream for " .. channel.name .. " is not healthy.")
                    end
                end
            end, 1, 7, 4, 1)

            main_dlg:add_button("Show EPG", function()
                if selected_channel_index > 0 and all_channels[selected_channel_index] then
                    local channel = all_channels[selected_channel_index]
                    if display_epg_for_channel then
                        display_epg_for_channel(channel.id)
                    else
                        vlc.msg.err("VLC Infinity: display_epg_for_channel is not defined yet.")
                    end
                end
            end, 5, 7, 4, 1)

        else
            main_dlg:add_label("No channels found. Try adjusting filters or search.", 1, 5, 8, 1)
        end
    else
        main_dlg:add_label("Failed to fetch IPTV playlist.", 1, 2, 8, 1)
    end

    main_dlg:show()
end



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
        end, 5, 6, 2, 1)
        
        main_dlg:add_button("Watch Later", function()
            if selected_movie_index > 0 and movies[selected_movie_index] then
                add_to_watch_later(movies[selected_movie_index])
            end
        end, 7, 6, 2, 1)
        
        main_dlg:add_label("Powered by TMDB", 1, 7, 8, 1)
    else
        main_dlg:add_label("No movies found. Try a different search.", 1, 4, 8, 1)
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
    main_dlg:add_label("Watch Later Movies", 1, 1, 8, 1)
    
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
                local stream = get_best_streaming_link(wl_item.imdb_id)
                
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
        main_dlg:add_label("No movies in Watch Later yet. Browse movies and add them!", 1, 2, 8, 1)
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
        
        for i, hist_item in ipairs(watch_history) do
            local title = hist_item.title
            if hist_item.watched_at then
                title = title .. " (Watched: " .. os.date("%Y-%m-%d %H:%M", hist_item.watched_at) .. ")"
            end
            hist_dropdown:add_value(title, i)
        end
        
        hist_dropdown:set_callback(function(index, value)
            selected_hist_index = index
        end)
        
        main_dlg:add_button("Play Again", function()
            if selected_hist_index > 0 and watch_history[selected_hist_index] then
                local hist_item = watch_history[selected_hist_index]
                local stream = get_best_streaming_link(hist_item.imdb_id)
                
                if stream then
                    vlc.msg.info("VLC Infinity: Playing " .. hist_item.title .. " from " .. stream.provider)
                    vlc.playlist.add({ { path = stream.url, name = hist_item.title } })
                    vlc.playlist.play()
                else
                    vlc.msg.err("VLC Infinity: No working streams found")
                end
            end
        end, 1, 3, 4, 1)
        
        main_dlg:add_button("Remove", function()
            if selected_hist_index > 0 then
                table.remove(watch_history, selected_hist_index)
                save_history()
                browse_history_dialog()
            end
        end, 5, 3, 4, 1)
    else
        main_dlg:add_label("No watch history yet.", 1, 2, 8, 1)
    end
    
    main_dlg:show()
end

local function settings_dialog()
    main_dlg:clear()
    main_dlg:add_label("Settings", 1, 1, 8, 1)

    main_dlg:add_label("TMDB API Key:", 1, 2, 4, 1)
    local tmdb_key_input = main_dlg:add_text_input(current_config.tmdb_api_key or "", 5, 2, 4, 1)

    main_dlg:add_label("User Region (e.g., US, UK):", 1, 3, 4, 1)
    local region_input = main_dlg:add_text_input(current_config.user_region or "", 5, 3, 4, 1)

    main_dlg:add_label("Enable Streaming:", 1, 4, 4, 1)
    local enable_streaming_checkbox = main_dlg:add_checkbox(current_config.enable_streaming or true, 5, 4, 4, 1)

    main_dlg:add_label("Preferred Streaming Provider:", 1, 5, 4, 1)
    local provider_dropdown = main_dlg:add_dropdown(5, 5, 4, 1)
    for i, provider in ipairs(STREAMING_PROVIDERS) do
        provider_dropdown:add_value(provider.name, provider.name)
    end
    provider_dropdown:set_selected(current_config.preferred_provider or "VidSrc")

    main_dlg:add_label("EPG URL (XMLTV format):", 1, 6, 4, 1)
    local epg_url_input = main_dlg:add_text_input(current_config.epg_url or "", 5, 6, 4, 1)

    main_dlg:add_button("Save Settings", function()
        current_config.tmdb_api_key = tmdb_key_input:get_text()
        current_config.user_region = region_input:get_text()
        current_config.enable_streaming = enable_streaming_checkbox:get_value()
        current_config.preferred_provider = provider_dropdown:get_selected()
        current_config.epg_url = epg_url_input:get_text()
        save_config(current_config)
        vlc.msg.info("VLC Infinity: Settings saved.")
        main_dlg:clear()
        main_dlg:add_label("Settings saved!", 1, 1, 8, 1)
        main_dlg:show()
    end, 1, 7, 8, 1)

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
        main_dlg = vlc.dialog("VLC Infinity Enhanced")
    end
    
    main_dlg:clear()
    main_dlg:add_label("VLC Infinity Enhanced v0.2", 1, 1, 8, 1)
    main_dlg:add_label("Select an option:", 1, 2, 8, 1)
    
    main_dlg:add_button("TV Shows", function()
        browse_channels_dialog()
    end, 1, 3, 4, 1)

    main_dlg:add_button("Movies", function()
        browse_movies_dialog()
    end, 5, 3, 4, 1)

    main_dlg:add_button("Animation", function()
        main_dlg:add_label("Animation: Coming Soon!", 1, 1, 8, 1)
        main_dlg:show()
    end, 1, 4, 4, 1)

    main_dlg:add_button("Most Watched", function()
        main_dlg:add_label("Most Watched: Coming Soon!", 1, 1, 8, 1)
        main_dlg:show()
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

    main_dlg:add_button("EPG", function()
        epg_dialog()
    end, 5, 6, 4, 1)

    main_dlg:add_button("Settings", function()
        settings_dialog()
    end, 1, 7, 8, 1)
    
    main_dlg:show()
end

function close()
    if main_dlg then
        main_dlg:delete()
        main_dlg = nil
    end
end

function menu()
    return {"Home", "TV Shows", "Movies", "Animation", "Most Watched", "Watch Later", "Favorites", "History", "EPG", "Settings"}
end

function trigger_menu(id)
    if main_dlg then
        main_dlg:clear()
    else
        main_dlg = vlc.dialog("VLC Infinity Enhanced")
    end

    if id == 1 then -- Home
        activate() -- Show the main screen
    elseif id == 2 then -- TV Shows
        browse_channels_dialog()
    elseif id == 3 then -- Movies
        browse_movies_dialog()
    elseif id == 4 then -- Animation (placeholder for now)
        main_dlg:add_label("Animation: Coming Soon!", 1, 1, 8, 1)
        main_dlg:show()
    elseif id == 5 then -- Most Watched (placeholder for now)
        main_dlg:add_label("Most Watched: Coming Soon!", 1, 1, 8, 1)
        main_dlg:show()
    elseif id == 6 then -- Watch Later
        browse_watch_later_dialog()
    elseif id == 7 then -- Favorites
        browse_favorites_dialog()
    elseif id == 8 then -- History
        browse_history_dialog()
    elseif id == 9 then -- EPG
        epg_dialog()
    elseif id == 10 then -- Settings
        settings_dialog()
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

vlc.msg.info("VLC Infinity Enhanced v0.2 loaded")
