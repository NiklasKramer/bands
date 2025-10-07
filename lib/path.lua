-- Path mode functionality
local Path = {}

-- Dependencies (will be set by main script)
local grid_ui_state
local apply_blend
local redraw
local metro
local util
local params
local path_state
local glide_state

-- Toggle path mode
function Path.toggle_path_mode()
    path_state.mode = not path_state.mode

    -- If turning off path mode, stop any playing path
    if not path_state.mode and path_state.playing then
        path_state.playing = false
        Path.stop_path_playback()
    end

    redraw() -- Update screen to show path mode status
    -- Grid will be updated by metro_grid_refresh

    -- Show info banner
    if Path.show_banner then
        Path.show_banner(path_state.mode and "Path Mode: On" or "Path Mode: Off")
    end
end

-- Toggle path recording/playback
function Path.toggle_path_recording()
    if not path_state.mode then
        return
    end

    if #path_state.points == 0 then
        return
    end

    path_state.playing = not path_state.playing

    if path_state.playing then
        -- Start playback: begin at first point
        path_state.current_point = 1
        Path.start_path_playback()
    else
        -- Stop playback
        Path.stop_path_playback()
    end

    redraw() -- Update screen to show playback status
    -- Grid will be updated by metro_grid_refresh
end

-- Start path playback
function Path.start_path_playback()
    if #path_state.points == 0 then
        return
    end

    local glide_time = params:get("glide")

    path_state.playback_metro = metro.init(function()
        if path_state.playing and path_state.current_point <= #path_state.points then
            -- Only proceed if glide is not active (wait for glide completion)
            -- Add safety check for glide_state
            if not glide_state or not glide_state.is_gliding then
                local point = path_state.points[path_state.current_point]

                -- Move to the next point in the path (this will trigger glide if enabled)
                apply_blend(point.x, point.y, grid_ui_state.current_matrix_pos.x, grid_ui_state.current_matrix_pos.y)
                grid_ui_state.current_matrix_pos = { x = point.x, y = point.y }

                path_state.current_point = path_state.current_point + 1

                -- Loop back to start when reaching the end
                if path_state.current_point > #path_state.points then
                    path_state.current_point = 1
                end
            end
        end
    end, 0.1) -- Use short interval for checking glide state
    path_state.playback_metro:start()
end

-- Stop path playback
function Path.stop_path_playback()
    if path_state.playback_metro then
        path_state.playback_metro:stop()
        path_state.playback_metro = nil
    end
end

-- Add point to path
function Path.add_path_point(x, y)
    if not path_state.mode then return end

    table.insert(path_state.points, {
        x = x,
        y = y,
        time = util.time()
    })
    -- Grid will be updated by metro_grid_refresh
end

-- Remove point from path
function Path.remove_path_point(x, y)
    if not path_state.mode then return end

    for i = #path_state.points, 1, -1 do
        local point = path_state.points[i]
        if point.x == x and point.y == y then
            table.remove(path_state.points, i)
            -- Grid will be updated by metro_grid_refresh
            return
        end
    end
end

-- Clear entire path
function Path.clear_path()
    path_state.points = {}
    path_state.playing = false
    path_state.current_point = 1
    Path.stop_path_playback()
    redraw()
    -- Grid will be updated by metro_grid_refresh
end

-- Getters
function Path.get_path_mode()
    return path_state.mode
end

function Path.get_path_points()
    return path_state.points
end

function Path.get_path_playing()
    return path_state.playing
end

function Path.get_path_current_point()
    return path_state.current_point
end

-- Initialize dependencies
function Path.init(deps)
    grid_ui_state = deps.grid_ui_state
    apply_blend = deps.apply_blend
    redraw = deps.redraw
    metro = deps.metro
    util = deps.util
    params = deps.params
    path_state = deps.path_state
    glide_state = deps.glide_state
    Path.show_banner = deps.show_banner
end

return Path
