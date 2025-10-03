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

-- Toggle path mode
function Path.toggle_path_mode()
    print(string.format("Path toggle called: current path_mode = %s", tostring(path_state.mode)))
    path_state.mode = not path_state.mode
    print(string.format("Path mode: %s", path_state.mode and "ON" or "OFF"))
    redraw() -- Update screen to show path mode status
    -- Grid will be updated by metro_grid_refresh
end

-- Toggle path recording/playback
function Path.toggle_path_recording()
    print(string.format("Path toggle: path_mode=%s, path_state.points=%d, path_state.playing=%s",
        path_state.mode, #path_state.points, path_state.playing))

    if not path_state.mode then
        print("Path recording: Path mode must be enabled first")
        return
    end

    if #path_state.points == 0 then
        print("Path recording: No path points to play")
        return
    end

    path_state.playing = not path_state.playing

    if path_state.playing then
        -- Start playback: begin at first point
        path_state.current_point = 1
        Path.start_path_playback()
        print("Path playback: STARTED")
    else
        -- Stop playback
        Path.stop_path_playback()
        print("Path playback: STOPPED")
    end

    redraw() -- Update screen to show playback status
    -- Grid will be updated by metro_grid_refresh
end

-- Start path playback
function Path.start_path_playback()
    if #path_state.points == 0 then
        print("Path playback: No points to play")
        return
    end

    local glide_time = params:get("glide")
    print(string.format("Path playback: Starting with %d points, glide time: %.2fs", #path_state.points, glide_time))
    print(string.format("Path playback: path_state.playing = %s", tostring(path_state.playing)))

    path_state.playback_metro = metro.init(function()
        print(string.format("Path metro called: playing=%s, current_point=%d, total_points=%d",
            tostring(path_state.playing), path_state.current_point, #path_state.points))
        if path_state.playing and path_state.current_point <= #path_state.points then
            local point = path_state.points[path_state.current_point]
            print(string.format("Path playback: Moving to point %d (%d,%d)", path_state.current_point, point.x, point.y))

            -- Move to the next point in the path
            apply_blend(point.x, point.y, grid_ui_state.current_matrix_pos.x, grid_ui_state.current_matrix_pos.y)
            grid_ui_state.current_matrix_pos = { x = point.x, y = point.y }

            path_state.current_point = path_state.current_point + 1

            -- Loop back to start when reaching the end
            if path_state.current_point > #path_state.points then
                path_state.current_point = 1
                print("Path playback: Looping back to start")
            end
        end
    end, glide_time) -- Use glide time as interval between points
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
            print(string.format("Path: Removed point (%d,%d) - Total: %d", x, y, #path_state.points))
            -- Grid will be updated by metro_grid_refresh
            return
        end
    end
    print(string.format("Path: Point (%d,%d) not found in path", x, y))
end

-- Clear entire path
function Path.clear_path()
    path_state.points = {}
    path_state.playing = false
    path_state.current_point = 1
    Path.stop_path_playback()
    print("Path: Cleared all points")
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
end

return Path
