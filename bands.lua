-- luacheck: globals screen
-- norns script skeleton
-- load Engine Bands
engine.name = "Bands"
local grid_device = grid.connect()

-- modules
local grid_ui = include 'lib/grid_ui'
local meters_mod = include 'lib/meters'

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
    current_values = {},            -- Current parameter values during glide
    target_values = {},             -- Target parameter values to glide to
    glide_time = 0,                 -- Time when glide started
    is_gliding = false,             -- Whether we're currently gliding
    start_pos = { x = 0, y = 0 },   -- Starting matrix position
    target_pos = { x = 0, y = 0 },  -- Target matrix position
    last_led_pos = { x = 0, y = 0 } -- Last LED position to clear
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
local function apply_blend(x, y, old_x, old_y)
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
            print(string.format("INTERRUPT DEBUG: elapsed=%.3f glide_time=%.3f progress=%.3f", elapsed, glide_time_param,
                progress))
            print(string.format("INTERRUPT DEBUG: start_pos=(%.3f,%.3f) target_pos=(%d,%d)",
                glide_state.start_pos.x or -999, glide_state.start_pos.y or -999,
                glide_state.target_pos.x, glide_state.target_pos.y))

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
    redraw()      -- Update the screen to show the new snapshot
    redraw_grid() -- Update the grid to show the new matrix position
end



-- Grid redraw function
local function redraw_grid()
    local g = grid_device
    g:all(0)
    local num = #freqs

    -- draw band controls (rows 1-15) - only when NOT in matrix mode
    if grid_ui_state.grid_mode ~= 4 then
        for i = 1, math.min(16, num) do
            local meter_v = band_meters[i] or 0
            local col = i

            if grid_ui_state.grid_mode == 1 then
                local level_id = string.format("band_%02d_level", i)
                local level_db = params:get(level_id)
                local level_y = util.round((6 - level_db) * 14 / 66 + 1)
                level_y = util.clamp(level_y, 1, 15)
                for y = level_y, 15 do
                    g:led(col, y, 1)
                end
            elseif grid_ui_state.grid_mode == 2 then
                local pan_id = string.format("band_%02d_pan", i)
                local pan = params:get(pan_id)
                local pan_y = util.round(pan * 7 + 8)
                pan_y = util.clamp(pan_y, 1, 15)
                g:led(col, pan_y, 4)
            elseif grid_ui_state.grid_mode == 3 then
                local thresh_id = string.format("band_%02d_thresh", i)
                local thresh = params:get(thresh_id)
                local thresh_y = util.round((1 - thresh) * 14 + 1)
                thresh_y = util.clamp(thresh_y, 1, 15)
                g:led(col, thresh_y, 4)
            end

            if grid_ui_state.grid_mode == 1 then
                local meter_h = math.floor(util.clamp(meter_v, 0, 1) * 15 + 0.5)
                if meter_h > 0 then
                    local meter_y0 = 15 - meter_h + 1
                    for y = meter_y0, 15 do
                        g:led(col, y, (y == meter_y0) and 15 or 5)
                    end
                end
            end

            if grid_ui_state.grid_mode == 2 then
                g:led(col, 8, 12)
            end
        end
    end

    -- Matrix mode display
    if grid_ui_state.grid_mode == 4 then
        for x = 2, 15 do
            for y = 2, 15 do
                local a_w, b_w, c_w, d_w = calculate_blend_weights(x - 1, y - 1)
                local brightness = 2
                g:led(x, y, brightness)
            end
        end

        -- Draw matrix position indicator
        if glide_state.is_gliding then
            local current_time = util.time()
            local elapsed = current_time - glide_state.glide_time
            local glide_time = params:get("glide")

            if elapsed < glide_time then
                local progress = elapsed / glide_time

                -- Calculate the current glide position
                local glide_x = glide_state.start_pos.x + (glide_state.target_pos.x - glide_state.start_pos.x) * progress
                local glide_y = glide_state.start_pos.y + (glide_state.target_pos.y - glide_state.start_pos.y) * progress

                -- Draw a simple trail by lighting up discrete steps along the path
                local total_steps = math.max(2,
                    math.abs(glide_state.target_pos.x - glide_state.start_pos.x) +
                    math.abs(glide_state.target_pos.y - glide_state.start_pos.y))
                local current_step = math.floor(progress * total_steps)

                -- Debug output
                print(string.format(
                    "Glide trail: start=(%d,%d) target=(%d,%d) progress=%.2f current_step=%d total_steps=%d",
                    glide_state.start_pos.x, glide_state.start_pos.y,
                    glide_state.target_pos.x, glide_state.target_pos.y,
                    progress, current_step, total_steps))

                -- Always draw at least the start position
                if current_step >= 0 then
                    for step = 0, math.max(0, current_step) do
                        local step_progress = step / total_steps
                        local step_x = glide_state.start_pos.x +
                            (glide_state.target_pos.x - glide_state.start_pos.x) * step_progress
                        local step_y = glide_state.start_pos.y +
                            (glide_state.target_pos.y - glide_state.start_pos.y) * step_progress

                        -- Round to integer grid positions
                        step_x = math.floor(step_x + 0.5)
                        step_y = math.floor(step_y + 0.5)

                        -- Much brighter trail to be visible against background (brightness 2)
                        local brightness = math.floor(8 + (12 - 8) * (step / math.max(1, current_step + 1)))
                        print(string.format("  Step %d: pos=(%d,%d) brightness=%d", step, step_x, step_y, brightness))
                        g:led(step_x + 1, step_y + 1, brightness)
                    end
                end

                -- Draw the target position (dim but visible)
                g:led(glide_state.target_pos.x + 1, glide_state.target_pos.y + 1, 6)
            else
                -- Glide complete, show normal bright position
                g:led(grid_ui_state.current_matrix_pos.x + 1, grid_ui_state.current_matrix_pos.y + 1, 15)
            end
        else
            -- Not gliding, show normal bright position
            g:led(grid_ui_state.current_matrix_pos.x + 1, grid_ui_state.current_matrix_pos.y + 1, 15)
        end
    end

    -- Draw snapshot selection buttons in row 16
    local snapshot_buttons = { 7, 8, 9, 10 }
    local snapshot_names = { "A", "B", "C", "D" }
    for i, x in ipairs(snapshot_buttons) do
        local brightness = (current_snapshot == snapshot_names[i]) and 15 or 4
        g:led(x, 16, brightness)
    end

    -- draw mode selector in row 16
    for x = 1, 3 do
        local brightness = (x == grid_ui_state.grid_mode) and 15 or 4
        g:led(x, 16, brightness)
    end

    -- Matrix mode button
    local matrix_brightness = (grid_ui_state.grid_mode == 4) and 15 or 4
    g:led(14, 16, matrix_brightness)

    -- draw shift key at 16,16
    local shift_brightness = grid_ui_state.shift_held and 15 or 4
    g:led(16, 16, shift_brightness)

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
                -- Glide complete
                params:set("q", glide_state.target_values.q)
                for i = 1, #freqs do
                    local level_id = string.format("band_%02d_level", i)
                    local pan_id = string.format("band_%02d_pan", i)
                    local thresh_id = string.format("band_%02d_thresh", i)

                    params:set(level_id, glide_state.target_values[level_id])
                    params:set(pan_id, glide_state.target_values[pan_id])
                    params:set(thresh_id, glide_state.target_values[thresh_id])
                end
                glide_state.is_gliding = false

                -- Update matrix position to final target position
                grid_ui_state.current_matrix_pos.x = glide_state.target_pos.x
                grid_ui_state.current_matrix_pos.y = glide_state.target_pos.y

                print(string.format("=== GLIDE END: reached (%d,%d) ===",
                    glide_state.target_pos.x, glide_state.target_pos.y))

                -- Redraw grid to show final position
                redraw_grid()
            else
                -- Interpolate between current and target values
                local progress = elapsed / glide_time
                local current_q = glide_state.current_values.q +
                    (glide_state.target_values.q - glide_state.current_values.q) * progress
                params:set("q", current_q)

                -- Update matrix position during glide
                grid_ui_state.current_matrix_pos.x = glide_state.start_pos.x +
                    (glide_state.target_pos.x - glide_state.start_pos.x) * progress
                grid_ui_state.current_matrix_pos.y = glide_state.start_pos.y +
                    (glide_state.target_pos.y - glide_state.start_pos.y) * progress

                -- Validate start_pos before calculation
                if not glide_state.start_pos.x or glide_state.start_pos.x ~= glide_state.start_pos.x then
                    print("ERROR: Invalid start_pos.x in metro, stopping glide")
                    glide_state.is_gliding = false
                    return
                end
                if not glide_state.start_pos.y or glide_state.start_pos.y ~= glide_state.start_pos.y then
                    print("ERROR: Invalid start_pos.y in metro, stopping glide")
                    glide_state.is_gliding = false
                    return
                end

                -- Draw the current glide position directly on the grid
                local current_x = glide_state.start_pos.x +
                    (glide_state.target_pos.x - glide_state.start_pos.x) * progress
                local current_y = glide_state.start_pos.y +
                    (glide_state.target_pos.y - glide_state.start_pos.y) * progress

                print(string.format("GLIDE CALC: start=(%.2f,%.2f) target=(%d,%d) progress=%.2f result=(%.2f,%.2f)",
                    glide_state.start_pos.x or -999, glide_state.start_pos.y or -999,
                    glide_state.target_pos.x, glide_state.target_pos.y,
                    progress, current_x or -999, current_y or -999))

                -- Round to integer grid positions
                current_x = math.floor(current_x + 0.5)
                current_y = math.floor(current_y + 0.5)

                -- Ensure we have valid integer coordinates
                current_x = math.max(1, math.min(14, current_x))
                current_y = math.max(1, math.min(14, current_y))

                -- Clear the previous LED position
                if glide_state.last_led_pos.x > 0 and glide_state.last_led_pos.y > 0 then
                    local last_led_x = glide_state.last_led_pos.x + 1
                    local last_led_y = glide_state.last_led_pos.y + 1
                    print(string.format("Clearing previous LED: (%d,%d)", last_led_x, last_led_y))
                    if last_led_x >= 1 and last_led_x <= 16 and last_led_y >= 1 and last_led_y <= 16 then
                        print(string.format("CALLING grid_device:led(%d,%d,2)", last_led_x, last_led_y))
                        grid_device:led(last_led_x, last_led_y, 2) -- Reset to background brightness
                    end
                end

                -- Light up the current position (bright)
                local led_x = current_x + 1
                local led_y = current_y + 1

                -- Check if this is a new position (walking started or moved)
                if glide_state.last_led_pos.x ~= current_x or glide_state.last_led_pos.y ~= current_y then
                    print(string.format(">>> WALKING: LED moved from (%d,%d) to (%d,%d) <<<",
                        glide_state.last_led_pos.x, glide_state.last_led_pos.y, current_x, current_y))
                else
                    print(string.format(">>> STATIC: LED staying at (%d,%d) <<<", current_x, current_y))
                end

                print(string.format("Glide LED: current=(%d,%d) brightness=15", led_x, led_y))
                if led_x >= 1 and led_x <= 16 and led_y >= 1 and led_y <= 16 then
                    print(string.format("CALLING grid_device:led(%d,%d,15)", led_x, led_y))
                    grid_device:led(led_x, led_y, 15)
                    -- Store this position to clear next time
                    glide_state.last_led_pos.x = current_x
                    glide_state.last_led_pos.y = current_y
                end

                -- Also light up the target position (dim)
                local target_led_x = glide_state.target_pos.x + 1
                local target_led_y = glide_state.target_pos.y + 1
                print(string.format("Glide LED: target=(%d,%d) brightness=6", target_led_x, target_led_y))
                if target_led_x >= 1 and target_led_x <= 16 and target_led_y >= 1 and target_led_y <= 16 then
                    print(string.format("CALLING grid_device:led(%d,%d,6)", target_led_x, target_led_y))
                    grid_device:led(target_led_x, target_led_y, 6)
                end

                -- Force grid refresh to apply changes
                grid_device:refresh()

                for i = 1, #freqs do
                    local level_id = string.format("band_%02d_level", i)
                    local pan_id = string.format("band_%02d_pan", i)
                    local thresh_id = string.format("band_%02d_thresh", i)

                    local current_level = glide_state.current_values[level_id] +
                        (glide_state.target_values[level_id] - glide_state.current_values[level_id]) * progress
                    local current_pan = glide_state.current_values[pan_id] +
                        (glide_state.target_values[pan_id] - glide_state.current_values[pan_id]) * progress
                    local current_thresh = glide_state.current_values[thresh_id] +
                        (glide_state.target_values[thresh_id] - glide_state.current_values[thresh_id]) * progress

                    params:set(level_id, current_level)
                    params:set(pan_id, current_pan)
                    params:set(thresh_id, current_thresh)
                end

                -- Grid is updated directly above, no need to call redraw_grid()
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
    end

    -- Global Q value
    screen.move(64, 50)
    screen.text_center(string.format("Q: %.2f", params:get("q")))

    -- Glide value
    screen.move(64, 60)
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
