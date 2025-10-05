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

-- Current state is now managed by the params system

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

-- Initialize current state from the current snapshot
local function init_current_state()
    -- Initialize from current snapshot (A by default)
    params:set("q", params:get("snapshot_a_q"))

    for i = 1, #freqs do
        local level = params:get(string.format("snapshot_a_%02d_level", i))
        local pan = params:get(string.format("snapshot_a_%02d_pan", i))
        local thresh = params:get(string.format("snapshot_a_%02d_thresh", i))

        -- Initialize hidden band parameters
        params:set(string.format("band_%02d_level", i), level)
        params:set(string.format("band_%02d_pan", i), pan)
        params:set(string.format("band_%02d_thresh", i), thresh)
    end
end

-- Initialize snapshot parameters with different default values
local function init_snapshots()
    -- Snapshots are now stored in Norns params with default values
    -- A: Left pan (-1.0), B: Right pan (1.0), C: Center pan (0.0), D: Alternating
    -- No initialization needed - params handle persistence automatically
end

-- Store current state to snapshot
local function store_snapshot(snapshot_name)
    -- Store to Norns params for persistence
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_q", params:get("q"))

    for i = 1, #freqs do
        local level_id = string.format("snapshot_%s_%02d_level", string.lower(snapshot_name), i)
        local pan_id = string.format("snapshot_%s_%02d_pan", string.lower(snapshot_name), i)
        local thresh_id = string.format("snapshot_%s_%02d_thresh", string.lower(snapshot_name), i)

        params:set(level_id, params:get(string.format("band_%02d_level", i)))
        params:set(pan_id, params:get(string.format("band_%02d_pan", i)))
        params:set(thresh_id, params:get(string.format("band_%02d_thresh", i)))
    end
end

-- Explicitly store current state to a snapshot (for manual snapshot updates)
local function save_snapshot(snapshot_name)
    store_snapshot(snapshot_name)
end

-- Recall snapshot
local function recall_snapshot(snapshot_name)
    -- Read from Norns params and update current state
    local snapshot_q = params:get("snapshot_" .. string.lower(snapshot_name) .. "_q")
    params:set("q", snapshot_q)

    for i = 1, #freqs do
        local level_id = string.format("snapshot_%s_%02d_level", string.lower(snapshot_name), i)
        local pan_id = string.format("snapshot_%s_%02d_pan", string.lower(snapshot_name), i)
        local thresh_id = string.format("snapshot_%s_%02d_thresh", string.lower(snapshot_name), i)

        local level_val = params:get(level_id)
        local pan_val = params:get(pan_id)
        local thresh_val = params:get(thresh_id)

        -- Update hidden band parameters (this will update the engine automatically)
        params:set(string.format("band_%02d_level", i), level_val)
        params:set(string.format("band_%02d_pan", i), pan_val)
        params:set(string.format("band_%02d_thresh", i), thresh_val)
    end
end

-- Calculate blend weights for matrix position
local function calculate_blend_weights(x, y)
    -- Clamp coordinates to valid range
    x = math.max(1, math.min(14, x))
    y = math.max(1, math.min(14, y))

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
    local a_w, b_w, c_w, d_w = calculate_blend_weights(x, y)

    -- Calculate target values
    local target_values = {}

    -- Blend global Q from params
    target_values.q = params:get("snapshot_a_q") * a_w +
        params:get("snapshot_b_q") * b_w +
        params:get("snapshot_c_q") * c_w +
        params:get("snapshot_d_q") * d_w

    -- Blend per-band parameters from params
    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)

        target_values[level_id] = params:get(string.format("snapshot_a_%02d_level", i)) * a_w +
            params:get(string.format("snapshot_b_%02d_level", i)) * b_w +
            params:get(string.format("snapshot_c_%02d_level", i)) * c_w +
            params:get(string.format("snapshot_d_%02d_level", i)) * d_w

        target_values[pan_id] = params:get(string.format("snapshot_a_%02d_pan", i)) * a_w +
            params:get(string.format("snapshot_b_%02d_pan", i)) * b_w +
            params:get(string.format("snapshot_c_%02d_pan", i)) * c_w +
            params:get(string.format("snapshot_d_%02d_pan", i)) * d_w

        target_values[thresh_id] = params:get(string.format("snapshot_a_%02d_thresh", i)) * a_w +
            params:get(string.format("snapshot_b_%02d_thresh", i)) * b_w +
            params:get(string.format("snapshot_c_%02d_thresh", i)) * c_w +
            params:get(string.format("snapshot_d_%02d_thresh", i)) * d_w
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


            -- Use current interpolated values as new starting point (ensure they're valid numbers)
            glide_state.start_pos.x = current_x or glide_state.start_pos.x
            glide_state.start_pos.y = current_y or glide_state.start_pos.y
            glide_state.current_values = current_values

            -- Validate that start_pos contains valid numbers
            if not glide_state.start_pos.x or glide_state.start_pos.x ~= glide_state.start_pos.x then
                glide_state.start_pos.x = grid_ui_state.current_matrix_pos.x
            end
            if not glide_state.start_pos.y or glide_state.start_pos.y ~= glide_state.start_pos.y then
                glide_state.start_pos.y = grid_ui_state.current_matrix_pos.y
            end

            -- Update last LED position for smooth visual transition (round to integers)
            glide_state.last_led_pos.x = math.floor(current_x + 0.5)
            glide_state.last_led_pos.y = math.floor(current_y + 0.5)
        else
            -- NORMAL CASE: Start new glide

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
        -- Apply immediately to params (this will update the engine automatically)
        params:set("q", target_values.q)
        for i = 1, #freqs do
            local level_id = string.format("band_%02d_level", i)
            local pan_id = string.format("band_%02d_pan", i)
            local thresh_id = string.format("band_%02d_thresh", i)

            params:set(level_id, target_values[level_id])
            params:set(pan_id, target_values[pan_id])
            params:set(thresh_id, target_values[thresh_id])
        end

        -- Auto-save changes to current snapshot
        store_snapshot(current_snapshot)
    end
end

-- Switch to a snapshot
local function switch_to_snapshot(snapshot_name)
    -- Never store current snapshot to avoid overwriting with path values
    -- Snapshots should only be updated when explicitly storing to them
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

    redraw()                               -- Update the screen to show the new snapshot
    redraw_grid()                          -- Update the grid to show the new snapshot
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

    -- initialize current state and snapshots
    init_current_state()
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
        path_state = path_state,
        glide_state = glide_state
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
        get_current_snapshot = function() return current_snapshot end
    })

    -- start grid refresh metro
    metro_grid_refresh = metro.init(function()
        -- Always redraw grid - glide animation is drawn as part of normal grid drawing
        redraw_grid()
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
                -- Update both parameters and visuals
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
        save_snapshot = save_snapshot,
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
        screen.text_center(string.format("Path Mode: %s", path_state.mode and "ON" or "OFF"))

        -- Path status
        if path_state.mode then
            screen.move(64, 60)
            screen.text_center(string.format("Path: %d points", #path_state.points))

            if path_state.playing then
                screen.move(64, 70)
                screen.text_center(string.format("Playing: %d/%d", path_state.current_point, #path_state.points))
            end
        end
    end

    -- Global Q value
    local q_y = (grid_ui_state.grid_mode == 4) and (path_state.mode and (path_state.playing and 80 or 70) or 60) or 50
    screen.move(64, q_y)
    screen.text_center(string.format("Q: %.2f", params:get("q")))

    -- Glide value
    local glide_y = (grid_ui_state.grid_mode == 4) and (path_state.mode and (path_state.playing and 90 or 80) or 70) or
        60
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

    -- Current state is now managed by the params system

    -- global controls
    params:add_group("global", 1)
    params:add {
        type = "control",
        id = "q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(q)
            if engine and engine.q then engine.q(q) end
            -- Also update current snapshot params
            local snapshot_q_id = string.format("snapshot_%s_q", string.lower(current_snapshot))
            params:set(snapshot_q_id, q)
        end
    }

    params:add {
        type = "control",
        id = "glide",
        name = "glide",
        controlspec = controlspec.new(0, 20, 'lin', 0.01, 0.1, 's'),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    -- Individual band parameters for current state (hidden from UI)
    for i = 1, num do
        params:add {
            type = "control",
            id = string.format("band_%02d_level", i),
            name = string.format("Band %02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12, 'dB'),
            formatter = function(p) return string.format("%.1f dB", p:get()) end,
            hidden = true,
            action = function(level)
                if engine and engine.level then engine.level(i, level) end
            end
        }
        params:add {
            type = "control",
            id = string.format("band_%02d_pan", i),
            name = string.format("Band %02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end,
            hidden = true,
            action = function(pan)
                if engine and engine.pan then engine.pan(i, pan) end
            end
        }
        params:add {
            type = "control",
            id = string.format("band_%02d_thresh", i),
            name = string.format("Band %02d Thresh", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, 0, 'dB'),
            formatter = function(p) return string.format("%.1f dB", p:get()) end,
            hidden = true,
            action = function(thresh)
                if engine and engine.thresh_band then engine.thresh_band(i, thresh) end
            end
        }
    end

    -- Add snapshot parameters for persistence
    -- Snapshot A
    params:add_group("snapshot A", 49)
    params:add {
        type = "control",
        id = "snapshot_a_q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    for i = 1, num do
        local hz = freqs[i]
        params:add {
            type = "control",
            id = string.format("snapshot_a_%02d_level", i),
            name = string.format("%02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_a_%02d_pan", i),
            name = string.format("%02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, -1),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_a_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, 0),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
    end

    -- Snapshot B
    params:add_group("snapshot B", 49)
    params:add {
        type = "control",
        id = "snapshot_b_q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    for i = 1, num do
        local hz = freqs[i]
        params:add {
            type = "control",
            id = string.format("snapshot_b_%02d_level", i),
            name = string.format("%02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_b_%02d_pan", i),
            name = string.format("%02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 1),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_b_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, 0),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
    end

    -- Snapshot C
    params:add_group("snapshot C", 49)
    params:add {
        type = "control",
        id = "snapshot_c_q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    for i = 1, num do
        local hz = freqs[i]
        params:add {
            type = "control",
            id = string.format("snapshot_c_%02d_level", i),
            name = string.format("%02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_c_%02d_pan", i),
            name = string.format("%02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_c_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, 0),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
    end

    -- Snapshot D
    params:add_group("snapshot D", 49)
    params:add {
        type = "control",
        id = "snapshot_d_q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    for i = 1, num do
        local hz = freqs[i]
        params:add {
            type = "control",
            id = string.format("snapshot_d_%02d_level", i),
            name = string.format("%02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_d_%02d_pan", i),
            name = string.format("%02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, (i % 2 == 0) and 1 or -1),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_d_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, 0),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
    end
end
