-- Helper functions for bands script
local util = require 'util'

local Helper = {}

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
        save_to_snapshot(current_snapshot)
    end
end

-- Mode-specific handlers
function Helper.handle_level_mode(band_idx, y, shift_held, freqs, save_to_snapshot, current_snapshot, set_selected_band)
    local level_db = Helper.row_to_level_db(y)
    Helper.set_band_param(band_idx, "level", level_db, shift_held, freqs, "%.1f dB", save_to_snapshot, current_snapshot)
    if set_selected_band then set_selected_band(band_idx) end
end

function Helper.handle_pan_mode(band_idx, y, shift_held, freqs, save_to_snapshot, current_snapshot)
    local pan = Helper.row_to_pan(y)
    Helper.set_band_param(band_idx, "pan", pan, shift_held, freqs, "%.2f", save_to_snapshot, current_snapshot)
end

function Helper.handle_threshold_mode(band_idx, y, shift_held, freqs, save_to_snapshot, current_snapshot)
    local thresh = Helper.row_to_threshold(y)
    Helper.set_band_param(band_idx, "thresh", thresh, shift_held, freqs, "%.2f", save_to_snapshot, current_snapshot)
end

function Helper.handle_decimate_mode(band_idx, y, shift_held, freqs, save_to_snapshot, current_snapshot)
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

return Helper
