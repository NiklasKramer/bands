-- Grid UI for bands script
local util = require 'util'

local GridUI = {}

-- Initialize grid UI
function GridUI.init(grid_device, freqs, mode_names)
    local state = {
        grid_device = grid_device,
        freqs = freqs,
        mode_names = mode_names,
        grid_mode = 1, -- 1=levels, 2=pans, 3=thresholds
        shift_held = false,
        band_meters = {},
        redraw_callback = nil
    }

    return state
end

-- Handle grid key presses
function GridUI.key(state, x, y, z, redraw_screen_callback)
    -- Handle shift key at position 16,16
    if y == 16 and x == 16 then
        state.shift_held = (z == 1)
        GridUI.redraw(state)
        return
    end

    -- Only process key press events
    if z == 1 then
        if y == 16 then
            -- Mode selector in row 16
            if x >= 1 and x <= 3 then
                state.grid_mode = x
                print(string.format("mode: %s", state.mode_names[state.grid_mode]))
                if redraw_screen_callback then redraw_screen_callback() end
            end
        elseif y >= 1 and y <= 15 then
            -- Band control in rows 1-15
            local band_idx = x
            if band_idx <= #state.freqs then
                local helper = require 'lib/helper'
                if state.grid_mode == 1 then
                    helper.handle_level_mode(band_idx, y, state.shift_held, state.freqs)
                elseif state.grid_mode == 2 then
                    helper.handle_pan_mode(band_idx, y, state.shift_held, state.freqs)
                elseif state.grid_mode == 3 then
                    helper.handle_threshold_mode(band_idx, y, state.shift_held, state.freqs)
                end
                GridUI.redraw(state)
            end
        end
    end
end

-- Redraw grid display
function GridUI.redraw(state)
    local g = state.grid_device
    g:all(0)
    local num = #state.freqs

    -- draw band controls (rows 1-15)
    for i = 1, math.min(16, num) do
        local meter_v = state.band_meters[i] or 0
        local col = i

        -- show current parameter value as background
        if state.grid_mode == 1 then
            -- levels: show bar (row 1 = +6dB, row 15 = -60dB)
            local level_id = string.format("band_%02d_level", i)
            local level_db = params:get(level_id)
            local level_y = util.round((6 - level_db) * 14 / 66 + 1)
            level_y = util.clamp(level_y, 1, 15)
            -- draw bar from level_y down to row 15
            for y = level_y, 15 do
                g:led(col, y, 1) -- dim bar
            end
        elseif state.grid_mode == 2 then
            -- pans: show single position
            local pan_id = string.format("band_%02d_pan", i)
            local pan = params:get(pan_id)
            local pan_y = util.round(pan * 7 + 8)
            pan_y = util.clamp(pan_y, 1, 15)
            g:led(col, pan_y, 4) -- highlight pan position
        elseif state.grid_mode == 3 then
            -- thresholds: show position (row 1 = 1.0, row 15 = 0.0)
            local thresh_id = string.format("band_%02d_thresh", i)
            local thresh = params:get(thresh_id)
            local thresh_y = util.round((1 - thresh) * 14 + 1)
            thresh_y = util.clamp(thresh_y, 1, 15)
            g:led(col, thresh_y, 4) -- highlight threshold position
        end

        -- show meter on top (brighter) - only in level mode
        if state.grid_mode == 1 then
            local meter_h = math.floor(util.clamp(meter_v, 0, 1) * 15 + 0.5)
            if meter_h > 0 then
                local meter_y0 = 15 - meter_h + 1
                for y = meter_y0, 15 do
                    g:led(col, y, (y == meter_y0) and 15 or 5) -- bright top, bright body
                end
            end
        end

        -- highlight center for pan mode
        if state.grid_mode == 2 then
            g:led(col, 8, 12) -- bright center line for pan
        end
    end

    -- draw mode selector in row 16
    for x = 1, 3 do
        local brightness = (x == state.grid_mode) and 15 or 4
        g:led(x, 16, brightness)
    end

    -- draw shift key at 16,16
    local shift_brightness = state.shift_held and 15 or 4
    g:led(16, 16, shift_brightness)

    g:refresh()
end

return GridUI
