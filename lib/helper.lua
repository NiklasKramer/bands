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
    -- row 1 = 1.0, row 15 = 0.0
    return 1 - ((y - 1) / 14)
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
    -- inverse of: thresh = 1 - ((y - 1) / 14)
    local thresh_y = util.round((1 - thresh) * 14 + 1)
    return util.clamp(thresh_y, 1, 15)
end

-- Set parameter for a single band or all bands
function Helper.set_band_param(band_idx, param_type, value, shift_held, freqs, format_str)
    format_str = format_str or "%.2f"
    if shift_held then
        -- set all bands
        for i = 1, #freqs do
            local param_id = string.format("band_%02d_%s", i, param_type)
            params:set(param_id, value)
        end
        print(string.format("all bands: set %s to " .. format_str, param_type, value))
    else
        -- set single band
        local param_id = string.format("band_%02d_%s", band_idx, param_type)
        params:set(param_id, value)
        print(string.format("band %d: set %s to " .. format_str, band_idx, param_type, value))
    end
end

-- Mode-specific handlers
function Helper.handle_level_mode(band_idx, y, shift_held, freqs)
    local level_db = Helper.row_to_level_db(y)
    Helper.set_band_param(band_idx, "level", level_db, shift_held, freqs, "%.1f dB")
end

function Helper.handle_pan_mode(band_idx, y, shift_held, freqs)
    local pan = Helper.row_to_pan(y)
    Helper.set_band_param(band_idx, "pan", pan, shift_held, freqs, "%.2f")
end

function Helper.handle_threshold_mode(band_idx, y, shift_held, freqs)
    local thresh = Helper.row_to_threshold(y)
    Helper.set_band_param(band_idx, "thresh", thresh, shift_held, freqs, "%.2f")
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
