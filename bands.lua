-- luacheck: globals screen
-- norns script skeleton
-- load Engine Bands
engine.name = "Bands"
local grid_device = grid.connect()

-- modules
local grid_ui = include 'lib/grid_ui'
local meters_mod = include 'lib/meters'
local path_mod = include 'lib/path'
local glide_mod = include 'lib/glide'
local grid_draw_mod = include 'lib/grid_draw'

-- params
local controlspec = require 'controlspec'
local util = require 'util'

-- forward declarations
local metro_grid_refresh
local metro_glide

-- state
local freqs = {
    80, 150, 250, 350, 500, 630, 800, 1000,
    1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
}

local mode_names = { "levels", "pans", "thresholds", "matrix" }
local band_meters = {}
local band_meter_polls
local grid_ui_state

-- Glide state
local glide_state = {
    current_values = {},             -- Current parameter values during glide
    target_values = { q = 1.0 },     -- Target parameter values to glide to (initialize with default)
    glide_time = 0,                  -- Time when glide started
    is_gliding = false,              -- Whether we're currently gliding
    start_pos = { x = 0, y = 0 },    -- Starting matrix position
    target_pos = { x = 0, y = 0 },   -- Target matrix position
    last_led_pos = { x = 0, y = 0 }, -- Last LED position to clear (legacy)
    last_led_positions = {}          -- Array of LED positions for sub-pixel clearing
}

-- Path mode state
local path_state = {
    mode = false,        -- Whether path mode is enabled on matrix
    recording = false,   -- Whether currently recording a path
    points = {},         -- Array of recorded path points
    playing = false,     -- Whether currently playing the path
    current_point = 1,   -- Current point index in playback
    playback_metro = nil -- Metro for path playback timing
}


-- Snapshot system
local snapshots = {
    A = { name = "Snapshot A", params = {} },
    B = { name = "Snapshot B", params = {} },
    C = { name = "Snapshot C", params = {} },
    D = { name = "Snapshot D", params = {} }
}
local current_snapshot = "A"

-- Initialize snapshot parameters with defaults
local function init_snapshots()
    for snapshot_name, snapshot in pairs(snapshots) do
        snapshot.params = {}
        for i = 1, #freqs do
            snapshot.params[i] = {
                level = -12.0,
                pan = 0.0,
                thresh = 0.0
            }
        end
        snapshot.params.q = 1.1
    end

    -- All snapshots start with identical default values
    -- Users can customize them later
    for snapshot_name, snapshot in pairs(snapshots) do
        snapshot.params.q = 1.1
        for i = 1, #freqs do
            snapshot.params[i].level = -12.0
            snapshot.params[i].pan = 0.0
            snapshot.params[i].thresh = 0.0
        end
    end

    print("Snapshots initialized with test data")
end

-- Store current parameters to snapshot
local function store_snapshot(snapshot_name)
    local snapshot = snapshots[snapshot_name]
    if not snapshot then return end

    snapshot.params.q = params:get("q")

    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)

        snapshot.params[i] = {
            level = params:get(level_id),
            pan = params:get(pan_id),
            thresh = params:get(thresh_id)
        }
    end

    print(string.format("Stored %s", snapshot.name))
end

-- Recall snapshot
local function recall_snapshot(snapshot_name)
    local snapshot = snapshots[snapshot_name]
    if not snapshot then return end

    params:set("q", snapshot.params.q)

    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)

        params:set(level_id, snapshot.params[i].level)
        params:set(pan_id, snapshot.params[i].pan)
        params:set(thresh_id, snapshot.params[i].thresh)
    end

    print(string.format("Recalled %s", snapshot.name))
end

-- Calculate blend weights for matrix position
local function calculate_blend_weights(x, y)
    local norm_x = (x - 1) / 13
    local norm_y = (y - 1) / 13

    local a_weight = (1 - norm_x) * (1 - norm_y)
    local b_weight = norm_x * (1 - norm_y)
    local c_weight = (1 - norm_x) * norm_y
    local d_weight = norm_x * norm_y

    return a_weight, b_weight, c_weight, d_weight
end

-- Apply blended parameters to engine
function apply_blend(x, y, old_x, old_y)
    print(string.format("apply_blend called with x=%d, y=%d", x, y))
    local a_w, b_w, c_w, d_w = calculate_blend_weights(x, y)
    print(string.format("Blend weights: A=%.2f B=%.2f C=%.2f D=%.2f", a_w, b_w, c_w, d_w))

    -- Calculate target values
    local target_values = {}

    -- Blend global Q
    target_values.q = snapshots.A.params.q * a_w +
        snapshots.B.params.q * b_w +
        snapshots.C.params.q * c_w +
        snapshots.D.params.q * d_w

    -- Blend per-band parameters
    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)

        target_values[level_id] = snapshots.A.params[i].level * a_w +
            snapshots.B.params[i].level * b_w +
            snapshots.C.params[i].level * c_w +
            snapshots.D.params[i].level * d_w

        target_values[pan_id] = snapshots.A.params[i].pan * a_w +
            snapshots.B.params[i].pan * b_w +
            snapshots.C.params[i].pan * c_w +
            snapshots.D.params[i].pan * d_w

        target_values[thresh_id] = snapshots.A.params[i].thresh * a_w +
            snapshots.B.params[i].thresh * b_w +
            snapshots.C.params[i].thresh * c_w +
            snapshots.D.params[i].thresh * d_w
    end

    -- Check if glide is enabled
    local glide_time_param = params:get("glide")
    if glide_time_param > 0 then
        if glide_state.is_gliding then
            -- INTERRUPTION CASE: Use current interpolated position and values as new start
            local current_time = util.time()
            local elapsed = current_time - glide_state.glide_time
            local progress = math.min(elapsed / glide_time_param, 1.0)

            -- Calculate current interpolated position



            local current_x = glide_state.start_pos.x +
                (glide_state.target_pos.x - glide_state.start_pos.x) * progress
            local current_y = glide_state.start_pos.y +
                (glide_state.target_pos.y - glide_state.start_pos.y) * progress

            -- Calculate current interpolated parameter values
            local current_values = {}
            current_values.q = glide_state.current_values.q +
                (glide_state.target_values.q - glide_state.current_values.q) * progress

            for i = 1, #freqs do
                local level_id = string.format("band_%02d_level", i)
                local pan_id = string.format("band_%02d_pan", i)
                local thresh_id = string.format("band_%02d_thresh", i)

                current_values[level_id] = glide_state.current_values[level_id] +
                    (glide_state.target_values[level_id] - glide_state.current_values[level_id]) * progress
                current_values[pan_id] = glide_state.current_values[pan_id] +
                    (glide_state.target_values[pan_id] - glide_state.current_values[pan_id]) * progress
                current_values[thresh_id] = glide_state.current_values[thresh_id] +
                    (glide_state.target_values[thresh_id] - glide_state.current_values[thresh_id]) * progress
            end

            print(string.format("=== GLIDE INTERRUPTED: was %.1f%% complete, restarting from (%.2f,%.2f) to (%d,%d) ===",
                progress * 100, current_x, current_y, x, y))
            print(string.format("INTERRUPT: Setting last_led_pos to (%.2f,%.2f) -> (%d,%d)",
                current_x, current_y, math.floor(current_x + 0.5), math.floor(current_y + 0.5)))

            -- Use current interpolated values as new starting point (ensure they're valid numbers)
            glide_state.start_pos.x = current_x or glide_state.start_pos.x
            glide_state.start_pos.y = current_y or glide_state.start_pos.y
            glide_state.current_values = current_values

            -- Validate that start_pos contains valid numbers
            if not glide_state.start_pos.x or glide_state.start_pos.x ~= glide_state.start_pos.x then
                print("ERROR: Invalid start_pos.x, using fallback")
                glide_state.start_pos.x = grid_ui_state.current_matrix_pos.x
            end
            if not glide_state.start_pos.y or glide_state.start_pos.y ~= glide_state.start_pos.y then
                print("ERROR: Invalid start_pos.y, using fallback")
                glide_state.start_pos.y = grid_ui_state.current_matrix_pos.y
            end

            -- Update last LED position for smooth visual transition (round to integers)
            glide_state.last_led_pos.x = math.floor(current_x + 0.5)
            glide_state.last_led_pos.y = math.floor(current_y + 0.5)
        else
            -- NORMAL CASE: Start new glide
            print(string.format("=== GLIDE START: from (%d,%d) to (%d,%d) ===",
                old_x or grid_ui_state.current_matrix_pos.x, old_y or grid_ui_state.current_matrix_pos.y, x, y))

            glide_state.start_pos.x = old_x or grid_ui_state.current_matrix_pos.x
            glide_state.start_pos.y = old_y or grid_ui_state.current_matrix_pos.y

            -- Store current parameter values as starting point
            glide_state.current_values = {}
            glide_state.current_values.q = params:get("q")
            for i = 1, #freqs do
                local level_id = string.format("band_%02d_level", i)
                local pan_id = string.format("band_%02d_pan", i)
                local thresh_id = string.format("band_%02d_thresh", i)

                glide_state.current_values[level_id] = params:get(level_id)
                glide_state.current_values[pan_id] = params:get(pan_id)
                glide_state.current_values[thresh_id] = params:get(thresh_id)
            end

            -- Initialize last LED position to start position
            glide_state.last_led_pos.x = glide_state.start_pos.x
            glide_state.last_led_pos.y = glide_state.start_pos.y
        end

        -- Set new target (common for both cases)
        glide_state.target_pos.x = x
        glide_state.target_pos.y = y
        glide_state.target_values = target_values
        glide_state.glide_time = util.time() -- Reset glide start time
        glide_state.is_gliding = true
    else
        -- Apply immediately
        params:set("q", target_values.q)
        for i = 1, #freqs do
            local level_id = string.format("band_%02d_level", i)
            local pan_id = string.format("band_%02d_pan", i)
            local thresh_id = string.format("band_%02d_thresh", i)

            params:set(level_id, target_values[level_id])
            params:set(pan_id, target_values[pan_id])
            params:set(thresh_id, target_values[thresh_id])
        end
    end
    print("Matrix blend applied")
end

-- Switch to a snapshot
local function switch_to_snapshot(snapshot_name)
    store_snapshot(current_snapshot)
    current_snapshot = snapshot_name
    recall_snapshot(snapshot_name)

    -- Stop any ongoing glide when switching snapshots
    glide_state.is_gliding = false

    -- Move matrix position to corresponding corner
    local old_x = grid_ui_state.current_matrix_pos.x
    local old_y = grid_ui_state.current_matrix_pos.y

    if snapshot_name == "A" then
        grid_ui_state.current_matrix_pos = { x = 1, y = 1 }   -- Top-left (2,2 on grid)
    elseif snapshot_name == "B" then
        grid_ui_state.current_matrix_pos = { x = 14, y = 1 }  -- Top-right (15,2 on grid)
    elseif snapshot_name == "C" then
        grid_ui_state.current_matrix_pos = { x = 1, y = 14 }  -- Bottom-left (2,15 on grid)
    elseif snapshot_name == "D" then
        grid_ui_state.current_matrix_pos = { x = 14, y = 14 } -- Bottom-right (15,15 on grid)
    end

    -- Apply the blend for the new matrix position WITHOUT glide (force immediate)
    local saved_glide_param = params:get("glide")
    params:set("glide", 0)                 -- Temporarily disable glide
    apply_blend(grid_ui_state.current_matrix_pos.x, grid_ui_state.current_matrix_pos.y, old_x, old_y)
    params:set("glide", saved_glide_param) -- Restore glide setting

    print(string.format("Switched to Snapshot %s", snapshot_name))
    redraw() -- Update the screen to show the new snapshot
    -- Grid will be updated by metro_grid_refresh
end




-- Grid redraw function
function redraw_grid()
    local g = grid_device
    g:all(0)
    local num = #freqs


    -- Draw main content based on mode
    if grid_ui_state.grid_mode ~= 4 then
        grid_draw_mod.draw_band_controls(g, num)
    else
        grid_draw_mod.draw_matrix_mode(g)
    end

    -- Draw UI controls
    grid_draw_mod.draw_ui_controls(g)

    g:refresh()
end

-- init
function init()
    screen.aa(0)
    screen.line_width(1)

    -- setup parameters
    add_params()
    params:bang()

    -- initialize snapshots
    init_snapshots()

    -- setup grid UI
    grid_ui_state = grid_ui.init(grid_device, freqs, mode_names)
    band_meters = {}

    -- setup meters
    band_meter_polls = meters_mod.init(freqs, band_meters)

    -- initialize glide_state with default values
    glide_state.target_values.q = 1.0
    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)
        glide_state.target_values[level_id] = 0.0
        glide_state.target_values[pan_id] = 0.0
        glide_state.target_values[thresh_id] = 0.5
    end

    -- initialize modules with dependencies
    path_mod.init({
        grid_ui_state = grid_ui_state,
        apply_blend = apply_blend,
        redraw = redraw,
        metro = metro,
        util = util,
        params = params,
        path_state = path_state
    })

    glide_mod.init({
        grid_ui_state = grid_ui_state,
        grid_device = grid_device,
        freqs = freqs,
        params = params,
        path_state = path_state,
        redraw_grid = redraw_grid,
        glide_state = glide_state
    })

    grid_draw_mod.init({
        grid_ui_state = grid_ui_state,
        band_meters = band_meters,
        util = util,
        params = params,
        calculate_blend_weights = calculate_blend_weights,
        path_state = path_state,
        glide_state = glide_state,
        current_snapshot = current_snapshot
    })

    -- start grid refresh metro
    metro_grid_refresh = metro.init(function()
        -- Only redraw grid if not gliding (glide metro handles grid during glide)
        if not glide_state.is_gliding then
            redraw_grid()
        else
            print("GRID REFRESH: Skipped during glide")
        end
    end, 1 / 60)
    metro_grid_refresh:start()

    -- start glide metro
    metro_glide = metro.init(function()
        if glide_state.is_gliding then
            local current_time = util.time()
            local elapsed = current_time - glide_state.glide_time
            local glide_time = params:get("glide")

            if elapsed >= glide_time then
                glide_mod.complete_glide()
            else
                glide_mod.update_glide_progress(elapsed, glide_time)
            end
        end
    end, 1 / 60)
    metro_glide:start()



    redraw()
end

-- grid key handler
function grid.key(x, y, z)
    grid_ui.key(grid_ui_state, x, y, z, redraw, {
        store_snapshot = store_snapshot,
        recall_snapshot = recall_snapshot,
        switch_to_snapshot = switch_to_snapshot,
        apply_blend = apply_blend,
        calculate_blend_weights = calculate_blend_weights,
        toggle_path_mode = path_mod.toggle_path_mode,
        toggle_path_recording = path_mod.toggle_path_recording,
        add_path_point = path_mod.add_path_point,
        remove_path_point = path_mod.remove_path_point,
        clear_path = path_mod.clear_path,
        get_path_mode = path_mod.get_path_mode,
        get_current_snapshot = function() return current_snapshot end,
        get_freqs = function() return freqs end,
        get_mode_names = function() return mode_names end,
        get_band_meters = function() return band_meters end,
        redraw_grid = redraw_grid
    })
end

-- screen redraw
function redraw()
    screen.clear()
    screen.level(15)

    -- Title
    screen.move(64, 10)
    screen.text_center("BANDS")

    -- Current mode
    screen.move(64, 20)
    screen.text_center(mode_names[grid_ui_state.grid_mode])

    -- Current snapshot
    screen.move(64, 30)
    screen.text_center("Snapshot: " .. current_snapshot)

    -- Matrix position (if in matrix mode)
    if grid_ui_state.grid_mode == 4 then
        screen.move(64, 40)
        screen.text_center(string.format("Matrix: %d,%d",
            grid_ui_state.current_matrix_pos.x,
            grid_ui_state.current_matrix_pos.y))

        -- Path mode status
        screen.move(64, 50)
        screen.text_center(string.format("Path Mode: %s", path_mode and "ON" or "OFF"))

        -- Path status
        if path_mode then
            screen.move(64, 60)
            screen.text_center(string.format("Path: %d points", #path_points))

            if path_playing then
                screen.move(64, 70)
                screen.text_center(string.format("Playing: %d/%d", path_current_point, #path_points))
            end
        end
    end

    -- Global Q value
    local q_y = (grid_ui_state.grid_mode == 4) and (path_mode and (path_playing and 80 or 70) or 60) or 50
    screen.move(64, q_y)
    screen.text_center(string.format("Q: %.2f", params:get("q")))

    -- Glide value
    local glide_y = (grid_ui_state.grid_mode == 4) and (path_mode and (path_playing and 90 or 80) or 70) or 60
    screen.move(64, glide_y)
    screen.text_center(string.format("Glide: %.2fs", params:get("glide")))

    -- Instructions
    screen.level(8)
    screen.move(64, 70)
    if grid_ui_state.grid_mode == 1 then
        screen.text_center("Adjust levels")
    elseif grid_ui_state.grid_mode == 2 then
        screen.text_center("Adjust pans")
    elseif grid_ui_state.grid_mode == 3 then
        screen.text_center("Adjust thresholds")
    elseif grid_ui_state.grid_mode == 4 then
        screen.text_center("Blend snapshots")
    end

    screen.update()
end

-- cleanup
function cleanup()
    meters_mod.cleanup(band_meter_polls)
    if metro_grid_refresh then
        metro_grid_refresh:stop()
        metro_grid_refresh = nil
    end
    if metro_glide then
        metro_glide:stop()
        metro_glide = nil
    end
    if path_state.playback_metro then
        path_state.playback_metro:stop()
        path_state.playback_metro = nil
    end
end

-- key/enc handlers
function key(n, z)
    -- add key handling here
end

function enc(n, d)
    -- add encoder handling here
end

-- parameters
function add_params()
    local num = #freqs
    -- global controls
    params:add_group("global", 1)
    params:add {
        type = "control",
        id = "q",
        name = "resonance (Q)",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(q)
            if engine and engine.q then engine.q(q) end
        end
    }

    params:add {
        type = "control",
        id = "glide",
        name = "glide",
        controlspec = controlspec.new(0, 20, 'lin', 0.01, 0.1, 's'),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    for i = 1, num do
        local hz = freqs[i]
        local group_name = string.format("band %02d (%d Hz)", i, hz)
        params:add_group(group_name, 3)

        local lvl_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thr_id = string.format("band_%02d_thresh", i)

        params:add {
            type = "control",
            id = lvl_id,
            name = "level (dB)",
            controlspec = controlspec.new(-60, 6, 'lin', 0.1, -12, 'dB'),
            action = function(db)
                if engine and engine.level then engine.level(i, db) end
            end
        }

        params:add {
            type = "control",
            id = pan_id,
            name = "pan",
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0, ''),
            formatter = function(p) return string.format("%.2f", p:get()) end,
            action = function(pan)
                if engine and engine.pan then engine.pan(i, pan) end
            end
        }

        params:add {
            type = "control",
            id = thr_id,
            name = "threshold",
            controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0, ''),
            formatter = function(p) return string.format("%.2f", p:get()) end,
            action = function(t)
                if engine and engine.thresh_band then engine.thresh_band(i, t) end
            end
        }
    end
end
