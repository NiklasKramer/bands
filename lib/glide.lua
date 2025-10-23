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
    if not glide_state.is_gliding then
        return
    end

    if not glide_state.target_values.q then
        glide_state.is_gliding = false
        return
    end

    -- Set final parameter values directly to engine
    if engine and engine.q then
        engine.q(glide_state.target_values.q)
    end

    -- Set final input settings
    if glide_state.target_values.audio_in_level and engine and engine.audio_in_level then
        engine.audio_in_level(glide_state.target_values.audio_in_level)
    end
    if glide_state.target_values.noise_level and engine and engine.noise_level then
        engine.noise_level(glide_state.target_values.noise_level)
    end
    if glide_state.target_values.dust_level and engine and engine.dust_level then
        engine.dust_level(glide_state.target_values.dust_level)
    end
    if glide_state.target_values.noise_lfo_rate and engine and engine.noise_lfo_rate then
        engine.noise_lfo_rate(glide_state.target_values.noise_lfo_rate)
    end
    if glide_state.target_values.noise_lfo_depth and engine and engine.noise_lfo_depth then
        engine.noise_lfo_depth(glide_state.target_values.noise_lfo_depth)
    end
    if glide_state.target_values.dust_density and engine and engine.dust_density then
        engine.dust_density(glide_state.target_values.dust_density)
    end
    if glide_state.target_values.osc_level and engine and engine.osc_level then
        engine.osc_level(glide_state.target_values.osc_level)
    end
    if glide_state.target_values.osc_freq and engine and engine.osc_freq then
        engine.osc_freq(glide_state.target_values.osc_freq)
    end
    if glide_state.target_values.osc_timbre and engine and engine.osc_timbre then
        engine.osc_timbre(glide_state.target_values.osc_timbre)
    end
    if glide_state.target_values.osc_warp and engine and engine.osc_warp then
        engine.osc_warp(glide_state.target_values.osc_warp)
    end
    if glide_state.target_values.osc_mod_rate and engine and engine.osc_mod_rate then
        engine.osc_mod_rate(glide_state.target_values.osc_mod_rate)
    end
    if glide_state.target_values.osc_mod_depth and engine and engine.osc_mod_depth then
        engine.osc_mod_depth(glide_state.target_values.osc_mod_depth)
    end
    if glide_state.target_values.file_level and engine and engine.file_level then
        engine.file_level(glide_state.target_values.file_level)
    end
    if glide_state.target_values.file_speed and engine and engine.file_speed then
        engine.file_speed(glide_state.target_values.file_speed)
    end
    if glide_state.target_values.file_gate and engine and engine.file_gate then
        engine.file_gate(glide_state.target_values.file_gate)
    end

    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)
        local decimate_id = string.format("band_%02d_decimate", i)

        -- Set engine parameters directly
        if glide_state.target_values[level_id] and engine and engine.level then
            engine.level(i, glide_state.target_values[level_id])
        end
        if glide_state.target_values[pan_id] and engine and engine.pan then
            engine.pan(i, glide_state.target_values[pan_id])
        end
        if glide_state.target_values[thresh_id] and engine and engine.thresh_band then
            engine.thresh_band(i, glide_state.target_values[thresh_id])
        end
        if glide_state.target_values[decimate_id] and engine and engine.decimate_band then
            engine.decimate_band(i, glide_state.target_values[decimate_id])
        end
    end

    glide_state.is_gliding = false

    -- Update matrix position to final target position
    grid_ui_state.current_matrix_pos.x = glide_state.target_pos.x
    grid_ui_state.current_matrix_pos.y = glide_state.target_pos.y

    -- Restart path playback metro if path is playing
    if path_state.playing and path_state.playback_metro then
        path_state.playback_metro:start(0.1)
    end


    -- Redraw grid to show final position
    redraw_grid()
end

-- Update glide progress
function Glide.update_glide_progress(elapsed, glide_time)
    local progress = elapsed / glide_time

    -- Validate start_pos before calculation
    if not glide_state.start_pos.x or glide_state.start_pos.x ~= glide_state.start_pos.x then
        glide_state.is_gliding = false
        return
    end
    if not glide_state.start_pos.y or glide_state.start_pos.y ~= glide_state.start_pos.y then
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

    -- Update params (this will update the engine automatically)
    params:set("q", current_q)

    -- Update input settings
    local current_audio_in_level = glide_state.current_values.audio_in_level +
        (glide_state.target_values.audio_in_level - glide_state.current_values.audio_in_level) * progress
    params:set("audio_in_level", current_audio_in_level)

    local current_noise_level = glide_state.current_values.noise_level +
        (glide_state.target_values.noise_level - glide_state.current_values.noise_level) * progress
    params:set("noise_level", current_noise_level)

    local current_dust_level = glide_state.current_values.dust_level +
        (glide_state.target_values.dust_level - glide_state.current_values.dust_level) * progress
    params:set("dust_level", current_dust_level)

    local current_noise_lfo_rate = glide_state.current_values.noise_lfo_rate +
        (glide_state.target_values.noise_lfo_rate - glide_state.current_values.noise_lfo_rate) * progress
    params:set("noise_lfo_rate", current_noise_lfo_rate)

    local current_noise_lfo_depth = glide_state.current_values.noise_lfo_depth +
        (glide_state.target_values.noise_lfo_depth - glide_state.current_values.noise_lfo_depth) * progress
    params:set("noise_lfo_depth", current_noise_lfo_depth)

    local current_dust_density = glide_state.current_values.dust_density +
        (glide_state.target_values.dust_density - glide_state.current_values.dust_density) * progress
    params:set("dust_density", current_dust_density)

    local current_osc_level = glide_state.current_values.osc_level +
        (glide_state.target_values.osc_level - glide_state.current_values.osc_level) * progress
    params:set("osc_level", current_osc_level)

    local current_osc_freq = glide_state.current_values.osc_freq +
        (glide_state.target_values.osc_freq - glide_state.current_values.osc_freq) * progress
    params:set("osc_freq", current_osc_freq)

    local current_osc_timbre = glide_state.current_values.osc_timbre +
        (glide_state.target_values.osc_timbre - glide_state.current_values.osc_timbre) * progress
    params:set("osc_timbre", current_osc_timbre)

    local current_osc_warp = glide_state.current_values.osc_warp +
        (glide_state.target_values.osc_warp - glide_state.current_values.osc_warp) * progress
    params:set("osc_warp", current_osc_warp)

    local current_osc_mod_rate = glide_state.current_values.osc_mod_rate +
        (glide_state.target_values.osc_mod_rate - glide_state.current_values.osc_mod_rate) * progress
    params:set("osc_mod_rate", current_osc_mod_rate)

    local current_osc_mod_depth = glide_state.current_values.osc_mod_depth +
        (glide_state.target_values.osc_mod_depth - glide_state.current_values.osc_mod_depth) * progress
    params:set("osc_mod_depth", current_osc_mod_depth)

    -- Update file parameters
    local current_file_level = glide_state.current_values.file_level +
        (glide_state.target_values.file_level - glide_state.current_values.file_level) * progress
    params:set("file_level", current_file_level)

    local current_file_speed = glide_state.current_values.file_speed +
        (glide_state.target_values.file_speed - glide_state.current_values.file_speed) * progress
    params:set("file_speed", current_file_speed)

    local current_file_gate = glide_state.current_values.file_gate +
        (glide_state.target_values.file_gate - glide_state.current_values.file_gate) * progress
    params:set("file_gate", current_file_gate)

    -- Update matrix position during glide
    grid_ui_state.current_matrix_pos.x = glide_state.start_pos.x +
        (glide_state.target_pos.x - glide_state.start_pos.x) * progress
    grid_ui_state.current_matrix_pos.y = glide_state.start_pos.y +
        (glide_state.target_pos.y - glide_state.start_pos.y) * progress

    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)
        local decimate_id = string.format("band_%02d_decimate", i)

        local current_level = glide_state.current_values[level_id] +
            (glide_state.target_values[level_id] - glide_state.current_values[level_id]) * progress
        local current_pan = glide_state.current_values[pan_id] +
            (glide_state.target_values[pan_id] - glide_state.current_values[pan_id]) * progress
        local current_thresh = glide_state.current_values[thresh_id] +
            (glide_state.target_values[thresh_id] - glide_state.current_values[thresh_id]) * progress
        local current_decimate = glide_state.current_values[decimate_id] +
            (glide_state.target_values[decimate_id] - glide_state.current_values[decimate_id]) * progress

        -- Update params (this will update the engine automatically)
        params:set(string.format("band_%02d_level", i), current_level)
        params:set(string.format("band_%02d_pan", i), current_pan)
        params:set(string.format("band_%02d_thresh", i), current_thresh)
        params:set(string.format("band_%02d_decimate", i), current_decimate)
    end
end

-- Update glide visuals
function Glide.update_glide_visuals(progress)
    -- Only draw glide animation on matrix screen
    if grid_ui_state.grid_mode ~= 4 then
        return
    end

    -- Draw the current glide position directly on the grid
    local current_x = glide_state.start_pos.x +
        (glide_state.target_pos.x - glide_state.start_pos.x) * progress
    local current_y = glide_state.start_pos.y +
        (glide_state.target_pos.y - glide_state.start_pos.y) * progress


    -- Clear previous sub-pixel LEDs
    Glide.clear_previous_glide_leds()

    -- Draw sub-pixel interpolation
    Glide.draw_sub_pixel_interpolation(current_x, current_y)

    -- Draw target indicator
    Glide.draw_target_indicator()
end

-- Clear previous glide LEDs
function Glide.clear_previous_glide_leds()
    -- Only clear LEDs if we're in matrix mode
    if grid_ui_state.grid_mode ~= 4 then
        return
    end

    -- Note: Grid clearing is now handled by the normal grid refresh metro
    -- This function is kept for compatibility but doesn't directly write to grid
end

-- Draw sub-pixel interpolation
function Glide.draw_sub_pixel_interpolation(current_x, current_y)
    -- Only draw if we're in matrix mode
    if grid_ui_state.grid_mode ~= 4 then
        return
    end

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

            -- Note: Grid drawing is now handled by the normal grid refresh metro
            -- grid_device:led(grid_x, grid_y, brightness)

            -- Store for clearing next time
            table.insert(glide_state.last_led_positions, { x = grid_x, y = grid_y })
        end
    end
end

-- Draw target indicator
function Glide.draw_target_indicator()
    -- Only draw if we're in matrix mode
    if grid_ui_state.grid_mode ~= 4 then
        return
    end

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
            -- Note: Grid drawing is now handled by the normal grid refresh metro
            -- grid_device:led(target_led_x, target_led_y, 6) -- Dim target indicator
        end
    end
end

-- Update glide grid display
function Glide.update_glide_grid_display()
    -- Only update if we're in matrix mode
    if grid_ui_state.grid_mode ~= 4 then
        return
    end

    -- Note: Grid drawing is now handled by the normal grid refresh metro
    -- This function is kept for compatibility but doesn't directly write to grid
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
