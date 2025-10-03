-- Glide functionality
local Glide = {}

-- Dependencies (will be set by main script)
local grid_ui_state
local grid_device
local freqs
local params
local path_state
local redraw_grid
local glide_state


-- Complete glide animation
function Glide.complete_glide()
    -- Debug: Check if target_values are valid
    print(string.format("COMPLETE_GLIDE DEBUG: target_values.q = %s", tostring(glide_state.target_values.q)))
    print(string.format("COMPLETE_GLIDE DEBUG: glide_state.is_gliding = %s", tostring(glide_state.is_gliding)))

    if not glide_state.is_gliding then
        print("ERROR: complete_glide called but not gliding, ignoring")
        return
    end

    if not glide_state.target_values.q then
        print("ERROR: target_values.q is nil, aborting glide completion")
        glide_state.is_gliding = false
        return
    end

    -- Set final parameter values
    params:set("q", glide_state.target_values.q)
    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)

        -- Check if values exist before setting
        if glide_state.target_values[level_id] then
            params:set(level_id, glide_state.target_values[level_id])
        end
        if glide_state.target_values[pan_id] then
            params:set(pan_id, glide_state.target_values[pan_id])
        end
        if glide_state.target_values[thresh_id] then
            params:set(thresh_id, glide_state.target_values[thresh_id])
        end
    end

    glide_state.is_gliding = false

    -- Update matrix position to final target position
    grid_ui_state.current_matrix_pos.x = glide_state.target_pos.x
    grid_ui_state.current_matrix_pos.y = glide_state.target_pos.y

    print(string.format("=== GLIDE END: reached (%d,%d) ===",
        glide_state.target_pos.x, glide_state.target_pos.y))

    -- Redraw grid to show final position
    redraw_grid()
end

-- Update glide progress
function Glide.update_glide_progress(elapsed, glide_time)
    local progress = elapsed / glide_time

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

    -- Update parameters
    Glide.update_glide_parameters(progress)

    -- Update visual display
    Glide.update_glide_visuals(progress)

    -- Update grid display
    Glide.update_glide_grid_display()
end

-- Update glide parameters
function Glide.update_glide_parameters(progress)
    local current_q = glide_state.current_values.q +
        (glide_state.target_values.q - glide_state.current_values.q) * progress
    params:set("q", current_q)

    -- Update matrix position during glide
    grid_ui_state.current_matrix_pos.x = glide_state.start_pos.x +
        (glide_state.target_pos.x - glide_state.start_pos.x) * progress
    grid_ui_state.current_matrix_pos.y = glide_state.start_pos.y +
        (glide_state.target_pos.y - glide_state.start_pos.y) * progress

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
end

-- Update glide visuals
function Glide.update_glide_visuals(progress)
    -- Draw the current glide position directly on the grid
    local current_x = glide_state.start_pos.x +
        (glide_state.target_pos.x - glide_state.start_pos.x) * progress
    local current_y = glide_state.start_pos.y +
        (glide_state.target_pos.y - glide_state.start_pos.y) * progress

    print(string.format("GLIDE CALC: start=(%.2f,%.2f) target=(%d,%d) progress=%.2f result=(%.2f,%.2f)",
        glide_state.start_pos.x or -999, glide_state.start_pos.y or -999,
        glide_state.target_pos.x, glide_state.target_pos.y,
        progress, current_x or -999, current_y or -999))

    -- Clear previous sub-pixel LEDs
    Glide.clear_previous_glide_leds()

    -- Draw sub-pixel interpolation
    Glide.draw_sub_pixel_interpolation(current_x, current_y)

    -- Draw target indicator
    Glide.draw_target_indicator()
end

-- Clear previous glide LEDs
function Glide.clear_previous_glide_leds()
    if glide_state.last_led_positions then
        for _, pos in ipairs(glide_state.last_led_positions) do
            if pos.x >= 1 and pos.x <= 16 and pos.y >= 1 and pos.y <= 16 then
                grid_device:led(pos.x, pos.y, 2) -- Reset to background brightness
            end
        end
    end
end

-- Draw sub-pixel interpolation
function Glide.draw_sub_pixel_interpolation(current_x, current_y)
    -- Calculate 2x2 grid positions around the fractional coordinate
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

    -- Store positions for clearing next time
    glide_state.last_led_positions = {}

    -- Light up the 2x2 grid with interpolated brightness
    for _, pos in ipairs(positions) do
        if pos.x >= 1 and pos.x <= 14 and pos.y >= 1 and pos.y <= 14 then
            -- Convert matrix position to grid position (add 1)
            local grid_x = pos.x + 1
            local grid_y = pos.y + 1

            -- Calculate brightness: 2 (background) + weight * (15-2) range
            local brightness = math.floor(2 + pos.weight * 13 + 0.5)
            brightness = math.max(2, math.min(15, brightness))

            grid_device:led(grid_x, grid_y, brightness)

            -- Store for clearing next time
            table.insert(glide_state.last_led_positions, { x = grid_x, y = grid_y })

            print(string.format("SUB-PIXEL: grid(%d,%d) weight=%.3f brightness=%d",
                grid_x, grid_y, pos.weight, brightness))
        end
    end
end

-- Draw target indicator
function Glide.draw_target_indicator()
    local target_led_x = glide_state.target_pos.x + 1
    local target_led_y = glide_state.target_pos.y + 1
    if target_led_x >= 1 and target_led_x <= 16 and target_led_y >= 1 and target_led_y <= 16 then
        -- Check if target overlaps with any of our interpolated positions
        local overlaps = false
        for _, pos in ipairs(glide_state.last_led_positions) do
            if pos.x == target_led_x and pos.y == target_led_y then
                overlaps = true
                break
            end
        end
        if not overlaps then
            grid_device:led(target_led_x, target_led_y, 6) -- Dim target indicator
        end
    end
end

-- Update glide grid display
function Glide.update_glide_grid_display()
    -- Draw path points ONLY if path mode is enabled AND we're in matrix mode
    print(string.format("DEBUG GLIDE: grid_mode=%d, path_mode=%s, path_points=%d", grid_ui_state.grid_mode,
        path_state.mode, #path_state.points))
    if grid_ui_state.grid_mode == 4 and path_state.mode and #path_state.points > 0 then
        for i, point in ipairs(path_state.points) do
            local led_x = point.x + 1
            local led_y = point.y + 1
            local brightness = (i == path_state.current_point and path_state.playing) and 15 or 8
            grid_device:led(led_x, led_y, brightness)
        end
    end

    -- Force grid refresh to apply changes
    grid_device:refresh()
end

-- Getters
function Glide.get_glide_state()
    return glide_state
end

function Glide.is_gliding()
    return glide_state.is_gliding
end

-- Initialize dependencies
function Glide.init(deps)
    grid_ui_state = deps.grid_ui_state
    grid_device = deps.grid_device
    freqs = deps.freqs
    params = deps.params
    path_state = deps.path_state
    redraw_grid = deps.redraw_grid
    glide_state = deps.glide_state
end

return Glide
