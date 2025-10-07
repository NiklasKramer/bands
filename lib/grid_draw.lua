-- Grid drawing functionality
local GridDraw = {}

-- Dependencies (will be set by main script)
local grid_ui_state
local band_meters
local util
local params
local calculate_blend_weights
local path_state
local glide_state
local get_current_snapshot

-- Draw band controls (levels, pans, thresholds)
function GridDraw.draw_band_controls(g, num)
    for i = 1, math.min(16, num) do
        local meter_v = band_meters[i] or 0
        local col = i

        -- Draw parameter indicators
        GridDraw.draw_parameter_indicators(g, col, i)

        -- Draw meters
        if grid_ui_state.grid_mode == 1 then
            GridDraw.draw_level_meters(g, col, i, meter_v)
        elseif grid_ui_state.grid_mode == 2 then
            GridDraw.draw_pan_meters(g, col)
        end
    end
end

-- Draw parameter indicators
function GridDraw.draw_parameter_indicators(g, col, i)
    if grid_ui_state.grid_mode == 1 then
        -- Get level from current state (passed as dependency)
        local level_db = params:get(string.format("band_%02d_level", i))
        local level_y = util.round((6 - level_db) * 14 / 66 + 1)
        level_y = util.clamp(level_y, 1, 15)
        for y = level_y, 15 do
            g:led(col, y, 1)
        end
    elseif grid_ui_state.grid_mode == 2 then
        -- Get pan from current state (passed as dependency)
        local pan = params:get(string.format("band_%02d_pan", i))
        local pan_y = util.round(pan * 7 + 8)
        pan_y = util.clamp(pan_y, 1, 15)
        g:led(col, pan_y, 8)
    elseif grid_ui_state.grid_mode == 3 then
        -- Get threshold from current state (passed as dependency)
        local thresh = params:get(string.format("band_%02d_thresh", i))
        local thresh_y = util.round(thresh * 14 + 1)
        thresh_y = util.clamp(thresh_y, 1, 15)
        g:led(col, thresh_y, 4)
    end
end

-- Draw level meters with sub-pixel interpolation
function GridDraw.draw_level_meters(g, col, i, meter_v)
    -- Sub-pixel brightness interpolation for meters
    local meter_height_float = util.clamp(meter_v, 0, 1) * 15
    local meter_height_int = math.floor(meter_height_float)
    local meter_frac = meter_height_float - meter_height_int

    if meter_height_float > 0 then
        local meter_y0 = 15 - meter_height_int + 1

        -- Draw full brightness LEDs for the solid part
        for y = meter_y0, 15 do
            g:led(col, y, (y == meter_y0) and 15 or 5)
        end

        -- Add sub-pixel LED with interpolated brightness
        if meter_frac > 0 and meter_y0 > 1 then
            local sub_pixel_y = meter_y0 - 1
            -- Brightness based on fractional part: 2 (background) + fraction * (15-2)
            local sub_pixel_brightness = math.floor(2 + meter_frac * 13)
            sub_pixel_brightness = math.max(2, math.min(15, sub_pixel_brightness))
            g:led(col, sub_pixel_y, sub_pixel_brightness)
        end
    end
end

-- Draw pan meters
function GridDraw.draw_pan_meters(g, col)
    g:led(col, 8, 4)
end

-- Draw matrix mode
function GridDraw.draw_matrix_mode(g)
    -- Draw matrix background
    GridDraw.draw_matrix_background(g)

    -- Draw path mode elements
    GridDraw.draw_path_mode_elements(g)

    -- Draw matrix position indicator
    GridDraw.draw_matrix_position_indicator(g)
end

-- Draw matrix background
function GridDraw.draw_matrix_background(g)
    for x = 2, 15 do
        for y = 2, 15 do
            local a_w, b_w, c_w, d_w = calculate_blend_weights(x - 1, y - 1)
            local brightness = 2
            g:led(x, y, brightness)
        end
    end
end

-- Draw path mode elements
function GridDraw.draw_path_mode_elements(g)
    if grid_ui_state.grid_mode == 4 then -- Matrix mode
        -- Path mode toggle indicator at (16,1)
        local path_brightness = path_state.mode and 15 or 4
        g:led(16, 1, path_brightness)

        -- Path recording start/stop indicator at (1,1)
        local record_brightness = path_state.playing and 15 or 4
        g:led(1, 1, record_brightness)

        -- Draw path points if path mode is enabled AND we're in matrix mode
        -- Keep them visible all the time (not just when not gliding)
        if path_state.mode and #path_state.points > 0 then
            for i, point in ipairs(path_state.points) do
                local led_x = math.floor(point.x + 1)
                local led_y = math.floor(point.y + 1)
                -- All path points are bright (12), only the current point being processed is brightest (15)
                local brightness = (i == path_state.current_point and path_state.playing) and 15 or 12
                g:led(led_x, led_y, brightness)
            end
        end
    end
end

-- Draw matrix position indicator
function GridDraw.draw_matrix_position_indicator(g)
    if glide_state.is_gliding then
        GridDraw.draw_glide_trail(g)
    else
        -- Not gliding, show normal bright position
        local pos_x = math.floor(grid_ui_state.current_matrix_pos.x + 1)
        local pos_y = math.floor(grid_ui_state.current_matrix_pos.y + 1)
        g:led(pos_x, pos_y, 15)
    end
end

-- Draw glide trail
function GridDraw.draw_glide_trail(g)
    local current_time = util.time()
    local elapsed = current_time - glide_state.glide_time
    local glide_time = params:get("glide")

    if elapsed < glide_time then
        local progress = elapsed / glide_time

        -- Calculate the current glide position (single calculation)
        local current_x = glide_state.start_pos.x + (glide_state.target_pos.x - glide_state.start_pos.x) * progress
        local current_y = glide_state.start_pos.y + (glide_state.target_pos.y - glide_state.start_pos.y) * progress

        -- Draw 2x2 grid with sub-pixel interpolation for smooth animation
        local x_floor = math.floor(current_x)
        local y_floor = math.floor(current_y)
        local x_frac = current_x - x_floor
        local y_frac = current_y - y_floor

        -- Clamp to valid matrix bounds (1-14)
        x_floor = math.max(1, math.min(13, x_floor)) -- Max 13 so x_floor+1 <= 14
        y_floor = math.max(1, math.min(13, y_floor)) -- Max 13 so y_floor+1 <= 14

        -- Calculate brightness for 2x2 grid using bilinear interpolation
        local positions = {
            { x = x_floor,     y = y_floor,     weight = (1 - x_frac) * (1 - y_frac) },
            { x = x_floor + 1, y = y_floor,     weight = x_frac * (1 - y_frac) },
            { x = x_floor,     y = y_floor + 1, weight = (1 - x_frac) * y_frac },
            { x = x_floor + 1, y = y_floor + 1, weight = x_frac * y_frac }
        }

        -- Light up the 2x2 grid with interpolated brightness
        for _, pos in ipairs(positions) do
            if pos.x >= 1 and pos.x <= 14 and pos.y >= 1 and pos.y <= 14 then
                -- Convert matrix position to grid position (add 1)
                local grid_x = pos.x + 1
                local grid_y = pos.y + 1

                -- Calculate brightness: 2 (background) + weight * (15-2) range
                local brightness = math.floor(2 + pos.weight * 13 + 0.5)
                brightness = math.max(2, math.min(15, brightness))

                -- Ensure coordinates and brightness are integers
                grid_x = math.floor(grid_x)
                grid_y = math.floor(grid_y)
                brightness = math.floor(brightness)

                g:led(grid_x, grid_y, brightness)
            end
        end
    else
        -- Glide complete, show normal bright position
        local pos_x = math.floor(grid_ui_state.current_matrix_pos.x + 1)
        local pos_y = math.floor(grid_ui_state.current_matrix_pos.y + 1)
        g:led(pos_x, pos_y, 15)
    end
end

-- Draw UI controls
function GridDraw.draw_ui_controls(g)
    -- Draw snapshot selection buttons in row 16
    GridDraw.draw_snapshot_buttons(g)

    -- Draw mode selector in row 16
    GridDraw.draw_mode_selector(g)

    -- Draw matrix mode button
    GridDraw.draw_matrix_button(g)

    -- Draw shift key
    GridDraw.draw_shift_key(g)
end

-- Draw snapshot buttons
function GridDraw.draw_snapshot_buttons(g)
    local snapshot_buttons = { 7, 8, 9, 10 }
    local snapshot_names = { "A", "B", "C", "D" }

    -- Get blend weights from current matrix position
    local a_w, b_w, c_w, d_w = calculate_blend_weights(
        grid_ui_state.current_matrix_pos.x,
        grid_ui_state.current_matrix_pos.y
    )
    local weights = { a_w, b_w, c_w, d_w }

    for i, x in ipairs(snapshot_buttons) do
        -- Map weight (0-1) to brightness (4-15)
        local weight_brightness = math.floor(4 + weights[i] * 11)
        g:led(x, 16, weight_brightness)
    end
end

-- Draw mode selector
function GridDraw.draw_mode_selector(g)
    for x = 1, 3 do
        local brightness = (x == grid_ui_state.grid_mode) and 15 or 4
        g:led(x, 16, brightness)
    end
end

-- Draw matrix button
function GridDraw.draw_matrix_button(g)
    local matrix_brightness = (grid_ui_state.grid_mode == 4) and 15 or 4
    g:led(14, 16, matrix_brightness)
end

-- Draw shift key
function GridDraw.draw_shift_key(g)
    local shift_brightness = grid_ui_state.shift_held and 15 or 4
    g:led(16, 16, shift_brightness)
end

-- Initialize dependencies
function GridDraw.init(deps)
    grid_ui_state = deps.grid_ui_state
    band_meters = deps.band_meters
    util = deps.util
    params = deps.params
    calculate_blend_weights = deps.calculate_blend_weights
    path_state = deps.path_state
    glide_state = deps.glide_state
    get_current_snapshot = deps.get_current_snapshot
end

return GridDraw
