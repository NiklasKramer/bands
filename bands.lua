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
local info_banner_mod = include 'lib/info_banner'

-- params
local controlspec = require 'controlspec'
local util = require 'util'

-- forward declarations
local metro_grid_refresh
local metro_glide
local metro_screen_refresh

-- state
local freqs = {
    80, 150, 250, 350, 500, 630, 800, 1000,
    1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
}

local mode_names = { "levels", "pans", "thresholds", "matrix" }
local band_meters = {}
local band_meter_polls
local grid_ui_state
local selected_band = 1 -- Currently selected band (1-16)

-- Current state is now managed by the params system

-- Update selected band
local function set_selected_band(band)
    if band >= 1 and band <= #freqs then
        selected_band = band
    end
end

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
    -- All snapshots: Center pan (0.0), thresholds (0.0 - all audio passes through)
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

    -- Show info banner
    if params:get("info_banner") == 2 then
        info_banner_mod.show("Snapshot " .. snapshot_name)
    end
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
        glide_state.target_values[thresh_id] = 0.0
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
        glide_state = glide_state,
        show_banner = function(msg)
            if params:get("info_banner") == 2 then
                info_banner_mod.show(msg)
            end
        end
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

    -- initialize info banner
    info_banner_mod.init({
        metro = metro
    })

    -- start grid refresh metro
    metro_grid_refresh = metro.init(function()
        -- Always redraw grid - glide animation is drawn as part of normal grid drawing
        redraw_grid()
    end, 1 / 60)
    metro_grid_refresh:start()

    -- start screen refresh metro
    metro_screen_refresh = metro.init(function()
        redraw()
    end, 1 / 60) -- 60fps for smooth updates
    metro_screen_refresh:start()

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
        set_selected_band = set_selected_band,
        redraw_grid = redraw_grid,
        show_banner = function(msg)
            if params:get("info_banner") == 2 then
                info_banner_mod.show(msg)
            end
        end
    })
end

-- screen redraw
function redraw()
    screen.clear()
    screen.level(15)

    -- Mode-specific screens
    if grid_ui_state.grid_mode == 1 then
        -- No text on levels screen - pure visual meters
        -- Levels screen - Visual meters
        local num_bands = math.min(16, #freqs)
        local meter_width = 3
        local meter_spacing = 5
        local start_x = 8
        local meter_height = 50
        local meter_y = 5 -- Move meters higher

        for i = 1, num_bands do
            local x = start_x + (i - 1) * meter_spacing
            local meter_v = band_meters[i] or 0
            local level_db = params:get(string.format("band_%02d_level", i))

            -- Convert level to meter height (0-50 pixels)
            local level_height = math.max(0, (level_db + 60) * 50 / 72) -- -60dB to +12dB range

            -- Convert audio meter value to dB, then to height
            local meter_db = 0
            if meter_v > 0 then
                meter_db = 20 * math.log10(meter_v) -- Convert linear to dB
            else
                meter_db = -60                      -- Silent
            end
            local peak_height = math.max(0, (meter_db + 60) * 50 / 72)

            -- Draw meter background (dark)
            screen.level(2)
            screen.rect(x, meter_y, meter_width, meter_height)
            screen.fill()

            -- Draw level indicator (green) - always show this
            screen.level(8)
            screen.rect(x, meter_y + meter_height - level_height, meter_width, level_height)
            screen.fill()

            -- Draw meter peak (bright) - show even if no audio
            screen.level(15)
            if peak_height > 0 then
                screen.rect(x, meter_y + meter_height - peak_height, meter_width, peak_height)
                screen.fill()
            else
                -- Show a small indicator even when no audio
                screen.rect(x, meter_y + meter_height - 2, meter_width, 2)
                screen.fill()
            end
        end

        -- Draw cursor below selected band
        if selected_band >= 1 and selected_band <= num_bands then
            local cursor_x = start_x + (selected_band - 1) * meter_spacing
            screen.level(15)
            screen.rect(cursor_x, meter_y + meter_height + 5, meter_width, 3)
            screen.fill()
        end
    elseif grid_ui_state.grid_mode == 2 then
        -- Pans screen - Visual pan indicators
        local num_bands = math.min(16, #freqs)
        local indicator_width = 3
        local indicator_spacing = 5
        local start_x = 8
        local indicator_height = 50
        local indicator_y = 5

        for i = 1, num_bands do
            local x = start_x + (i - 1) * indicator_spacing
            local pan = params:get(string.format("band_%02d_pan", i))

            -- Convert pan (-1 to 1) to position (0 to indicator_height)
            -- Invert so left pan (-1) is at top, right pan (+1) is at bottom
            local pan_position = (1 - pan) * indicator_height / 2
            pan_position = math.max(0, math.min(indicator_height, pan_position))

            -- Draw background line
            screen.level(2)
            screen.rect(x, indicator_y, indicator_width, indicator_height)
            screen.fill()

            -- Draw center line
            screen.level(4)
            screen.rect(x, indicator_y + indicator_height / 2 - 1, indicator_width, 2)
            screen.fill()

            -- Draw pan indicator
            screen.level(15)
            screen.rect(x, indicator_y + indicator_height - pan_position - 2, indicator_width, 4)
            screen.fill()
        end

        -- Draw cursor below selected band
        if selected_band >= 1 and selected_band <= num_bands then
            local cursor_x = start_x + (selected_band - 1) * indicator_spacing
            screen.level(15)
            screen.rect(cursor_x, indicator_y + indicator_height + 5, indicator_width, 3)
            screen.fill()
        end
    elseif grid_ui_state.grid_mode == 3 then
        -- Thresholds screen - Visual threshold indicators
        local num_bands = math.min(16, #freqs)
        local indicator_width = 3
        local indicator_spacing = 5
        local start_x = 8
        local indicator_height = 50
        local indicator_y = 5

        for i = 1, num_bands do
            local x = start_x + (i - 1) * indicator_spacing
            local thresh = params:get(string.format("band_%02d_thresh", i))

            -- Convert threshold (0.0 to 1.0) to position (0 to indicator_height)
            -- Higher thresholds appear higher on screen
            local thresh_position = thresh * indicator_height
            thresh_position = math.max(0, math.min(indicator_height, thresh_position))

            -- Draw background line
            screen.level(2)
            screen.rect(x, indicator_y, indicator_width, indicator_height)
            screen.fill()

            -- Draw threshold indicator
            screen.level(15)
            screen.rect(x, indicator_y + thresh_position - 2, indicator_width, 4)
            screen.fill()
        end

        -- Draw cursor below selected band
        if selected_band >= 1 and selected_band <= num_bands then
            local cursor_x = start_x + (selected_band - 1) * indicator_spacing
            screen.level(15)
            screen.rect(cursor_x, indicator_y + indicator_height + 5, indicator_width, 3)
            screen.fill()
        end
    elseif grid_ui_state.grid_mode == 4 then
        -- Matrix screen - Visual matrix display
        local matrix_size = 14
        local cell_size = 4
        local start_x = 8
        local start_y = 8

        -- Draw matrix grid
        for x = 1, matrix_size do
            for y = 1, matrix_size do
                local cell_x = start_x + (x - 1) * cell_size
                local cell_y = start_y + (y - 1) * cell_size

                -- Current position indicator
                if x == grid_ui_state.current_matrix_pos.x and y == grid_ui_state.current_matrix_pos.y then
                    screen.level(15) -- Bright white for current position
                else
                    screen.level(2)  -- Dark for other positions
                end

                screen.rect(cell_x, cell_y, cell_size - 1, cell_size - 1)
                screen.fill()
            end
        end

        -- Draw path points if in path mode
        if path_state.mode and #path_state.points > 0 then
            screen.level(8) -- Medium brightness for path points
            for i, point in ipairs(path_state.points) do
                local cell_x = start_x + (point.x - 1) * cell_size
                local cell_y = start_y + (point.y - 1) * cell_size
                screen.rect(cell_x, cell_y, cell_size - 1, cell_size - 1)
                screen.fill()
            end
        end

        -- Draw glide animation if active
        if glide_state.is_gliding then
            -- Calculate current glide position with sub-pixel interpolation
            local current_time = util.time()
            local elapsed = current_time - glide_state.glide_time
            local glide_time = params:get("glide")
            local progress = math.min(1, elapsed / glide_time)

            -- Interpolate between start and target positions
            local current_x = glide_state.start_pos.x + (glide_state.target_pos.x - glide_state.start_pos.x) * progress
            local current_y = glide_state.start_pos.y + (glide_state.target_pos.y - glide_state.start_pos.y) * progress

            -- Draw current glide position
            local glide_x = start_x + (current_x - 1) * cell_size
            local glide_y = start_y + (current_y - 1) * cell_size

            -- Bright pulsing effect for glide position
            local pulse = math.sin(util.time() * 10) * 0.5 + 0.5 -- 0 to 1 pulse
            screen.level(8 + math.floor(pulse * 7))              -- 8 to 15 brightness
            screen.rect(glide_x, glide_y, cell_size - 1, cell_size - 1)
            screen.fill()

            -- Draw target position
            if glide_state.target_pos then
                local target_x = start_x + (glide_state.target_pos.x - 1) * cell_size
                local target_y = start_y + (glide_state.target_pos.y - 1) * cell_size
                screen.level(12) -- Medium brightness for target
                screen.rect(target_x, target_y, cell_size - 1, cell_size - 1)
                screen.fill()
            end
        end
    end

    -- Draw info banner on top of everything
    info_banner_mod.draw()

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
    if metro_screen_refresh then
        metro_screen_refresh:stop()
        metro_screen_refresh = nil
    end
    if path_state.playback_metro then
        path_state.playback_metro:stop()
        path_state.playback_metro = nil
    end
end

-- key/enc handlers
function key(n, z)
    if n == 1 then
        -- Key 1: Shift functionality
        grid_ui_state.shift_held = (z == 1)
        -- Update grid shift LED
        if grid_device then
            grid_device:led(16, 8, grid_ui_state.shift_held and 15 or 0)
            grid_device:refresh()
        end
    elseif z == 1 then -- Key press (not release)
        if n == 2 then
            -- Key 2: Reset all bands to default values (current screen only)
            if grid_ui_state.grid_mode == 1 then
                -- Reset levels to -12dB
                for i = 1, #freqs do
                    params:set(string.format("band_%02d_level", i), -12)
                end
                -- Save to current snapshot
                store_snapshot(current_snapshot)
            elseif grid_ui_state.grid_mode == 2 then
                -- Reset pans to center (0)
                for i = 1, #freqs do
                    params:set(string.format("band_%02d_pan", i), 0)
                end
                -- Save to current snapshot
                store_snapshot(current_snapshot)
            elseif grid_ui_state.grid_mode == 3 then
                -- Reset thresholds to 0.0 (all audio passes through)
                for i = 1, #freqs do
                    params:set(string.format("band_%02d_thresh", i), 0.0)
                end
                -- Save to current snapshot
                store_snapshot(current_snapshot)
            end
        elseif n == 3 then
            -- Key 3: Randomize all bands (current screen only)
            if grid_ui_state.grid_mode == 1 then
                -- Randomize levels (-60dB to +12dB)
                for i = 1, #freqs do
                    local random_level = math.random(-60, 12)
                    params:set(string.format("band_%02d_level", i), random_level)
                end
                -- Save to current snapshot
                store_snapshot(current_snapshot)
            elseif grid_ui_state.grid_mode == 2 then
                -- Randomize pans (-1 to +1)
                for i = 1, #freqs do
                    local random_pan = (math.random() - 0.5) * 2
                    params:set(string.format("band_%02d_pan", i), random_pan)
                end
                -- Save to current snapshot
                store_snapshot(current_snapshot)
            elseif grid_ui_state.grid_mode == 3 then
                -- Randomize thresholds (0.0 to 1.0)
                for i = 1, #freqs do
                    local random_thresh = math.random() -- Returns value between 0.0 and 1.0
                    params:set(string.format("band_%02d_thresh", i), random_thresh)
                end
                -- Save to current snapshot
                store_snapshot(current_snapshot)
            end
        end
    end
end

function enc(n, d)
    if n == 2 then
        -- Encoder 2: Select band (only in levels, pans, thresholds modes)
        if grid_ui_state.grid_mode >= 1 and grid_ui_state.grid_mode <= 3 then
            selected_band = selected_band + d
            -- Clamp to bounds: 1-16
            selected_band = math.max(1, math.min(#freqs, selected_band))
        end
    elseif n == 3 then
        -- Encoder 3: Adjust parameter for selected band
        if grid_ui_state.grid_mode >= 1 and grid_ui_state.grid_mode <= 3 then
            if grid_ui_state.shift_held then
                -- Shift held: Adjust all bands
                if grid_ui_state.grid_mode == 1 then
                    -- Adjust all levels
                    local step = d * 0.5 -- 0.5dB per turn for levels
                    for i = 1, #freqs do
                        local current_level = params:get(string.format("band_%02d_level", i))
                        local new_level = math.max(-60, math.min(12, current_level + step))
                        params:set(string.format("band_%02d_level", i), new_level)
                    end
                elseif grid_ui_state.grid_mode == 2 then
                    -- Adjust all pans
                    local step = d * 0.01 -- 0.01 per turn for pan
                    for i = 1, #freqs do
                        local current_pan = params:get(string.format("band_%02d_pan", i))
                        local new_pan = math.max(-1, math.min(1, current_pan + step))
                        params:set(string.format("band_%02d_pan", i), new_pan)
                    end
                elseif grid_ui_state.grid_mode == 3 then
                    -- Adjust all thresholds
                    local step = d * 0.01 -- 0.01 per turn for thresholds (0.0-1.0 range)
                    for i = 1, #freqs do
                        local current_thresh = params:get(string.format("band_%02d_thresh", i))
                        local new_thresh = math.max(0, math.min(1, current_thresh + step))
                        params:set(string.format("band_%02d_thresh", i), new_thresh)
                    end
                end
                -- Save to current snapshot
                store_snapshot(current_snapshot)
            else
                -- No shift: Adjust selected band only
                local band_idx = selected_band

                if grid_ui_state.grid_mode == 1 then
                    -- Adjust level - faster steps for easier adjustment
                    local step = d * 0.5 -- 0.5dB per turn for levels
                    local current_level = params:get(string.format("band_%02d_level", band_idx))
                    local new_level = math.max(-60, math.min(12, current_level + step))
                    params:set(string.format("band_%02d_level", band_idx), new_level)
                    -- Save to current snapshot
                    store_snapshot(current_snapshot)
                elseif grid_ui_state.grid_mode == 2 then
                    -- Adjust pan - fine control
                    local step = d * 0.01 -- 0.01 per turn for pan
                    local current_pan = params:get(string.format("band_%02d_pan", band_idx))
                    local new_pan = math.max(-1, math.min(1, current_pan + step))
                    params:set(string.format("band_%02d_pan", band_idx), new_pan)
                    -- Save to current snapshot
                    store_snapshot(current_snapshot)
                elseif grid_ui_state.grid_mode == 3 then
                    -- Adjust threshold - fine control
                    local step = d * 0.01 -- 0.01 per turn for thresholds (0.0-1.0 range)
                    local current_thresh = params:get(string.format("band_%02d_thresh", band_idx))
                    local new_thresh = math.max(0, math.min(1, current_thresh + step))
                    params:set(string.format("band_%02d_thresh", band_idx), new_thresh)
                    -- Save to current snapshot
                    store_snapshot(current_snapshot)
                end
            end
        end
    end
end

-- parameters
function add_params()
    local num = #freqs

    -- Current state is now managed by the params system

    -- global controls
    params:add_group("global", 3)
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

    params:add {
        type = "option",
        id = "info_banner",
        name = "Info Banner",
        options = { "Off", "On" },
        default = 2
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
            controlspec = controlspec.new(0, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end,
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
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_a_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(0, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
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
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_b_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(0, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
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
            controlspec = controlspec.new(0, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
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
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_d_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(0, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
    end
end
