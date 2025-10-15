-- Helper functions for bands script
local util = require 'util'

local Helper = {}

-- Conversion functions for input parameters
function Helper.x_to_audio_level(x)
    -- keys 1-16 map to 0.0-1.0
    return (x - 1) / 15
end

function Helper.x_to_osc_level(x)
    -- keys 1-16 map to 0.0-1.0
    return (x - 1) / 15
end

function Helper.x_to_osc_freq(x)
    -- keys 1-16 map to 0.1-2000 Hz exponential
    local normalized = (x - 1) / 15 -- 0 to 1
    return 0.1 * math.exp(normalized * math.log(2000 / 0.1))
end

function Helper.x_to_osc_timbre(x)
    -- keys 1-16 map to 0.0-1.0
    return (x - 1) / 15
end

function Helper.x_to_osc_warp(x)
    -- keys 1-16 map to 0.0-1.0
    return (x - 1) / 15
end

function Helper.x_to_osc_mod_rate(x)
    -- keys 1-16 map to 0.1-100 Hz exponential
    local normalized = (x - 1) / 15 -- 0 to 1
    return 0.1 * math.exp(normalized * math.log(100 / 0.1))
end

function Helper.x_to_noise_level(x)
    -- keys 1-16 map to 0.0-1.0
    return (x - 1) / 15
end

function Helper.x_to_noise_lfo_rate(x)
    -- keys 1-16 map to 0-20 Hz, key 1 = 0 (off)
    return (x - 1) * 20 / 15
end

function Helper.x_to_noise_lfo_depth(x)
    -- keys 1-16 map to 0.0-1.0
    return (x - 1) / 15
end

function Helper.x_to_dust_level(x)
    -- keys 1-16 map to 0.0-1.0
    return (x - 1) / 15
end

function Helper.x_to_dust_density(x)
    -- keys 1-16 map to 1-1000 Hz exponential
    local normalized = (x - 1) / 15 -- 0 to 1
    return math.floor(1 + (999 * (math.exp(normalized * 3) - 1) / (math.exp(3) - 1)))
end

function Helper.x_to_file_level(x)
    -- keys 1-16 map to 0.0-1.0
    return (x - 1) / 15
end

function Helper.x_to_file_speed(x)
    -- keys 1-16 map to -4.0 to 4.0 (center at key 8-9)
    return ((x - 1) / 15) * 8 - 4
end

-- Inverse conversion functions for display
function Helper.audio_level_to_x(level)
    return util.clamp(util.round(level * 15 + 1), 1, 16)
end

function Helper.noise_level_to_x(level)
    return util.clamp(util.round(level * 15 + 1), 1, 16)
end

function Helper.noise_lfo_rate_to_x(rate)
    return util.clamp(util.round(rate * 15 / 20 + 1), 1, 16)
end

function Helper.noise_lfo_depth_to_x(depth)
    return util.clamp(util.round(depth * 15 + 1), 1, 16)
end

function Helper.dust_level_to_x(level)
    return util.clamp(util.round(level * 15 + 1), 1, 16)
end

function Helper.dust_density_to_x(density)
    local normalized = math.log((density - 1) * (math.exp(3) - 1) / 999 + 1) / 3
    return util.clamp(util.round(normalized * 15 + 1), 1, 16)
end

function Helper.osc_level_to_x(level)
    return util.clamp(util.round(level * 15 + 1), 1, 16)
end

function Helper.osc_freq_to_x(freq)
    local normalized = math.log(freq / 0.1) / math.log(2000 / 0.1)
    return util.clamp(util.round(normalized * 15 + 1), 1, 16)
end

function Helper.osc_timbre_to_x(timbre)
    return util.clamp(util.round(timbre * 15 + 1), 1, 16)
end

function Helper.osc_warp_to_x(warp)
    return util.clamp(util.round(warp * 15 + 1), 1, 16)
end

function Helper.osc_mod_rate_to_x(rate)
    local normalized = math.log(rate / 0.1) / math.log(100 / 0.1)
    return util.clamp(util.round(normalized * 15 + 1), 1, 16)
end

-- Conversion functions: row to parameter value
function Helper.row_to_level_db(y)
    -- row 1 = +6dB, row 15 = -60dB
    return 6 - ((y - 1) * 66 / 14)
end

function Helper.row_to_pan(y)
    -- row 1 = -1 (left), row 8 = 0 (center), row 15 = +1 (right)
    return (y - 8) / 7
end

function Helper.row_to_threshold(y)
    -- row 1 = 0.0, row 15 = 0.2 (20% of original range)
    return ((y - 1) / 14) * 0.2
end

function Helper.row_to_decimate(y)
    -- row 1 = 48000 Hz (no decimation), row 15 = 100 Hz (max decimation)
    -- Use exponential scale for musical response
    local normalized = (y - 1) / 14                        -- 0 to 1
    return math.floor(48000 * math.exp(-normalized * 6.2)) -- Exponential decay
end

-- Conversion functions: parameter value to row
function Helper.level_db_to_row(level_db)
    -- inverse of: level_db = 6 - ((y - 1) * 66 / 14)
    local level_y = util.round((6 - level_db) * 14 / 66 + 1)
    return util.clamp(level_y, 1, 15)
end

function Helper.pan_to_row(pan)
    -- inverse of: pan = (y - 8) / 7
    local pan_y = util.round(pan * 7 + 8)
    return util.clamp(pan_y, 1, 15)
end

function Helper.threshold_to_row(thresh)
    -- inverse of: thresh = ((y - 1) / 14) * 0.2
    local thresh_y = util.round((thresh / 0.2) * 14 + 1)
    return util.clamp(thresh_y, 1, 15)
end

function Helper.decimate_to_row(rate)
    -- inverse of exponential decay
    local normalized = -math.log(rate / 48000) / 6.2
    local decimate_y = util.round(normalized * 14 + 1)
    return util.clamp(decimate_y, 1, 15)
end

function Helper.file_level_to_x(level)
    return util.clamp(util.round(level * 15 + 1), 1, 16)
end

function Helper.file_speed_to_x(speed)
    -- inverse of: speed = ((x - 1) / 15) * 8 - 4
    return util.clamp(util.round((speed + 4) / 8 * 15 + 1), 1, 16)
end

-- Set parameter for a single band or all bands
function Helper.set_band_param(band_idx, param_type, value, shift_held, freqs, format_str, save_to_snapshot,
                               current_snapshot)
    format_str = format_str or "%.2f"
    if shift_held then
        -- set all bands
        for i = 1, #freqs do
            -- Update params (this will update the engine automatically)
            if param_type == "level" then
                params:set(string.format("band_%02d_level", i), value)
            elseif param_type == "pan" then
                params:set(string.format("band_%02d_pan", i), value)
            elseif param_type == "thresh" then
                params:set(string.format("band_%02d_thresh", i), value)
            elseif param_type == "decimate" then
                params:set(string.format("band_%02d_decimate", i), value)
            end
        end
        print(string.format("all bands: set %s to " .. format_str, param_type, value))
    else
        -- set single band
        if param_type == "level" then
            params:set(string.format("band_%02d_level", band_idx), value)
        elseif param_type == "pan" then
            params:set(string.format("band_%02d_pan", band_idx), value)
        elseif param_type == "thresh" then
            params:set(string.format("band_%02d_thresh", band_idx), value)
        elseif param_type == "decimate" then
            params:set(string.format("band_%02d_decimate", band_idx), value)
        end
        print(string.format("band %d: set %s to " .. format_str, band_idx, param_type, value))
    end

    -- Auto-save to current snapshot if requested
    if save_to_snapshot and current_snapshot then
        save_to_snapshot(current_snapshot, "grid") -- Always from grid in helper
    end
end

-- Check if at snapshot corner
local function is_at_snapshot_corner(x, y)
    return (x == 1 and y == 1) or   -- A
           (x == 14 and y == 1) or  -- B
           (x == 1 and y == 14) or  -- C
           (x == 14 and y == 14)    -- D
end

-- Mode-specific handlers
function Helper.handle_level_mode(band_idx, y, shift_held, freqs, save_to_snapshot, current_snapshot, set_selected_band, ui_state, show_banner)
    -- Check if at corner before allowing edits
    if ui_state and not is_at_snapshot_corner(ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y) then
        if show_banner then
            show_banner("GRID: MOVE TO CORNER TO EDIT")
        end
        return
    end
    
    local level_db = Helper.row_to_level_db(y)
    Helper.set_band_param(band_idx, "level", level_db, shift_held, freqs, "%.1f dB", save_to_snapshot, current_snapshot)
    if set_selected_band then set_selected_band(band_idx) end
end

function Helper.handle_pan_mode(band_idx, y, shift_held, freqs, save_to_snapshot, current_snapshot, ui_state, show_banner)
    -- Check if at corner before allowing edits
    if ui_state and not is_at_snapshot_corner(ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y) then
        if show_banner then
            show_banner("GRID: MOVE TO CORNER TO EDIT")
        end
        return
    end
    
    local pan = Helper.row_to_pan(y)
    Helper.set_band_param(band_idx, "pan", pan, shift_held, freqs, "%.2f", save_to_snapshot, current_snapshot)
end

function Helper.handle_threshold_mode(band_idx, y, shift_held, freqs, save_to_snapshot, current_snapshot, ui_state, show_banner)
    -- Check if at corner before allowing edits
    if ui_state and not is_at_snapshot_corner(ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y) then
        if show_banner then
            show_banner("GRID: MOVE TO CORNER TO EDIT")
        end
        return
    end
    
    local thresh = Helper.row_to_threshold(y)
    Helper.set_band_param(band_idx, "thresh", thresh, shift_held, freqs, "%.2f", save_to_snapshot, current_snapshot)
end

function Helper.handle_decimate_mode(band_idx, y, shift_held, freqs, save_to_snapshot, current_snapshot, ui_state, show_banner)
    -- Check if at corner before allowing edits
    if ui_state and not is_at_snapshot_corner(ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y) then
        if show_banner then
            show_banner("GRID: MOVE TO CORNER TO EDIT")
        end
        return
    end
    
    local rate = Helper.row_to_decimate(y)
    Helper.set_band_param(band_idx, "decimate", rate, shift_held, freqs, "%.0f Hz", save_to_snapshot, current_snapshot)
end

-- UI handlers
function Helper.handle_mode_selector(x, mode_names, set_mode_callback)
    if x >= 1 and x <= 3 then
        set_mode_callback(x)
        print(string.format("mode: %s", mode_names[x]))
    end
end

function Helper.handle_band_control(x, y, shift_held, grid_mode, freqs, redraw_callback)
    local band_idx = x
    if band_idx <= #freqs then
        if grid_mode == 1 then
            Helper.handle_level_mode(band_idx, y, shift_held, freqs)
        elseif grid_mode == 2 then
            Helper.handle_pan_mode(band_idx, y, shift_held, freqs)
        elseif grid_mode == 3 then
            Helper.handle_threshold_mode(band_idx, y, shift_held, freqs)
        end
        redraw_callback()
    end
end

-- Handle input mode (mode 0) with selector
function Helper.handle_input_mode(x, y, shift_held, save_to_snapshot, current_snapshot, show_banner, input_mode_state)
    local param_id, value, display_text

    -- Row 1: Input selector (Input/Osc/Dust/Noise/File)
    if y == 1 then
        if x >= 1 and x <= 3 then
            input_mode_state.selected_input = 1 -- Input
            input_mode_state.selected_param = 1
            if show_banner then
                show_banner("input")
            end
        elseif x >= 4 and x <= 6 then
            input_mode_state.selected_input = 2 -- Osc
            input_mode_state.selected_param = 1
            if show_banner then
                show_banner("osc")
            end
        elseif x >= 7 and x <= 9 then
            input_mode_state.selected_input = 3 -- Dust
            input_mode_state.selected_param = 1
            if show_banner then
                show_banner("dust")
            end
        elseif x >= 10 and x <= 12 then
            input_mode_state.selected_input = 4 -- Noise
            input_mode_state.selected_param = 1
            if show_banner then
                show_banner("noise")
            end
        elseif x >= 13 and x <= 16 then
            input_mode_state.selected_input = 5 -- File
            input_mode_state.selected_param = 1
            if show_banner then
                show_banner("file")
            end
        end
        return
    end

    -- Rows 2+: Parameters based on selected input
    if input_mode_state.selected_input == 1 then
        -- Live audio input
        if y == 2 then
            value = Helper.x_to_audio_level(x)
            param_id = "audio_in_level"
            display_text = string.format("Audio In: %.2f", value)
        end
    elseif input_mode_state.selected_input == 2 then
        -- Oscillator
        if y == 2 then
            value = Helper.x_to_osc_level(x)
            param_id = "osc_level"
            display_text = string.format("Osc: %.2f", value)
        elseif y == 3 then
            value = Helper.x_to_osc_freq(x)
            param_id = "osc_freq"
            display_text = string.format("Freq: %.1fHz", value)
        elseif y == 4 then
            value = Helper.x_to_osc_timbre(x)
            param_id = "osc_timbre"
            display_text = string.format("Timbre: %.2f", value)
        elseif y == 5 then
            value = Helper.x_to_osc_warp(x)
            param_id = "osc_warp"
            display_text = string.format("Morph: %.2f", value)
        elseif y == 6 then
            value = Helper.x_to_osc_mod_rate(x)
            param_id = "osc_mod_rate"
            display_text = string.format("Mod Rate: %.1fHz", value)
        end
    elseif input_mode_state.selected_input == 3 then
        -- Dust
        if y == 2 then
            value = Helper.x_to_dust_level(x)
            param_id = "dust_level"
            display_text = string.format("Dust: %.2f", value)
        elseif y == 3 then
            value = Helper.x_to_dust_density(x)
            param_id = "dust_density"
            display_text = string.format("Dust Dens: %dHz", value)
        end
    elseif input_mode_state.selected_input == 4 then
        -- Noise
        if y == 2 then
            value = Helper.x_to_noise_level(x)
            param_id = "noise_level"
            display_text = string.format("NOISE: %.2f", value)
        elseif y == 3 then
            value = Helper.x_to_noise_lfo_rate(x)
            param_id = "noise_lfo_rate"
            if value == 0 then
                display_text = "LFO RATE: OFF"
            else
                display_text = string.format("LFO RATE: %.1fHz", value)
            end
        elseif y == 4 then
            value = Helper.x_to_noise_lfo_depth(x)
            param_id = "noise_lfo_depth"
            display_text = string.format("LFO DEPTH: %.0f%%", value * 100)
        end
    elseif input_mode_state.selected_input == 5 then
        -- File playback
        if y == 2 then
            value = Helper.x_to_file_level(x)
            param_id = "file_level"
            display_text = string.format("FILE LEVEL: %.2f", value)
        elseif y == 3 then
            value = Helper.x_to_file_speed(x)
            param_id = "file_speed"
            display_text = string.format("FILE SPEED: %.2f", value)
        end
    end

    -- Apply the parameter change if we got a valid one
    if param_id and value then
        params:set(param_id, value)

        -- Also update the corresponding snapshot parameter
        local snapshot_param = string.format("snapshot_%s_%s", string.lower(current_snapshot), param_id)
        params:set(snapshot_param, value)

        -- Show info banner with the change
        if show_banner and display_text then
            show_banner(display_text)
        end
    end
end

return Helper
