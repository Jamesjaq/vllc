-- VLC Infinity Lua Extension
-- vlc-infinity.lua

local main_dlg = nil

-- Path for favorites storage
local favorites_file = vlc.config.path() .. "vlc-infinity-favorites.json"
local history_file = vlc.config.path() .. "vlc-infinity-history.json"

-- Helper function to save data to a file
local function save_data(filename, data)
    local file = vlc.io.open(filename, "w")
    if file then
        file:write(vlc.json.encode(data))
        file:close()
        return true
    end
    vlc.msg.err("VLC Infinity: Failed to save data to " .. filename)
    return false
end

-- Helper function to load data from a file
local function load_data(filename)
    local file = vlc.io.open(filename, "r")
    if file then
        local content = file:read()
        file:close()
        return vlc.json.decode(content)
    end
    vlc.msg.warn("VLC Infinity: No data found or failed to load from " .. filename)
    return nil
end

-- Favorites table
local favorites = {}
local watch_history = {}

-- Load favorites on startup
local loaded_favorites = load_data(favorites_file)
if loaded_favorites then
    favorites = loaded_favorites
    vlc.msg.info("VLC Infinity: Loaded " .. #favorites .. " favorites.")
end

local loaded_history = load_data(history_file)
if loaded_history then
    watch_history = loaded_history
    vlc.msg.info("VLC Infinity: Loaded " .. #watch_history .. " watch history entries.")
end


-- Helper function to fetch content from a URL
local function check_stream_health(url)
    local http = vlc.net.get_http_session()
    if not http then
        vlc.msg.err("VLC Infinity: Failed to get HTTP session for health check.")
        return false
    end

    local stream = http:get(url)
    if stream then
        stream:release()
        http:release()
        return true
    else
        vlc.msg.warn("VLC Infinity: Stream health check failed for " .. url)
        http:release()
        return false
    end
end

local function fetch_url(url)
    local http = vlc.net.get_http_session()
    if not http then
        vlc.msg.err("VLC Infinity: Failed to get HTTP session.")
        return nil
    end

    local stream = http:get(url)
    if not stream then
        vlc.msg.err("VLC Infinity: Failed to open URL: " .. url)
        http:release()
        return nil
    end

    local content = ""
    local chunk = stream:read(1024)
    while chunk do
        content = content .. chunk
        chunk = stream:read(1024)
    end

    stream:release()
    http:release()
    return content
end

-- Helper function to parse M3U content
local function parse_m3u(m3u_content)
    local channels = {}
    local lines = {}
    for line in m3u_content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local current_channel = nil
    for i, line in ipairs(lines) do
        if line:match("#EXTINF:.-,(.+)") then
            current_channel = { name = line:match("#EXTINF:.-,(.+)"), url = "", logo = "", group = "" }
            local logo_match = line:match("tvg-logo=\"([^"]+)\"")
            if logo_match then
                current_channel.logo = logo_match
            end
            local group_match = line:match("group-title=\"([^"]+)\"")
            if group_match then
                current_channel.group = group_match
            end
        elseif line:match("^(http|https)://") and current_channel then
            current_channel.url = line
            table.insert(channels, current_channel)
            current_channel = nil
        end
    end
    return channels
end

-- Descriptor: VLC looks for this to provide meta info about our extension
function descriptor()
    return {
        title = "VLC Infinity",
        version = "0.1",
        author = "Manus AI",
        url = "https://github.com/Jamesjaq/vlc",
        description = "Advanced VLC plugin for free cable TV and movies.",
        capabilities = {"menu"}
    }
end

-- Called when the extension is started via the View menu.
function activate()
    vlc.msg.info("VLC Infinity: Extension activated!")
    main_dlg = vlc.dialog("VLC Infinity")
    main_dlg:add_label("Welcome to VLC Infinity! Please select an option from the menu.", 1, 1, 8, 1)
    main_dlg:show()
end

-- Called when the extension dialog is closed by the user.
function close()
    if main_dlg then
        main_dlg:delete()
        main_dlg = nil
    end
    vlc.deactivate()
end

-- Defines the View menu options that is available once the extension is activated.
function menu()
    return {"Browse Channels", "Browse Movies", "Favorites", "History", "EPG", "Settings"}
end

-- Called when a menu option is selected.
local all_channels = {}
local selected_channel_index = 0

local function play_selected_channel()
    if selected_channel_index > 0 and all_channels[selected_channel_index] then
        local channel = all_channels[selected_channel_index]
        vlc.msg.info("VLC Infinity: Attempting to play channel: " .. channel.name .. " (" .. channel.url .. ")")
        if check_stream_health(channel.url) then
            local success, err = pcall(vlc.playlist.add, { { path = channel.url, name = channel.name } })
            if not success then
            vlc.msg.err("VLC Infinity: Failed to play channel " .. channel.name .. ": " .. tostring(err))
        else
            vlc.msg.info("VLC Infinity: Successfully added " .. channel.name .. " to playlist.")
            vlc.playlist.play()
            -- Add to watch history
            table.insert(watch_history, channel)
            save_data(history_file, watch_history)
        end
        else
            vlc.msg.err("VLC Infinity: Stream for " .. channel.name .. " is not healthy.")
        end
    else
        vlc.msg.warn("VLC Infinity: No channel selected or invalid index.")
    end
end

local function add_to_favorites()
    if selected_channel_index > 0 and all_channels[selected_channel_index] then
        local channel = all_channels[selected_channel_index]
        table.insert(favorites, channel)
        save_data(favorites_file, favorites)
        vlc.msg.info("VLC Infinity: Added " .. channel.name .. " to favorites.")
    else
        vlc.msg.warn("VLC Infinity: No channel selected to add to favorites.")
    end
end

local function update_selected_channel(index, value)
    selected_channel_index = index
    vlc.msg.info("VLC Infinity: Selected channel index: " .. selected_channel_index .. ", value: " .. value)
end

local function fetch_movies_from_internet_archive(search_query)
    local base_url = "https://archive.org/advancedsearch.php?q=collection:(feature_films)"
    local query_param = ""
    if search_query and search_query ~= "" then
        query_param = "+AND+title:(" .. vlc.strings.url_encode(search_query) .. ")"
    end
    local url = base_url .. query_param .. "&fl[]=identifier,title,description,date,creator,subject&output=json"
    vlc.msg.info("VLC Infinity: Fetching movies from Internet Archive: " .. url)
    local json_content = fetch_url(url)
    if json_content then
        local data = vlc.json.decode(json_content)
        if data and data.response and data.response.docs then
            return data.response.docs
        end
    end
    return nil
end

local function epg_dialog()
    main_dlg:clear()
    main_dlg:add_label("EPG: Coming Soon!", 1, 1, 8, 1)
    main_dlg:show()
end

local function browse_movies_dialog(search_query, genre_filter)
    main_dlg:clear()
    main_dlg:add_label("Search Movies:", 1, 1, 8, 1)
    local search_input = main_dlg:add_text_input(1, 2, 8, 1, search_query or "")
    local search_button = main_dlg:add_button("Search", function() 
        local query = search_input:get_text()
        vlc.msg.info("VLC Infinity: Searching for movies: " .. query)
        browse_movies_dialog(query, genre_filter)
    end, 1, 3, 8, 1)

    local all_movies = fetch_movies_from_internet_archive(search_query)
    local unique_genres = {}
    if all_movies then
        for i, movie in ipairs(all_movies) do
            if movie.subject then
                if type(movie.subject) == "table" then
                    for j, genre in ipairs(movie.subject) do
                        if not unique_genres[genre] then
                            unique_genres[genre] = true
                        end
                    end
                else
                    if not unique_genres[movie.subject] then
                        unique_genres[movie.subject] = true
                    end
                end
            end
        end
    end

    local genre_dropdown = main_dlg:add_dropdown(1, 4, 8, 1)
    genre_dropdown:add_value("All Genres", "")
    for genre, _ in pairs(unique_genres) do
        genre_dropdown:add_value(genre, genre)
    end
    genre_dropdown:set_callback(function(index, value)
        browse_movies_dialog(search_query, value)
    end)

    local filtered_movies = {}
    if all_movies then
        for i, movie in ipairs(all_movies) do
            local matches_genre = true
            if genre_filter and genre_filter ~= "" then
                if type(movie.subject) == "table" then
                    local found = false
                    for j, genre in ipairs(movie.subject) do
                        if genre == genre_filter then
                            found = true
                            break
                        end
                    end
                    matches_genre = found
                else
                    matches_genre = (movie.subject == genre_filter)
                end
            end
            if matches_genre then
                table.insert(filtered_movies, movie)
            end
        end
    end

    if #filtered_movies > 0 then
        main_dlg:add_label("Movies (" .. #filtered_movies .. " found):", 1, 5, 8, 1)
        local movie_dropdown = main_dlg:add_dropdown(1, 6, 8, 1)
        for i, movie in ipairs(filtered_movies) do
            movie_dropdown:add_value(movie.title, i)
        end
        main_dlg:add_button("Play Movie", function()
            if movie_dropdown:get_selection() > 0 then
                local selected_movie_index = movie_dropdown:get_selection()
                local movie = filtered_movies[selected_movie_index]
                if movie and movie.identifier then
                    local movie_url = "https://archive.org/download/" .. movie.identifier .. "/format=h264" -- Assuming h264 format is available
                    vlc.msg.info("VLC Infinity: Attempting to play movie: " .. movie.title .. " (" .. movie_url .. ")")
                    if check_stream_health(movie_url) then
                        local success, err = pcall(vlc.playlist.add, { { path = movie_url, name = movie.title } })
                        if not success then
                            vlc.msg.err("VLC Infinity: Failed to play movie " .. movie.title .. ": " .. tostring(err))
                        else
                            vlc.msg.info("VLC Infinity: Successfully added " .. movie.title .. " to playlist.")
                            vlc.playlist.play()
                            -- Add to watch history
                            table.insert(watch_history, { name = movie.title, url = movie_url, type = "movie" })
                            save_data(history_file, watch_history)
                        end
                    else
                        vlc.msg.err("VLC Infinity: Movie stream for " .. movie.title .. " is not healthy.")
                    end
                else
                    vlc.msg.warn("VLC Infinity: Invalid movie selection.")
                end
            else
                vlc.msg.warn("VLC Infinity: No movie selected.")
            end
        end, 1, 7, 8, 1)
    else
        main_dlg:add_label("No movies found or failed to fetch.", 1, 5, 8, 1)
    end
    main_dlg:show()
end

local function browse_channels_dialog(search_query, country_filter, category_filter)
    local iptv_url = "https://iptv-org.github.io/iptv/index.m3u"
    vlc.msg.info("VLC Infinity: Fetching IPTV playlist from " .. iptv_url)
    local m3u_content = fetch_url(iptv_url)

    if m3u_content then
        local parsed_channels = parse_m3u(m3u_content)
        all_channels = {}
        for i, channel in ipairs(parsed_channels) do
            local matches_search = not search_query or channel.name:lower():find(search_query:lower())
            local matches_country = not country_filter or channel.country == country_filter
            local matches_category = not category_filter or channel.group == category_filter

            if matches_search and matches_country and matches_category then
                table.insert(all_channels, channel)
            end
        end
        vlc.msg.info("VLC Infinity: Found " .. #all_channels .. " channels.")

        main_dlg:add_label("Select a Channel (" .. #all_channels .. " found):", 1, 6, 8, 1)
        local search_input = main_dlg:add_text_input(1, 2, 8, 1, "")
        local search_button = main_dlg:add_button("Search", function() 
            local query = search_input:get_text()
            vlc.msg.info("VLC Infinity: Searching for: " .. query)
            -- Re-fetch and filter channels based on query
            browse_channels_dialog(query, country_filter, category_filter)
        end, 1, 3, 8, 1)

        local unique_countries = {}
        local unique_categories = {}
        for i, channel in ipairs(parsed_channels) do
            if channel.country and not unique_countries[channel.country] then
                unique_countries[channel.country] = true
            end
            if channel.group and not unique_categories[channel.group] then
                unique_categories[channel.group] = true
            end
        end

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

        local dropdown = main_dlg:add_dropdown(1, 7, 8, 1)
        for i, channel in ipairs(all_channels) do
            dropdown:add_value(channel.name, i)
        end
        dropdown:set_callback(update_selected_channel)

        main_dlg:add_button("Play", play_selected_channel, 1, 8, 4, 1)
        main_dlg:add_button("Add to Favorites", add_to_favorites, 5, 8, 4, 1)
    else
        main_dlg:add_label("Failed to fetch IPTV channels.", 1, 1, 8, 1)
    end
    main_dlg:show()
end

function trigger_menu(id)
    if main_dlg then
        main_dlg:clear()
    else
        main_dlg = vlc.dialog("VLC Infinity")
    end

    if id == 1 then
        vlc.msg.info("VLC Infinity: Browse Channels selected")
        browse_channels_dialog()
    elseif id == 2 then
        vlc.msg.info("VLC Infinity: Browse Movies selected")
        browse_movies_dialog()
    elseif id == 3 then
        vlc.msg.info("VLC Infinity: Favorites selected")
        if #favorites > 0 then
            main_dlg:add_label("Your Favorites:", 1, 1, 8, 1)
            local fav_dropdown = main_dlg:add_dropdown(1, 2, 8, 1)
            all_channels = favorites -- Reuse all_channels for playback logic
            for i, fav in ipairs(favorites) do
                fav_dropdown:add_value(fav.name, i)
            end
            fav_dropdown:set_callback(update_selected_channel)
            main_dlg:add_button("Play Favorite", play_selected_channel, 1, 3, 8, 1)
        else
            main_dlg:add_label("You have no favorites yet.", 1, 1, 8, 1)
        end
    elseif id == 4 then
        vlc.msg.info("VLC Infinity: History selected")
        if #watch_history > 0 then
            main_dlg:add_label("Your Watch History:", 1, 1, 8, 1)
            local history_dropdown = main_dlg:add_dropdown(1, 2, 8, 1)
            all_channels = watch_history -- Reuse all_channels for playback logic
            for i, entry in ipairs(watch_history) do
                history_dropdown:add_value(entry.name, i)
            end
            history_dropdown:set_callback(update_selected_channel)
            main_dlg:add_button("Play from History", play_selected_channel, 1, 3, 8, 1)
        else
            main_dlg:add_label("Your watch history is empty.", 1, 1, 8, 1)
        end
    elseif id == 5 then
        vlc.msg.info("VLC Infinity: EPG selected")
        epg_dialog()
    elseif id == 6 then
        vlc.msg.info("VLC Infinity: Settings selected")
        main_dlg:add_label("Settings: Coming Soon!", 1, 1, 8, 1)
    end
    main_dlg:show()
end

-- Called when the extension is deactivated.
function deactivate()
    vlc.msg.info("VLC Infinity: Extension deactivated!")
    if main_dlg then
        main_dlg:delete()
        main_dlg = nil
    end
end
