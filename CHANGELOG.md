# Changelog

## Version 0.3 (2026-07-09)

### Added
- **MovieBox-like UI organization**: Implemented new menu categories: "Home", "TV Shows", "Movies", "Animation", "Most Watched", "Watch Later", "Favorites", "History", "EPG", and "Settings".
- **Watch Later functionality**: Users can now add movies to a "Watch Later" list and play them back.
- **EPG (Electronic Program Guide) with search**: Added an EPG section allowing users to view TV program listings and search for specific programs.
- **Country filtering for TV channels**: `parse_m3u` now extracts country information, enabling filtering of TV channels by country.

### Changed
- **Enhanced streaming health check**: Improved `check_stream_health` with a longer timeout and more detailed logging for better stream reliability.
- **Robust URL fetching**: `fetch_url` now includes `pcall` for safer stream reading and more informative error messages.
- **IMDb ID validation**: Added validation for `imdb_id` in `get_best_streaming_link` to prevent errors with invalid inputs.
- **Menu and Trigger Menu logic**: Refactored `menu` and `trigger_menu` functions to support the new UI categories and ensure correct navigation.

### Fixed
- Resolved conflicting `settings_dialog` definitions.
- Corrected the `trigger_menu` function to properly map menu IDs to their respective dialog functions.
