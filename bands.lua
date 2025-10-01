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
local shift_held = false

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
-- Helper function to calculate level row from dB value
local function level_db_to_row(level_db)
    -- inverse of: level_db = 6 - ((y - 1) * 66 / 14)
    local level_y = util.round((6 - level_db) * 14 / 66 + 1)
    return util.clamp(level_y, 1, 15)
end

-- Helper function to calculate dB value from row
local function row_to_level_db(y)
    -- row 1 = +6dB, row 15 = -60dB
    return 6 - ((y - 1) * 66 / 14)
end

-- Helper function to calculate pan row from pan value
local function pan_to_row(pan)
    -- inverse of: pan = (y - 8) / 7
    local pan_y = util.round(pan * 7 + 8)
    return util.clamp(pan_y, 1, 15)
end

-- Helper function to calculate pan value from row
local function row_to_pan(y)
    -- row 1 = -1 (left), row 8 = 0 (center), row 15 = +1 (right)
    return (y - 8) / 7
end

-- Helper function to calculate threshold row from threshold value
local function threshold_to_row(thresh)
    -- inverse of: thresh = 1 - ((y - 1) / 14)
    local thresh_y = util.round((1 - thresh) * 14 + 1)
    return util.clamp(thresh_y, 1, 15)
end

-- Helper function to calculate threshold value from row
local function row_to_threshold(y)
    -- row 1 = 1.0, row 15 = 0.0
    return 1 - ((y - 1) / 14)
end

-- Helper function to set parameter for a single band or all bands
local function set_band_param(band_idx, param_type, value, shift_held, format_str)
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

-- Handle level mode
local function handle_level_mode(band_idx, y, shift_held)
    local level_db = row_to_level_db(y)
    set_band_param(band_idx, "level", level_db, shift_held, "%.1f dB")
end

-- Handle pan mode
local function handle_pan_mode(band_idx, y, shift_held)
    local pan = row_to_pan(y)
    set_band_param(band_idx, "pan", pan, shift_held, "%.2f")
end

-- Handle threshold mode
local function handle_threshold_mode(band_idx, y, shift_held)
    local thresh = row_to_threshold(y)
    set_band_param(band_idx, "thresh", thresh, shift_held, "%.2f")
end

-- Handle mode selector row
local function handle_mode_selector(x)
    if x >= 1 and x <= 3 then
        grid_mode = x
        print(string.format("mode: %s", mode_names[grid_mode]))
        redraw()
    end
end

-- Handle band control rows
local function handle_band_control(x, y, shift_held)
    local band_idx = x
    if band_idx <= #freqs then
        if grid_mode == 1 then
            handle_level_mode(band_idx, y, shift_held)
        elseif grid_mode == 2 then
            handle_pan_mode(band_idx, y, shift_held)
        elseif grid_mode == 3 then
            handle_threshold_mode(band_idx, y, shift_held)
        end
        grid_redraw()
    end
end

function grid.key(x, y, z)
    -- Handle shift key at position 16,16
    if y == 16 and x == 16 then
        shift_held = (z == 1)
        grid_redraw()
        return
    end

    -- Only process key press events
    if z == 1 then
        if y == 16 then
            -- Mode selector in row 16
            handle_mode_selector(x)
        elseif y >= 1 and y <= 15 then
            -- Band control in rows 1-15
            handle_band_control(x, y, shift_held)
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
    screen.text_center(mode_names[grid_mode])
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
            -- levels: show bar (row 1 = +6dB, row 15 = -60dB)
            local level_id = string.format("band_%02d_level", i)
            local level_db = params:get(level_id)
            -- inverse of: level_db = 6 - ((y - 1) * 66 / 14)
            local level_y = util.round((6 - level_db) * 14 / 66 + 1)
            level_y = util.clamp(level_y, 1, 15)
            -- draw bar from level_y down to row 15
            for y = level_y, 15 do
                grid_device:led(col, y, 1) -- dim bar
            end
        elseif grid_mode == 2 then
            -- pans: show single position
            local pan_id = string.format("band_%02d_pan", i)
            local pan = params:get(pan_id)
            -- inverse of: pan = (y - 8) / 7
            local pan_y = util.round(pan * 7 + 8)
            pan_y = util.clamp(pan_y, 1, 15)
            grid_device:led(col, pan_y, 4) -- highlight pan position
        elseif grid_mode == 3 then
            -- thresholds: show position (row 1 = 1.0, row 15 = 0.0)
            local thresh_id = string.format("band_%02d_thresh", i)
            local thresh = params:get(thresh_id)
            -- inverse of: thresh = 1 - ((y - 1) / 14)
            local thresh_y = util.round((1 - thresh) * 14 + 1)
            thresh_y = util.clamp(thresh_y, 1, 15)
            grid_device:led(col, thresh_y, 4) -- highlight threshold position
        end

        -- show meter on top (brighter) - only in level mode
        if grid_mode == 1 then
            local meter_h = math.floor(util.clamp(meter_v, 0, 1) * 15 + 0.5)
            if meter_h > 0 then
                local meter_y0 = 15 - meter_h + 1
                for y = meter_y0, 15 do
                    grid_device:led(col, y, (y == meter_y0) and 15 or 5) -- bright top, bright body
                end
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

    -- draw shift key at 16,16
    local shift_brightness = shift_held and 15 or 4
    grid_device:led(16, 16, shift_brightness)

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
