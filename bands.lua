-- luacheck: globals screen
-- norns script skeleton
-- clear starting point for building a script
-- load Engine Bands
engine.name = "Bands"
local grid_device = grid.connect()
-- params -------------------------------------------------------
local controlspec = require 'controlspec'
local util = require 'util'

-- forward declarations for local functions used by init/cleanup
local start_meter_polls
local stop_meter_polls
local metro_grid_refresh

local freqs = {
    80, 150, 250, 350, 500, 630, 800, 1000,
    1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
}

-- meters ------------------------------------------------------
local band_meters = {}
local band_meter_polls = {}

-- mode selector (row 16)
local grid_mode = 1 -- 1=levels, 2=pans, 3=thresholds
local mode_names = { "levels", "pans", "thresholds" }

-- init is called when the script loads
function init()
    screen.aa(0)
    screen.line_width(1)
    add_params()
    params:bang()
    start_meter_polls()
    -- start periodic grid refresh (~40 Hz)
    metro_grid_refresh = metro.init(function(stage)
        grid_redraw()
    end, 1 / 60)
    metro_grid_refresh:start()
    redraw()
end

-- key is called when a key is pressed or released
-- n: key number (1..3), z: 1 = press, 0 = release
function key(n, z)
    -- add key handling here
end

-- grid key handling for band control
function grid.key(x, y, z)
    if z == 1 then
        if y == 16 then
            -- mode selector in row 16
            if x >= 1 and x <= 3 then
                grid_mode = x
                print(string.format("mode: %s", mode_names[grid_mode]))
            end
        elseif y >= 1 and y <= 15 then
            -- band control in rows 1-15
            local band_idx = x
            if band_idx <= #freqs then
                if grid_mode == 1 then
                    -- set levels: row 1 = +6dB, row 15 = -60dB
                    local level_db = 6 - ((y - 1) * 66 / 14)
                    local level_id = string.format("band_%02d_level", band_idx)
                    params:set(level_id, level_db)
                    print(string.format("band %d: set level to %.1f dB", band_idx, level_db))
                elseif grid_mode == 2 then
                    -- set pans: row 1 = -1 (left), row 8 = 0 (center), row 15 = +1 (right)
                    local pan = (y - 8) / 7 -- map y 1-15 to pan -1 to +1, with 8 = 0
                    local pan_id = string.format("band_%02d_pan", band_idx)
                    params:set(pan_id, pan)
                    print(string.format("band %d: set pan to %.2f", band_idx, pan))
                elseif grid_mode == 3 then
                    -- set thresholds: row 1 = 1.0, row 15 = 0.0
                    local thresh = 1 - ((y - 1) / 14) -- map y 1-15 to thresh 1 to 0
                    local thresh_id = string.format("band_%02d_thresh", band_idx)
                    params:set(thresh_id, thresh)
                    print(string.format("band %d: set threshold to %.2f", band_idx, thresh))
                end

                -- immediately update grid to reflect the change
                grid_redraw()
            end
        end
    end
end

-- enc is called when an encoder is turned
-- n: encoder number (1..3), d: delta steps
function enc(n, d)
    -- add encoder handling here
end

-- redraw updates the screen
function redraw()
    screen.clear()
    screen.level(15)
    screen.move(64, 32)
    screen.text_center("script skeleton")
    screen.update()
end

-- cleanup is called on script exit
function cleanup()
    stop_meter_polls()
    if metro_grid_refresh then
        metro_grid_refresh:stop()
        metro_grid_refresh = nil
    end
end

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

function grid_redraw()
    grid_device:all(0)
    local num = #freqs

    -- draw band controls (rows 1-15)
    for i = 1, math.min(16, num) do
        local meter_v = band_meters[i] or 0
        local col = i

        -- show current parameter value as background
        if grid_mode == 1 then
            -- levels: show bar
            local level_id = string.format("band_%02d_level", i)
            local level_db = params:get(level_id)
            local param_v = (level_db + 60) / 66 -- convert -60dB to +6dB range to 0-1
            local param_h = math.floor(util.clamp(param_v, 0, 1) * 15 + 0.5)
            if param_h > 0 then
                local param_y0 = 15 - param_h + 1
                for y = param_y0, 15 do
                    grid_device:led(col, y, 2) -- dim background
                end
            end
        elseif grid_mode == 2 then
            -- pans: show single position
            local pan_id = string.format("band_%02d_pan", i)
            local pan = params:get(pan_id)
            local pan_y = math.floor(pan * 7 + 8) -- convert -1 to +1 to y 1-15, with 0→8
            pan_y = util.clamp(pan_y, 1, 15)
            grid_device:led(col, pan_y, 4)        -- highlight pan position
        elseif grid_mode == 3 then
            -- thresholds: show bar
            local thresh_id = string.format("band_%02d_thresh", i)
            local param_v = params:get(thresh_id) -- already 0-1
            local param_h = math.floor(util.clamp(param_v, 0, 1) * 15 + 0.5)
            if param_h > 0 then
                local param_y0 = 15 - param_h + 1
                for y = param_y0, 15 do
                    grid_device:led(col, y, 2) -- dim background
                end
            end
        end

        -- show meter on top (brighter)
        local meter_h = math.floor(util.clamp(meter_v, 0, 1) * 15 + 0.5)
        if meter_h > 0 then
            local meter_y0 = 15 - meter_h + 1
            for y = meter_y0, 15 do
                grid_device:led(col, y, (y == meter_y0) and 12 or 4) -- bright top, medium body
            end
        end

        -- highlight center for pan mode
        if grid_mode == 2 then
            grid_device:led(col, 8, 12) -- bright center line for pan
        end
    end

    -- draw mode selector in row 16
    for x = 1, 3 do
        local brightness = (x == grid_mode) and 15 or 4 -- bright for selected, dim for others
        grid_device:led(x, 16, brightness)
    end

    grid_device:refresh()
end

start_meter_polls = function()
    for i = 1, #freqs do
        do
            local poll_name = "meter_" .. (i - 1)
            local p = poll.set(poll_name, function(v)
                v = v or 0
                band_meters[i] = v
                -- print(string.format("meter[%02d]=%.4f", i, v))
            end)
            p.time = 1 / 60
            p:start()
            band_meter_polls[#band_meter_polls + 1] = p
        end
    end
end

stop_meter_polls = function()
    for i = 1, #band_meter_polls do
        local p = band_meter_polls[i]
        if p then p:stop() end
        band_meter_polls[i] = nil
    end
end
