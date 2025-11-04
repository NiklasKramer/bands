-- bands

engine.name = "Bands"
local grid_device = grid.connect()

-- modules
local grid_ui = include 'lib/grid_ui'
local meters_mod = include 'lib/meters'
local path_mod = include 'lib/path'
local glide_mod = include 'lib/glide'
local grid_draw_mod = include 'lib/grid_draw'
local info_banner_mod = include 'lib/info_banner'
local screen_indicators = include 'lib/screen_indicators'
local snapshot_mod = include 'lib/snapshot'
local Blend = include 'lib/blend'
local ScreenDraw = include 'lib/screen_draw'

-- params
local controlspec = require 'controlspec'
local util = require 'util'
local fileselect = require 'lib/fileselect'

-- forward declarations
local metro_grid_refresh
local metro_glide
local metro_screen_refresh

-- state
local freqs = {
    80, 150, 250, 350, 500, 630, 800, 1000,
    1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
}

local mode_names = { "INPUTS", "LEVELS", "PANS", "THRESHOLDS", "DECIMATE", "EFFECTS", "MATRIX" }
local band_meters = {}
local band_meter_polls
local grid_ui_state
local selected_band = 1                      -- Currently selected band (1-16)
local selected_matrix_pos = { x = 1, y = 1 } -- Selected position for matrix navigation

-- Input mode state
local input_mode_state = {
    selected_input = 1, -- 1=live, 2=osc, 3=dust, 4=noise, 5=file
    selected_param = 1  -- Selected parameter within the input type
}

-- Effects mode state
local effects_mode_state = {
    selected_effect = 1, -- 1=delay, 2=eq
    selected_param = 1   -- Selected parameter within the effect type
}

-- Norns screen mode (independent from grid mode)
local norns_mode = 0 -- 0=inputs, 1=levels, 2=pans, 3=thresholds, 4=decimate, 5=effects, 6=matrix

-- Current state is now managed by the params system

-- Update selected band
local function set_selected_band(band)
    if band >= 1 and band <= #freqs then
        selected_band = band
    end
end

-- Glide state
local glide_state = {
    current_values = {},             -- Current parameter values during glide
    target_values = { q = 1.0 },     -- Target parameter values to glide to (initialize with default)
    glide_time = 0,                  -- Time when glide started
    is_gliding = false,              -- Whether we're currently gliding
    start_pos = { x = 0, y = 0 },    -- Starting matrix position
    target_pos = { x = 0, y = 0 },   -- Target matrix position
    last_led_pos = { x = 0, y = 0 }, -- Last LED position to clear (legacy)
    last_led_positions = {}          -- Array of LED positions for sub-pixel clearing
}

-- Path mode state
local path_state = {
    mode = false,        -- Whether path mode is enabled on matrix
    recording = false,   -- Whether currently recording a path
    points = {},         -- Array of recorded path points
    playing = false,     -- Whether currently playing the path
    current_point = 1,   -- Current point index in playback
    playback_metro = nil -- Metro for path playback timing
}


-- Snapshot system
local snapshots = {
    A = { name = "Snapshot A", params = {} },
    B = { name = "Snapshot B", params = {} },
    C = { name = "Snapshot C", params = {} },
    D = { name = "Snapshot D", params = {} }
}

-- Selected snapshot (independent of matrix position when current_state_mode is OFF)
local selected_snapshot = "A"

-- Module instances (initialized in init())
local blend_mod
local screen_draw_mod

-- Get snapshot based on mode:
-- When current_state_mode is OFF: return selected_snapshot (decoupled)
-- When current_state_mode is ON: derive from matrix position
local function get_current_snapshot_from_position()
    if not grid_ui_state.current_state_mode then
        return selected_snapshot
    end

    -- In current state mode, derive from position
    local x = grid_ui_state.current_matrix_pos.x
    local y = grid_ui_state.current_matrix_pos.y

    if x == 1 and y == 1 then
        return "A"
    elseif x == 14 and y == 1 then
        return "B"
    elseif x == 1 and y == 14 then
        return "C"
    elseif x == 14 and y == 14 then
        return "D"
    else
        -- When not at a corner, return the closest corner
        -- This determines which snapshot letter to show in snapshot display
        local dist_a = math.abs(x - 1) + math.abs(y - 1)
        local dist_b = math.abs(x - 14) + math.abs(y - 1)
        local dist_c = math.abs(x - 1) + math.abs(y - 14)
        local dist_d = math.abs(x - 14) + math.abs(y - 14)
        local min_dist = math.min(dist_a, dist_b, dist_c, dist_d)

        if min_dist == dist_a then
            return "A"
        elseif min_dist == dist_b then
            return "B"
        elseif min_dist == dist_c then
            return "C"
        else
            return "D"
        end
    end
end

-- Clipboard for copy/paste
local clipboard = nil

-- File selection state
local fileselect_active = false

-- File selection callback
local function file_select_callback(file)
    fileselect_active = false -- Reset the flag
    if file ~= "cancel" and file ~= "" then
        params:set("file_path", file)
    end
end

-- Initialize current state from the current snapshot
-- Wrapper functions for snapshot module
local function init_current_state()
    snapshot_mod.init_current_state(params, freqs)
end

local function init_snapshots()
    snapshot_mod.init_snapshots()
end

local function store_snapshot(snapshot_name)
    snapshot_mod.store_snapshot(snapshot_name, params, freqs)
end

local function save_snapshot(snapshot_name, source)
    store_snapshot(snapshot_name)
    -- Show banner only when explicitly saving (not auto-save)
    if source and params:get("info_banner") == 2 then
        local prefix = (source == "grid") and "GRID: " or ""
        info_banner_mod.show(prefix .. "SAVED " .. snapshot_name)
    end
end

local function recall_snapshot(snapshot_name)
    snapshot_mod.recall_snapshot(snapshot_name, params, freqs)
end

-- Copy current state to clipboard
local function copy_snapshot()
    clipboard = {}

    -- Copy global parameters
    clipboard.q = params:get("q")

    -- Copy input settings
    clipboard.audio_in_level = params:get("audio_in_level")
    clipboard.noise_level = params:get("noise_level")
    clipboard.dust_level = params:get("dust_level")
    clipboard.noise_lfo_rate = params:get("noise_lfo_rate")
    clipboard.noise_lfo_depth = params:get("noise_lfo_depth")
    clipboard.noise_lfo_rate_jitter_rate = params:get("noise_lfo_rate_jitter_rate")
    clipboard.noise_lfo_rate_jitter_depth = params:get("noise_lfo_rate_jitter_depth")
    clipboard.dust_density = params:get("dust_density")
    clipboard.osc_level = params:get("osc_level")
    clipboard.osc_freq = params:get("osc_freq")
    clipboard.osc_timbre = params:get("osc_timbre")
    clipboard.osc_warp = params:get("osc_warp")
    clipboard.osc_mod_rate = params:get("osc_mod_rate")
    clipboard.osc_mod_depth = params:get("osc_mod_depth")
    clipboard.file_level = params:get("file_level")
    clipboard.file_speed = params:get("file_speed")
    clipboard.file_gate = params:get("file_gate")

    -- Copy effect settings
    clipboard.delay_time = params:get("delay_time")
    clipboard.delay_feedback = params:get("delay_feedback")
    clipboard.delay_mix = params:get("delay_mix")
    clipboard.delay_width = params:get("delay_width")
    clipboard.eq_low_cut = params:get("eq_low_cut")
    clipboard.eq_high_cut = params:get("eq_high_cut")
    clipboard.eq_low_gain = params:get("eq_low_gain")
    clipboard.eq_mid_gain = params:get("eq_mid_gain")
    clipboard.eq_high_gain = params:get("eq_high_gain")

    -- Copy band settings
    for i = 1, #freqs do
        clipboard["band_" .. i .. "_level"] = params:get(string.format("band_%02d_level", i))
        clipboard["band_" .. i .. "_pan"] = params:get(string.format("band_%02d_pan", i))
        clipboard["band_" .. i .. "_thresh"] = params:get(string.format("band_%02d_thresh", i))
        clipboard["band_" .. i .. "_decimate"] = params:get(string.format("band_%02d_decimate", i))
    end

    -- Show banner
    if params:get("info_banner") == 2 then
        info_banner_mod.show("COPIED")
    end
end

-- Paste clipboard to current state
local function paste_snapshot()
    if clipboard == nil then
        if params:get("info_banner") == 2 then
            info_banner_mod.show("NOTHING TO PASTE")
        end
        return
    end

    -- Paste global parameters
    params:set("q", clipboard.q)

    -- Paste input settings
    params:set("audio_in_level", clipboard.audio_in_level)
    params:set("noise_level", clipboard.noise_level)
    params:set("dust_level", clipboard.dust_level)
    params:set("noise_lfo_rate", clipboard.noise_lfo_rate)
    params:set("noise_lfo_depth", clipboard.noise_lfo_depth)
    params:set("noise_lfo_rate_jitter_rate", clipboard.noise_lfo_rate_jitter_rate)
    params:set("noise_lfo_rate_jitter_depth", clipboard.noise_lfo_rate_jitter_depth)
    params:set("dust_density", clipboard.dust_density)
    params:set("osc_level", clipboard.osc_level)
    params:set("osc_freq", clipboard.osc_freq)
    params:set("osc_timbre", clipboard.osc_timbre)
    params:set("osc_warp", clipboard.osc_warp)
    params:set("osc_mod_rate", clipboard.osc_mod_rate)
    params:set("osc_mod_depth", clipboard.osc_mod_depth)
    params:set("file_level", clipboard.file_level)
    params:set("file_speed", clipboard.file_speed)
    params:set("file_gate", clipboard.file_gate)

    -- Paste effect settings
    params:set("delay_time", clipboard.delay_time)
    params:set("delay_feedback", clipboard.delay_feedback)
    params:set("delay_mix", clipboard.delay_mix)
    params:set("delay_width", clipboard.delay_width)
    params:set("eq_low_cut", clipboard.eq_low_cut)
    params:set("eq_high_cut", clipboard.eq_high_cut)
    params:set("eq_low_gain", clipboard.eq_low_gain)
    params:set("eq_mid_gain", clipboard.eq_mid_gain)
    params:set("eq_high_gain", clipboard.eq_high_gain)

    -- Paste band settings
    for i = 1, #freqs do
        params:set(string.format("band_%02d_level", i), clipboard["band_" .. i .. "_level"])
        params:set(string.format("band_%02d_pan", i), clipboard["band_" .. i .. "_pan"])
        params:set(string.format("band_%02d_thresh", i), clipboard["band_" .. i .. "_thresh"])
        params:set(string.format("band_%02d_decimate", i), clipboard["band_" .. i .. "_decimate"])
    end

    -- Save to current snapshot
    store_snapshot(get_current_snapshot_from_position())

    -- Show banner
    if params:get("info_banner") == 2 then
        info_banner_mod.show("PASTED")
    end
end

-- Calculate blend weights for matrix position
local function calculate_blend_weights(x, y)
    -- Clamp coordinates to valid range
    x = util.clamp(x, 1, 14)
    y = util.clamp(y, 1, 14)

    local norm_x = (x - 1) / 13
    local norm_y = (y - 1) / 13

    local a_weight = (1 - norm_x) * (1 - norm_y)
    local b_weight = norm_x * (1 - norm_y)
    local c_weight = (1 - norm_x) * norm_y
    local d_weight = norm_x * norm_y

    return a_weight, b_weight, c_weight, d_weight
end

-- Check if we're at a snapshot corner (100% on one snapshot)
local function is_at_snapshot_corner(x, y)
    return (x == 1 and y == 1) or -- A
        (x == 14 and y == 1) or   -- B
        (x == 1 and y == 14) or   -- C
        (x == 14 and y == 14)     -- D
end


-- Apply blended parameters to engine
function apply_blend(x, y, old_x, old_y)
    local a_w, b_w, c_w, d_w = calculate_blend_weights(x, y)

    -- Calculate target values using blend module
    local target_values = blend_mod:calculate_target_values(a_w, b_w, c_w, d_w)

    -- Check if glide is enabled
    local glide_time_param = params:get("glide")
    if glide_time_param > 0 then
        if glide_state.is_gliding then
            -- Handle glide interruption
            blend_mod:handle_glide_interruption(glide_time_param)
        else
            -- Initialize new glide state
            blend_mod:initialize_glide_state(old_x, old_y)
        end

        -- Set new target (common for both cases)
        glide_state.target_pos.x = x
        glide_state.target_pos.y = y
        glide_state.target_values = target_values
        glide_state.glide_time = util.time()
        glide_state.is_gliding = true
    else
        -- Apply immediately without glide
        blend_mod:apply_values_immediately(target_values, x, y, old_x, old_y)
    end
end

-- Select a snapshot (without moving matrix - for when current_state_mode is OFF)
local function select_snapshot(snapshot_name)
    selected_snapshot = snapshot_name
    -- Recall the snapshot to load its values into live parameters
    recall_snapshot(snapshot_name)
    redraw()
    redraw_grid()
    if params:get("info_banner") == 2 then
        info_banner_mod.show("SNAPSHOT " .. snapshot_name)
    end
end

-- Switch to a snapshot (moves matrix position)
local function switch_to_snapshot(snapshot_name)
    -- Switch to snapshot moves matrix position to the corner
    -- Current snapshot is then derived from that position
    snapshot_mod.switch_to_snapshot(
        snapshot_name,
        params,
        freqs,
        grid_ui_state,
        glide_state,
        apply_blend,
        redraw,
        redraw_grid
    )
end




-- Grid redraw function
function redraw_grid()
    local g = grid_device
    g:all(0)
    local num = #freqs


    -- Draw main content based on mode
    if grid_ui_state.grid_mode >= 1 and grid_ui_state.grid_mode <= 4 then
        grid_draw_mod.draw_band_controls(g, num)
    elseif grid_ui_state.grid_mode == 6 then
        grid_draw_mod.draw_matrix_mode(g)
    end

    -- Draw UI controls
    grid_draw_mod.draw_ui_controls(g)

    g:refresh()
end

-- init
function init()
    screen.aa(0)
    screen.line_width(1)

    -- setup parameters
    add_params()

    -- Delay params:bang() to allow engine to fully initialize
    -- This prevents clicks on script load
    clock.run(function()
        clock.sleep(0.1) -- Wait 100ms for engine initialization
        params:bang()

        -- initialize current state and snapshots after params are loaded
        init_current_state()
        init_snapshots()
    end)

    -- setup grid UI
    grid_ui_state = grid_ui.init(grid_device, freqs, mode_names)
    band_meters = {}

    -- setup meters
    band_meter_polls = meters_mod.init(freqs, band_meters)

    -- initialize glide_state with default values
    glide_state.target_values.q = 1.0
    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)
        local decimate_id = string.format("band_%02d_decimate", i)
        glide_state.target_values[level_id] = 0.0
        glide_state.target_values[pan_id] = 0.0
        glide_state.target_values[thresh_id] = 0.0
        glide_state.target_values[decimate_id] = 48000
    end

    -- initialize modules with dependencies
    path_mod.init({
        grid_ui_state = grid_ui_state,
        apply_blend = apply_blend,
        redraw = redraw,
        metro = metro,
        util = util,
        params = params,
        path_state = path_state,
        glide_state = glide_state,
        show_banner = function(msg)
            if params:get("info_banner") == 2 then
                info_banner_mod.show(msg)
            end
        end
    })

    glide_mod.init({
        grid_ui_state = grid_ui_state,
        grid_device = grid_device,
        freqs = freqs,
        params = params,
        path_state = path_state,
        redraw_grid = redraw_grid,
        glide_state = glide_state
    })

    grid_draw_mod.init({
        grid_ui_state = grid_ui_state,
        band_meters = band_meters,
        util = util,
        params = params,
        calculate_blend_weights = calculate_blend_weights,
        path_state = path_state,
        glide_state = glide_state,
        get_current_snapshot = function() return get_current_snapshot_from_position() end
    })

    -- initialize blend module
    blend_mod = Blend.new(
        params, freqs, glide_state, grid_ui_state, util, engine,
        is_at_snapshot_corner, get_current_snapshot_from_position, store_snapshot, info_banner_mod
    )

    -- initialize screen draw module
    screen_draw_mod = ScreenDraw.new(
        params, freqs, grid_ui_state, input_mode_state, effects_mode_state,
        selected_band, band_meters, path_state, glide_state, util,
        selected_matrix_pos, get_current_snapshot_from_position, _path.audio
    )

    -- initialize info banner
    info_banner_mod.init({
        metro = metro
    })

    -- initialize screen indicators
    screen_indicators.init()

    -- start grid refresh metro
    metro_grid_refresh = metro.init(function()
        -- Always redraw grid - glide animation is drawn as part of normal grid drawing
        redraw_grid()
    end, 1 / 60)
    metro_grid_refresh:start()

    -- start screen refresh metro
    metro_screen_refresh = metro.init(function()
        redraw()
    end, 1 / 60) -- 60fps for smooth updates
    metro_screen_refresh:start()

    -- start glide metro
    metro_glide = metro.init(function()
        if glide_state.is_gliding then
            local current_time = util.time()
            local elapsed = current_time - glide_state.glide_time
            local glide_time = params:get("glide")

            if elapsed >= glide_time then
                glide_mod.complete_glide()
            else
                -- Update both parameters and visuals
                glide_mod.update_glide_progress(elapsed, glide_time)
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
        save_snapshot = save_snapshot,
        recall_snapshot = recall_snapshot,
        select_snapshot = select_snapshot,
        switch_to_snapshot = switch_to_snapshot,
        apply_blend = apply_blend,
        calculate_blend_weights = calculate_blend_weights,
        toggle_path_mode = path_mod.toggle_path_mode,
        toggle_path_recording = path_mod.toggle_path_recording,
        add_path_point = path_mod.add_path_point,
        remove_path_point = path_mod.remove_path_point,
        clear_path = path_mod.clear_path,
        get_path_mode = path_mod.get_path_mode,
        get_current_snapshot = function() return get_current_snapshot_from_position() end,
        get_freqs = function() return freqs end,
        get_mode_names = function() return mode_names end,
        get_band_meters = function() return band_meters end,
        get_input_mode_state = function() return input_mode_state end,
        set_selected_band = set_selected_band,
        redraw_grid = redraw_grid,
        show_banner = function(msg)
            if params:get("info_banner") == 2 then
                info_banner_mod.show(msg)
            end
        end
    })
end

-- screen redraw
function redraw()
    -- If file browser is active, let fileselect handle screen redraw
    if fileselect_active then
        return
    end

    screen.clear()
    screen.level(15)

    -- Mode-specific screens using screen_draw_mod
    if norns_mode == 0 then
        screen_draw_mod:draw_inputs_mode()
    elseif norns_mode == 1 then
        screen_draw_mod:draw_levels_screen()
    elseif norns_mode == 2 then
        screen_draw_mod:draw_pans_screen()
    elseif norns_mode == 3 then
        screen_draw_mod:draw_thresholds_screen()
    elseif norns_mode == 4 then
        screen_draw_mod:draw_decimate_screen()
    elseif norns_mode == 5 then
        screen_draw_mod:draw_effects_screen()
    elseif norns_mode == 6 then
        screen_draw_mod:draw_matrix_screen()
    end

    -- Draw screen indicators on the left side (7 modes total)
    screen_indicators.draw_screen_indicator(7, norns_mode + 1)

    -- Draw info banner on top of everything
    info_banner_mod.draw()

    screen.update()
end

-- key/enc handlers
-- Handle shift key (Key 1)
local function handle_shift_key(z)
    grid_ui_state.shift_held = (z == 1)
    -- Update grid shift LED
    if grid_device then
        grid_device:led(16, 8, grid_ui_state.shift_held and 15 or 0)
        grid_device:refresh()
    end
end

-- Handle inputs mode actions for Key 2 (previous input)
local function handle_key2_inputs_mode()
    input_mode_state.selected_input = util.clamp(input_mode_state.selected_input - 1, 1, 5)
    input_mode_state.selected_param = 1
    local input_names = { "INPUT", "OSCILLATOR", "DUST", "NOISE", "FILE" }
    if params:get("info_banner") == 2 then
        info_banner_mod.show(input_names[input_mode_state.selected_input])
    end
end

-- Handle effects mode actions for Key 2 (previous effect)
local function handle_key2_effects_mode()
    effects_mode_state.selected_effect = util.clamp(effects_mode_state.selected_effect - 1, 1, 2)
    effects_mode_state.selected_param = 1
    local effect_names = { "DELAY", "EQ" }
    if params:get("info_banner") == 2 then
        info_banner_mod.show(effect_names[effects_mode_state.selected_effect])
    end
end

-- Handle matrix mode actions for Key 2 (go to selected position)
local function handle_key2_matrix_mode()
    local old_x = grid_ui_state.current_matrix_pos.x
    local old_y = grid_ui_state.current_matrix_pos.y
    apply_blend(selected_matrix_pos.x, selected_matrix_pos.y, old_x, old_y)
    if params:get("info_banner") == 2 then
        info_banner_mod.show(string.format("POSITION %d,%d", selected_matrix_pos.x, selected_matrix_pos.y))
    end
end

-- Reset band parameters to default values
local function reset_band_params(mode)
    if mode == 1 then
        -- Reset levels to -12dB
        for i = 1, #freqs do
            params:set(string.format("band_%02d_level", i), -12)
        end
    elseif mode == 2 then
        -- Reset pans to center (0)
        for i = 1, #freqs do
            params:set(string.format("band_%02d_pan", i), 0)
        end
    elseif mode == 3 then
        -- Reset thresholds to 0.0
        for i = 1, #freqs do
            params:set(string.format("band_%02d_thresh", i), 0.0)
        end
    elseif mode == 4 then
        -- Reset decimate to 48000 Hz
        for i = 1, #freqs do
            params:set(string.format("band_%02d_decimate", i), 48000)
        end
    end
    store_snapshot(get_current_snapshot_from_position())
end

-- Handle band modes actions for Key 2 (reset)
local function handle_key2_band_modes()
    if grid_ui_state.current_state_mode then
        if params:get("info_banner") == 2 then
            info_banner_mod.show("CURRENT STATE MODE - EDITS DISABLED")
        end
        return
    end
    reset_band_params(norns_mode)
end

-- Handle Key 2 press
local function handle_key_2()
    if grid_ui_state.shift_held then
        copy_snapshot()
    elseif norns_mode == 0 then
        handle_key2_inputs_mode()
    elseif norns_mode == 5 then
        handle_key2_effects_mode()
    elseif norns_mode == 6 then
        handle_key2_matrix_mode()
    elseif norns_mode >= 1 and norns_mode <= 4 then
        handle_key2_band_modes()
    end
end

-- Handle inputs mode actions for Key 3 (next input)
local function handle_key3_inputs_mode()
    input_mode_state.selected_input = util.clamp(input_mode_state.selected_input + 1, 1, 5)
    input_mode_state.selected_param = 1
    local input_names = { "INPUT", "OSCILLATOR", "DUST", "NOISE", "FILE" }
    if params:get("info_banner") == 2 then
        info_banner_mod.show(input_names[input_mode_state.selected_input])
    end
end

-- Handle effects mode actions for Key 3 (next effect)
local function handle_key3_effects_mode()
    effects_mode_state.selected_effect = util.clamp(effects_mode_state.selected_effect + 1, 1, 2)
    effects_mode_state.selected_param = 1
    local effect_names = { "DELAY", "EQ" }
    if params:get("info_banner") == 2 then
        info_banner_mod.show(effect_names[effects_mode_state.selected_effect])
    end
end

-- Handle matrix mode actions for Key 3 (random position)
local function handle_key3_matrix_mode()
    selected_matrix_pos.x = math.random(1, 14)
    selected_matrix_pos.y = math.random(1, 14)
end

-- Randomize band parameters
local function randomize_band_params(mode)
    if mode == 1 then
        -- Randomize levels (-60dB to +12dB)
        for i = 1, #freqs do
            local random_level = math.random(-60, 12)
            params:set(string.format("band_%02d_level", i), random_level)
        end
    elseif mode == 2 then
        -- Randomize pans (-1 to +1)
        for i = 1, #freqs do
            local random_pan = (math.random() - 0.5) * 2
            params:set(string.format("band_%02d_pan", i), random_pan)
        end
    elseif mode == 3 then
        -- Randomize thresholds (0.0 to 0.2)
        for i = 1, #freqs do
            local random_thresh = math.random() * 0.2
            params:set(string.format("band_%02d_thresh", i), random_thresh)
        end
    elseif mode == 4 then
        -- Randomize decimate rates (100 to 48000 Hz)
        for i = 1, #freqs do
            local random_normalized = math.random()
            local random_rate = math.floor(48000 * math.exp(-random_normalized * 6.2))
            params:set(string.format("band_%02d_decimate", i), random_rate)
        end
    end
    store_snapshot(get_current_snapshot_from_position())
end

-- Handle band modes actions for Key 3 (randomize)
local function handle_key3_band_modes()
    if grid_ui_state.current_state_mode then
        if params:get("info_banner") == 2 then
            info_banner_mod.show("CURRENT STATE MODE - EDITS DISABLED")
        end
        return
    end
    randomize_band_params(norns_mode)
end

-- Handle Key 3 press
local function handle_key_3()
    if grid_ui_state.shift_held then
        paste_snapshot()
    elseif norns_mode == 0 then
        handle_key3_inputs_mode()
    elseif norns_mode == 5 then
        handle_key3_effects_mode()
    elseif norns_mode == 6 then
        handle_key3_matrix_mode()
    elseif norns_mode >= 1 and norns_mode <= 4 then
        handle_key3_band_modes()
    end
end

-- Main key handler
function key(n, z)
    if n == 1 then
        handle_shift_key(z)
    elseif z == 1 then -- Key press (not release)
        if n == 2 then
            handle_key_2()
        elseif n == 3 then
            handle_key_3()
        end
    end
end

-- Handle Encoder 1: Mode switching or snapshot selection
local function handle_enc_1(d)
    if grid_ui_state.shift_held then
        -- Shift + Encoder 1: Switch/Select snapshots
        local snapshots_list = { "A", "B", "C", "D" }
        local current_snapshot = get_current_snapshot_from_position()
        local current_index = 1
        for i, snap in ipairs(snapshots_list) do
            if snap == current_snapshot then
                current_index = i
                break
            end
        end

        local new_index = current_index + d
        new_index = util.clamp(new_index, 1, 4)

        -- Use select_snapshot when current_state_mode is OFF, switch_to_snapshot when ON
        if grid_ui_state.current_state_mode then
            switch_to_snapshot(snapshots_list[new_index])
        else
            select_snapshot(snapshots_list[new_index])
        end
    else
        -- Encoder 1: Switch between modes; keep grid in sync except for matrix
        local old_mode = norns_mode
        norns_mode = util.clamp(norns_mode + d, 0, 6)
        if norns_mode ~= old_mode then
            if norns_mode >= 1 and norns_mode <= 4 then
                grid_ui_state.grid_mode = norns_mode
            elseif norns_mode == 6 then
                -- Don't force grid into matrix; leave as-is
            elseif norns_mode == 0 or norns_mode == 5 then
                -- Inputs/Effects have no direct grid mode; leave grid mode unchanged
            end
            redraw_grid()
        end

        -- Show mode change banner
        if params:get("info_banner") == 2 then
            local mode_name = mode_names[norns_mode + 1] or "unknown"
            info_banner_mod.show(mode_name)
        end
    end
end

-- Handle Encoder 2: Parameter/band selection
local function handle_enc_2(d)
    if grid_ui_state.shift_held then
        -- Shift + Encoder 2: Toggle current state mode
        grid_ui_state.current_state_mode = not grid_ui_state.current_state_mode
        redraw()
        redraw_grid()
        if params:get("info_banner") == 2 then
            info_banner_mod.show(grid_ui_state.current_state_mode and "CURRENT STATE ON" or "CURRENT STATE OFF")
        end
    elseif norns_mode == 0 then
        -- Inputs mode: Select parameter within current input type
        local max_params = 1 -- Default for Live (only 1 param)
        if input_mode_state.selected_input == 1 then
            max_params = 1
        elseif input_mode_state.selected_input == 2 then
            max_params = 6
        elseif input_mode_state.selected_input == 3 then
            max_params = 2
        elseif input_mode_state.selected_input == 4 then
            max_params = 5
        elseif input_mode_state.selected_input == 5 then
            max_params = 4
        end
        input_mode_state.selected_param = util.clamp(input_mode_state.selected_param + d, 1, max_params)
    elseif norns_mode == 5 then
        -- Effects mode: Select parameter within current effect type
        local max_params = (effects_mode_state.selected_effect == 1) and 4 or 5
        effects_mode_state.selected_param = util.clamp(effects_mode_state.selected_param + d, 1, max_params)
    elseif norns_mode == 6 then
        -- Matrix mode: Navigate X position
        selected_matrix_pos.x = selected_matrix_pos.x + d
        selected_matrix_pos.x = util.clamp(selected_matrix_pos.x, 1, 14)
    elseif norns_mode >= 1 and norns_mode <= 4 then
        -- Other modes: Select band
        selected_band = selected_band + d
        selected_band = util.clamp(selected_band, 1, #freqs)
    end
end

-- Handle inputs mode parameter adjustment for Encoder 3
local function handle_enc3_inputs_mode(d)
    -- Check for shift + encoder 3 for semitone pitch control (file input only)
    if grid_ui_state.shift_held and input_mode_state.selected_input == 5 then
        local current_speed = params:get("file_speed")
        local current_semitones = math.floor(math.log(current_speed) / math.log(2) * 12 + 0.5)
        local new_semitones = util.clamp(current_semitones + d, -24, 24)
        local new_speed = math.pow(2, new_semitones / 12)
        params:set("file_speed", new_speed)
        store_snapshot(get_current_snapshot_from_position())
        if params:get("info_banner") == 2 then
            info_banner_mod.show(string.format("PITCH: %+d semitones (%.2fx)", new_semitones, new_speed))
        end
        return
    end

    if input_mode_state.selected_input == 1 then
        -- Live: Audio In Level
        local current = params:get("audio_in_level")
        local new_val = util.clamp(current + d * 0.01, 0, 1)
        params:set("audio_in_level", new_val)
        store_snapshot(get_current_snapshot_from_position())
    elseif input_mode_state.selected_input == 2 then
        -- Osc: Adjust selected parameter
        local param_idx = input_mode_state.selected_param
        if param_idx == 1 then
            local current = params:get("osc_level")
            params:set("osc_level", util.clamp(current + d * 0.01, 0, 1))
        elseif param_idx == 2 then
            local current = params:get("osc_freq")
            params:set("osc_freq", util.clamp(current * math.exp(d * 0.05), 0.1, 2000))
        elseif param_idx == 3 then
            local current = params:get("osc_timbre")
            params:set("osc_timbre", util.clamp(current + d * 0.01, 0, 1))
        elseif param_idx == 4 then
            local current = params:get("osc_warp")
            params:set("osc_warp", util.clamp(current + d * 0.01, 0, 1))
        elseif param_idx == 5 then
            local current = params:get("osc_mod_rate")
            params:set("osc_mod_rate", util.clamp(current * math.exp(d * 0.05), 0.1, 100))
        elseif param_idx == 6 then
            local current = params:get("osc_mod_depth")
            params:set("osc_mod_depth", util.clamp(current + d * 0.01, 0, 1))
        end
        store_snapshot(get_current_snapshot_from_position())
    elseif input_mode_state.selected_input == 3 then
        -- Dust: Adjust selected parameter
        if input_mode_state.selected_param == 1 then
            local current = params:get("dust_level")
            params:set("dust_level", util.clamp(current + d * 0.01, 0, 1))
        elseif input_mode_state.selected_param == 2 then
            local current = params:get("dust_density")
            local new_val = math.floor(util.clamp(current * math.exp(d * 0.02), 1, 1000) + 0.5)
            if new_val == current then
                new_val = util.clamp(current + (d > 0 and 1 or -1), 1, 1000)
            end
            params:set("dust_density", new_val)
        end
        store_snapshot(get_current_snapshot_from_position())
    elseif input_mode_state.selected_input == 4 then
        -- Noise: Adjust selected parameter
        local param_idx = input_mode_state.selected_param
        if param_idx == 1 then
            local current = params:get("noise_level")
            params:set("noise_level", util.clamp(current + d * 0.01, 0, 1))
        elseif param_idx == 2 then
            local current = params:get("noise_lfo_rate")
            params:set("noise_lfo_rate", util.clamp(current + d * 0.1, 0, 20))
        elseif param_idx == 3 then
            local current = params:get("noise_lfo_depth")
            params:set("noise_lfo_depth", util.clamp(current + d * 0.01, 0, 1))
        elseif param_idx == 4 then
            local current = params:get("noise_lfo_rate_jitter_rate")
            params:set("noise_lfo_rate_jitter_rate", util.clamp(current + d * 0.05, 0, 5))
        elseif param_idx == 5 then
            local current = params:get("noise_lfo_rate_jitter_depth")
            params:set("noise_lfo_rate_jitter_depth", util.clamp(current + d * 0.01, 0, 1))
        end
        store_snapshot(get_current_snapshot_from_position())
    elseif input_mode_state.selected_input == 5 then
        -- File: Adjust selected parameter via Enc 3
        local param_idx = input_mode_state.selected_param
        if param_idx == 1 then
            -- Level
            local current = params:get("file_level")
            params:set("file_level", util.clamp(current + d * 0.01, 0, 1))
            store_snapshot(get_current_snapshot_from_position())
        elseif param_idx == 2 then
            -- Speed
            local current = params:get("file_speed")
            params:set("file_speed", util.clamp(current + d * 0.01, -4, 4))
            store_snapshot(get_current_snapshot_from_position())
        elseif param_idx == 3 then
            -- Play/Stop (toggle on any encoder turn)
            if d ~= 0 then
                local current = params:get("file_gate")
                params:set("file_gate", 1 - current)
                store_snapshot(get_current_snapshot_from_position())
                if params:get("info_banner") == 2 then
                    info_banner_mod.show(current == 0 and "FILE PLAY" or "FILE STOP")
                end
            end
        elseif param_idx == 4 then
            -- Select file (open file browser on any encoder turn)
            if d ~= 0 and not fileselect_active then
                fileselect_active = true
                fileselect.enter(_path.audio, file_select_callback, "audio")
            end
        end
    end
end

-- Handle effects mode parameter adjustment for Encoder 3
local function handle_enc3_effects_mode(d)
    if effects_mode_state.selected_effect == 1 then
        -- Delay effect
        local param_idx = effects_mode_state.selected_param
        if param_idx == 1 then
            local current = params:get("delay_time")
            -- Use exponential scaling with minimum step to prevent getting stuck
            local factor = math.exp(d * 0.05)
            local new_val = current * factor
            -- Ensure minimum step of 0.01s when very small
            if current < 0.1 and math.abs(new_val - current) < 0.01 then
                new_val = current + (d > 0 and 0.01 or -0.01)
            end
            params:set("delay_time", util.clamp(new_val, 0.01, 10.0))
        elseif param_idx == 2 then
            local current = params:get("delay_feedback")
            params:set("delay_feedback", util.clamp(current + d * 0.01, 0, 1))
        elseif param_idx == 3 then
            local current = params:get("delay_mix")
            params:set("delay_mix", util.clamp(current + d * 0.01, 0, 1))
        elseif param_idx == 4 then
            local current = params:get("delay_width")
            params:set("delay_width", util.clamp(current + d * 0.01, 0, 1))
        end
    elseif effects_mode_state.selected_effect == 2 then
        -- EQ effect
        local param_idx = effects_mode_state.selected_param
        if param_idx == 1 then
            local current = params:get("eq_low_cut")
            params:set("eq_low_cut", util.clamp(current * math.exp(d * 0.05), 10, 5000))
        elseif param_idx == 2 then
            local current = params:get("eq_high_cut")
            params:set("eq_high_cut", util.clamp(current * math.exp(d * 0.05), 500, 22000))
        elseif param_idx == 3 then
            local current = params:get("eq_low_gain")
            params:set("eq_low_gain", util.clamp(current + d * 0.5, -48, 24))
        elseif param_idx == 4 then
            local current = params:get("eq_mid_gain")
            params:set("eq_mid_gain", util.clamp(current + d * 0.5, -48, 24))
        elseif param_idx == 5 then
            local current = params:get("eq_high_gain")
            params:set("eq_high_gain", util.clamp(current + d * 0.5, -48, 24))
        end
    end
    store_snapshot(get_current_snapshot_from_position())
end

-- Handle matrix mode actions for Encoder 3
local function handle_enc3_matrix_mode(d)
    if grid_ui_state.shift_held then
        -- Shift + enc 3: Adjust glide time
        local current_glide = params:get("glide")
        local new_glide = util.clamp(current_glide + d * 0.1, 0.05, 20)
        params:set("glide", new_glide)
        if params:get("info_banner") == 2 then
            info_banner_mod.show(string.format("GLIDE: %.2fs", new_glide))
        end
    else
        -- Normal: Navigate Y position
        selected_matrix_pos.y = selected_matrix_pos.y + d
        selected_matrix_pos.y = util.clamp(selected_matrix_pos.y, 1, 14)
    end
end

-- Adjust all bands for a given mode
local function adjust_all_bands(mode, d)
    if mode == 1 then
        -- Adjust all levels
        local step = d * 0.5
        for i = 1, #freqs do
            local current_level = params:get(string.format("band_%02d_level", i))
            params:set(string.format("band_%02d_level", i), util.clamp(current_level + step, -60, 12))
        end
    elseif mode == 2 then
        -- Adjust all pans
        local step = d * 0.01
        for i = 1, #freqs do
            local current_pan = params:get(string.format("band_%02d_pan", i))
            params:set(string.format("band_%02d_pan", i), util.clamp(current_pan + step, -1, 1))
        end
    elseif mode == 3 then
        -- Adjust all thresholds
        local step = d * 0.01
        for i = 1, #freqs do
            local current_thresh = params:get(string.format("band_%02d_thresh", i))
            params:set(string.format("band_%02d_thresh", i), util.clamp(current_thresh + step, 0, 1))
        end
    elseif mode == 4 then
        -- Adjust all decimate rates
        local step = d * 500
        for i = 1, #freqs do
            local current_rate = params:get(string.format("band_%02d_decimate", i))
            params:set(string.format("band_%02d_decimate", i), util.clamp(current_rate + step, 100, 48000))
        end
    end
    store_snapshot(get_current_snapshot_from_position())
end

-- Adjust single band parameter
local function adjust_single_band(mode, band_idx, d)
    if mode == 1 then
        -- Adjust level
        local step = d * 0.5
        local current_level = params:get(string.format("band_%02d_level", band_idx))
        params:set(string.format("band_%02d_level", band_idx), util.clamp(current_level + step, -60, 12))
    elseif mode == 2 then
        -- Adjust pan
        local step = d * 0.01
        local current_pan = params:get(string.format("band_%02d_pan", band_idx))
        params:set(string.format("band_%02d_pan", band_idx), util.clamp(current_pan + step, -1, 1))
    elseif mode == 3 then
        -- Adjust threshold
        local step = d * 0.01
        local current_thresh = params:get(string.format("band_%02d_thresh", band_idx))
        params:set(string.format("band_%02d_thresh", band_idx), util.clamp(current_thresh + step, 0, 1))
    elseif mode == 4 then
        -- Adjust decimate rate
        local step = d * 500
        local current_rate = params:get(string.format("band_%02d_decimate", band_idx))
        params:set(string.format("band_%02d_decimate", band_idx), util.clamp(current_rate + step, 100, 48000))
    end
    store_snapshot(get_current_snapshot_from_position())
end

-- Handle band modes parameter adjustment for Encoder 3
local function handle_enc3_band_modes(d)
    if grid_ui_state.shift_held then
        -- Shift held: Adjust all bands
        adjust_all_bands(norns_mode, d)
    else
        -- No shift: Adjust selected band only
        adjust_single_band(norns_mode, selected_band, d)
    end
end

-- Handle Encoder 3: Value adjustment
local function handle_enc_3(d)
    -- Block edits globally when current state mode is ON
    if grid_ui_state.current_state_mode then
        if params:get("info_banner") == 2 then
            info_banner_mod.show("CURRENT STATE MODE - EDITS DISABLED")
        end
        return
    end

    if norns_mode == 0 then
        handle_enc3_inputs_mode(d)
    elseif norns_mode == 5 then
        handle_enc3_effects_mode(d)
    elseif norns_mode == 6 then
        handle_enc3_matrix_mode(d)
    elseif norns_mode >= 1 and norns_mode <= 4 then
        handle_enc3_band_modes(d)
    end
end

-- Main encoder handler
function enc(n, d)
    -- If file browser is active, let fileselect handle all input
    if fileselect_active then
        return
    end

    if n == 1 then
        handle_enc_1(d)
    elseif n == 2 then
        handle_enc_2(d)
    elseif n == 3 then
        handle_enc_3(d)
    end
end

-- parameters
function add_params()
    local num = #freqs

    -- ====================
    -- GLOBAL SETTINGS
    -- ====================
    params:add_separator("global_settings", "Global Settings")

    params:add {
        type = "control",
        id = "q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(q)
            if engine and engine.q then engine.q(q) end
            -- Also update current snapshot params
            local snapshot_q_id = string.format("snapshot_%s_q", string.lower(get_current_snapshot_from_position()))
            params:set(snapshot_q_id, q)
        end
    }

    params:add {
        type = "control",
        id = "glide",
        name = "Glide",
        controlspec = controlspec.new(0.05, 20, 'lin', 0.01, 0.1, 's'),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    params:add {
        type = "control",
        id = "decimate_smoothing",
        name = "Decimate Smooth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 1),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(smoothing)
            if engine and engine.decimate_smoothing then engine.decimate_smoothing(smoothing) end
        end
    }

    params:add {
        type = "option",
        id = "info_banner",
        name = "Info Banner",
        options = { "Off", "On" },
        default = 2
    }

    -- ====================
    -- INPUT SOURCES
    -- ====================
    params:add_separator("input_sources", "Input Sources")

    -- Audio In
    params:add_separator("audio_in_section", "> Audio In")
    params:add {
        type = "control",
        id = "audio_in_level",
        name = "Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0), -- Default 0.0 (user brings it up manually)
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(level)
            if engine and engine.audio_in_level then engine.audio_in_level(level) end
        end
    }

    -- Noise
    params:add_separator("noise_section", "> Noise")
    params:add {
        type = "control",
        id = "noise_level",
        name = "Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(level)
            if engine and engine.noise_level then engine.noise_level(level) end
        end
    }

    params:add {
        type = "control",
        id = "noise_lfo_rate",
        name = "LFO Rate",
        controlspec = controlspec.new(0, 20, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p)
            local val = p:get()
            if val == 0 then
                return "Off"
            else
                return string.format("%.2f Hz", val)
            end
        end,
        action = function(rate)
            if engine and engine.noise_lfo_rate then engine.noise_lfo_rate(rate) end
        end
    }

    params:add {
        type = "control",
        id = "noise_lfo_depth",
        name = "LFO Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end,
        action = function(depth)
            if engine and engine.noise_lfo_depth then engine.noise_lfo_depth(depth) end
        end
    }

    -- Noise LFO rate jitter controls
    params:add {
        type = "control",
        id = "noise_lfo_rate_jitter_rate",
        name = "LFO Rate Jitter Rate",
        controlspec = controlspec.new(0, 10, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end,
        action = function(rate)
            if engine and engine.noise_lfo_rate_jitter_rate then engine.noise_lfo_rate_jitter_rate(rate) end
        end
    }

    params:add {
        type = "control",
        id = "noise_lfo_rate_jitter_depth",
        name = "LFO Rate Jitter Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end,
        action = function(depth)
            if engine and engine.noise_lfo_rate_jitter_depth then engine.noise_lfo_rate_jitter_depth(depth) end
        end
    }

    -- Dust
    params:add_separator("dust_section", "> Dust")
    params:add {
        type = "control",
        id = "dust_level",
        name = "Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(level)
            if engine and engine.dust_level then engine.dust_level(level) end
        end
    }

    params:add {
        type = "control",
        id = "dust_density",
        name = "Density",
        controlspec = controlspec.new(1, 1000, 'exp', 1, 10, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end,
        action = function(density)
            if engine and engine.dust_density then engine.dust_density(density) end
        end
    }

    -- Oscillator
    params:add_separator("osc_section", "> Oscillator")
    params:add {
        type = "control",
        id = "osc_level",
        name = "Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(level)
            if engine and engine.osc_level then engine.osc_level(level) end
        end
    }

    params:add {
        type = "control",
        id = "osc_freq",
        name = "Frequency",
        controlspec = controlspec.new(0.1, 2000, 'exp', 0, 5, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end,
        action = function(freq)
            if engine and engine.osc_freq then engine.osc_freq(freq) end
        end
    }

    params:add {
        type = "control",
        id = "osc_timbre",
        name = "Timbre",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.3),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(timbre)
            if engine and engine.osc_timbre then engine.osc_timbre(timbre) end
        end
    }

    params:add {
        type = "control",
        id = "osc_warp",
        name = "Morph",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(warp)
            if engine and engine.osc_warp then engine.osc_warp(warp) end
        end
    }

    params:add {
        type = "control",
        id = "osc_mod_rate",
        name = "Mod Rate",
        controlspec = controlspec.new(0.1, 100, 'exp', 0.1, 5.0, 'Hz'),
        formatter = function(p) return string.format("%.1f Hz", p:get()) end,
        action = function(rate)
            if engine and engine.osc_mod_rate then engine.osc_mod_rate(rate) end
        end
    }

    params:add {
        type = "control",
        id = "osc_mod_depth",
        name = "Mod Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(depth)
            if engine and engine.osc_mod_depth then engine.osc_mod_depth(depth) end
        end
    }

    -- File
    params:add_separator("file_section", "> File")
    params:add {
        type = "file",
        id = "file_path",
        name = "File Path",
        path = _path.audio,
        action = function(file)
            if engine and engine.file_load and file ~= "" then
                engine.file_load(file)
            end
        end
    }

    params:add {
        type = "control",
        id = "file_level",
        name = "Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(level)
            if engine and engine.file_level then engine.file_level(level) end
        end
    }

    params:add {
        type = "control",
        id = "file_speed",
        name = "Speed",
        controlspec = controlspec.new(-4, 4, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(speed)
            if engine and engine.file_speed then engine.file_speed(speed) end
        end
    }


    params:add {
        type = "binary",
        id = "file_gate",
        name = "Play/Stop",
        behavior = "toggle",
        default = 0,
        action = function(gate)
            if engine and engine.file_gate then engine.file_gate(gate) end
        end
    }

    -- ====================
    -- OUTPUT EFFECTS
    -- ====================
    params:add_separator("output_effects", "Output Effects")

    -- Delay
    params:add_separator("delay_section", "> Delay")
    params:add {
        type = "control",
        id = "delay_time",
        name = "Time",
        controlspec = controlspec.new(0.01, 10.0, 'exp', 0.01, 0.5, 's'),
        formatter = function(p) return string.format("%.2fs", p:get()) end,
        action = function(time)
            if engine and engine.delay_time then engine.delay_time(time) end
        end
    }

    params:add {
        type = "control",
        id = "delay_feedback",
        name = "Feedback",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(feedback)
            if engine and engine.delay_feedback then engine.delay_feedback(feedback) end
        end
    }

    params:add {
        type = "control",
        id = "delay_mix",
        name = "Mix",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(mix)
            if engine and engine.delay_mix then engine.delay_mix(mix) end
        end
    }

    params:add {
        type = "control",
        id = "delay_width",
        name = "Width",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end,
        action = function(width)
            if engine and engine.delay_width then engine.delay_width(width) end
        end
    }

    -- EQ
    params:add_separator("eq_section", "> EQ")
    params:add {
        type = "control",
        id = "eq_low_cut",
        name = "Low Cut",
        controlspec = controlspec.new(10, 5000, 'exp', 1, 20, 'Hz'), -- More extreme: 10Hz-5kHz
        formatter = function(p) return string.format("%.0f Hz", p:get()) end,
        action = function(freq)
            if engine and engine.eq_low_cut then engine.eq_low_cut(freq) end
        end
    }

    params:add {
        type = "control",
        id = "eq_high_cut",
        name = "High Cut",
        controlspec = controlspec.new(500, 22000, 'exp', 1, 20000, 'Hz'), -- More extreme: 500Hz-22kHz
        formatter = function(p) return string.format("%.0f Hz", p:get()) end,
        action = function(freq)
            if engine and engine.eq_high_cut then engine.eq_high_cut(freq) end
        end
    }

    params:add {
        type = "control",
        id = "eq_low_gain",
        name = "Low Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'), -- More extreme: -48 to +24 dB
        formatter = function(p) return string.format("%.1f dB", p:get()) end,
        action = function(gain)
            if engine and engine.eq_low_gain then engine.eq_low_gain(gain) end
        end
    }

    params:add {
        type = "control",
        id = "eq_mid_gain",
        name = "Mid Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'), -- More extreme: -48 to +24 dB
        formatter = function(p) return string.format("%.1f dB", p:get()) end,
        action = function(gain)
            if engine and engine.eq_mid_gain then engine.eq_mid_gain(gain) end
        end
    }

    params:add {
        type = "control",
        id = "eq_high_gain",
        name = "High Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'), -- More extreme: -48 to +24 dB
        formatter = function(p) return string.format("%.1f dB", p:get()) end,
        action = function(gain)
            if engine and engine.eq_high_gain then engine.eq_high_gain(gain) end
        end
    }

    -- ====================
    -- SNAPSHOTS
    -- ====================
    params:add_separator("snapshots_section", "Snapshots")

    -- Snapshot A
    params:add_group("snapshot A", 91)
    params:add {
        type = "control",
        id = "snapshot_a_q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    -- Input source settings for snapshot A
    params:add {
        type = "control",
        id = "snapshot_a_audio_in_level",
        name = "Audio In Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_noise_level",
        name = "Noise Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_dust_level",
        name = "Dust Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_noise_lfo_rate",
        name = "Noise LFO Rate",
        controlspec = controlspec.new(0, 20, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p)
            local val = p:get()
            if val == 0 then
                return "Off"
            else
                return string.format("%.2f Hz", val)
            end
        end
    }
    params:add {
        type = "control",
        id = "snapshot_a_noise_lfo_depth",
        name = "Noise LFO Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_noise_lfo_rate_jitter_rate",
        name = "Noise LFO Rate Jitter Rate",
        controlspec = controlspec.new(0, 5, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_noise_lfo_rate_jitter_depth",
        name = "Noise LFO Rate Jitter Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_dust_density",
        name = "Dust Density",
        controlspec = controlspec.new(1, 1000, 'exp', 1, 10, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_osc_level",
        name = "Osc Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_osc_freq",
        name = "Osc Freq",
        controlspec = controlspec.new(0.1, 2000, 'exp', 0, 220, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_osc_timbre",
        name = "Osc Timbre",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.3),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_osc_warp",
        name = "Osc Morph",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_osc_mod_rate",
        name = "Osc Mod Rate",
        controlspec = controlspec.new(0.1, 100, 'exp', 0.1, 5.0, 'Hz'),
        formatter = function(p) return string.format("%.1f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_osc_mod_depth",
        name = "Osc Mod Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_file_level",
        name = "File Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_file_speed",
        name = "File Speed",
        controlspec = controlspec.new(-4, 4, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "binary",
        id = "snapshot_a_file_gate",
        name = "File Gate",
        behavior = "toggle",
        default = 0
    }
    params:add {
        type = "control",
        id = "snapshot_a_delay_time",
        name = "Delay Time",
        controlspec = controlspec.new(0.01, 10.0, 'exp', 0.01, 0.5, 's'),
        formatter = function(p) return string.format("%.2fs", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_delay_feedback",
        name = "Delay Feedback",
        controlspec = controlspec.new(0, 1.2, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_delay_mix",
        name = "Delay Mix",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_delay_width",
        name = "Delay Width",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_eq_low_cut",
        name = "EQ Low Cut",
        controlspec = controlspec.new(10, 5000, 'exp', 1, 20, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_eq_high_cut",
        name = "EQ High Cut",
        controlspec = controlspec.new(500, 22000, 'exp', 1, 20000, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_eq_low_gain",
        name = "EQ Low Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_eq_mid_gain",
        name = "EQ Mid Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_a_eq_high_gain",
        name = "EQ High Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }

    for i = 1, num do
        local hz = freqs[i]
        params:add {
            type = "control",
            id = string.format("snapshot_a_%02d_level", i),
            name = string.format("%02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_a_%02d_pan", i),
            name = string.format("%02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_a_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(0, 0.2, 'lin', 0.001, 0),
            formatter = function(p) return string.format("%.3f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_a_%02d_decimate", i),
            name = string.format("%02d Decimate", i),
            controlspec = controlspec.new(100, 48000, 'exp', 1, 48000),
            formatter = function(p) return string.format("%.0f Hz", p:get()) end
        }
    end

    -- Snapshot B
    params:add_group("snapshot B", 91)
    params:add {
        type = "control",
        id = "snapshot_b_q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    -- Input source settings for snapshot B
    params:add {
        type = "control",
        id = "snapshot_b_audio_in_level",
        name = "Audio In Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_noise_level",
        name = "Noise Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_dust_level",
        name = "Dust Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_noise_lfo_rate",
        name = "Noise LFO Rate",
        controlspec = controlspec.new(0, 20, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p)
            local val = p:get()
            if val == 0 then
                return "Off"
            else
                return string.format("%.2f Hz", val)
            end
        end
    }
    params:add {
        type = "control",
        id = "snapshot_b_noise_lfo_depth",
        name = "Noise LFO Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_noise_lfo_rate_jitter_rate",
        name = "Noise LFO Rate Jitter Rate",
        controlspec = controlspec.new(0, 5, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_noise_lfo_rate_jitter_depth",
        name = "Noise LFO Rate Jitter Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_dust_density",
        name = "Dust Density",
        controlspec = controlspec.new(1, 1000, 'exp', 1, 10, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_osc_level",
        name = "Osc Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_osc_freq",
        name = "Osc Freq",
        controlspec = controlspec.new(0.1, 2000, 'exp', 0, 220, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_osc_timbre",
        name = "Osc Timbre",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.3),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_osc_warp",
        name = "Osc Morph",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_osc_mod_rate",
        name = "Osc Mod Rate",
        controlspec = controlspec.new(0.1, 100, 'exp', 0.1, 5.0, 'Hz'),
        formatter = function(p) return string.format("%.1f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_osc_mod_depth",
        name = "Osc Mod Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_file_level",
        name = "File Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_file_speed",
        name = "File Speed",
        controlspec = controlspec.new(-4, 4, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "binary",
        id = "snapshot_b_file_gate",
        name = "File Gate",
        behavior = "toggle",
        default = 0
    }
    params:add {
        type = "control",
        id = "snapshot_b_delay_time",
        name = "Delay Time",
        controlspec = controlspec.new(0.01, 10.0, 'exp', 0.01, 0.5, 's'),
        formatter = function(p) return string.format("%.2fs", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_delay_feedback",
        name = "Delay Feedback",
        controlspec = controlspec.new(0, 1.2, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_delay_mix",
        name = "Delay Mix",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_delay_width",
        name = "Delay Width",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_eq_low_cut",
        name = "EQ Low Cut",
        controlspec = controlspec.new(10, 5000, 'exp', 1, 20, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_eq_high_cut",
        name = "EQ High Cut",
        controlspec = controlspec.new(500, 22000, 'exp', 1, 20000, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_eq_low_gain",
        name = "EQ Low Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_eq_mid_gain",
        name = "EQ Mid Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_b_eq_high_gain",
        name = "EQ High Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }

    for i = 1, num do
        local hz = freqs[i]
        params:add {
            type = "control",
            id = string.format("snapshot_b_%02d_level", i),
            name = string.format("%02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_b_%02d_pan", i),
            name = string.format("%02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_b_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(0, 0.2, 'lin', 0.001, 0),
            formatter = function(p) return string.format("%.3f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_b_%02d_decimate", i),
            name = string.format("%02d Decimate", i),
            controlspec = controlspec.new(100, 48000, 'exp', 1, 48000),
            formatter = function(p) return string.format("%.0f Hz", p:get()) end
        }
    end

    -- Snapshot C
    params:add_group("snapshot C", 91)
    params:add {
        type = "control",
        id = "snapshot_c_q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    -- Input source settings for snapshot C
    params:add {
        type = "control",
        id = "snapshot_c_audio_in_level",
        name = "Audio In Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_noise_level",
        name = "Noise Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_dust_level",
        name = "Dust Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_noise_lfo_rate",
        name = "Noise LFO Rate",
        controlspec = controlspec.new(0, 20, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p)
            local val = p:get()
            if val == 0 then
                return "Off"
            else
                return string.format("%.2f Hz", val)
            end
        end
    }
    params:add {
        type = "control",
        id = "snapshot_c_noise_lfo_depth",
        name = "Noise LFO Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_noise_lfo_rate_jitter_rate",
        name = "Noise LFO Rate Jitter Rate",
        controlspec = controlspec.new(0, 5, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_noise_lfo_rate_jitter_depth",
        name = "Noise LFO Rate Jitter Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_dust_density",
        name = "Dust Density",
        controlspec = controlspec.new(1, 1000, 'exp', 1, 10, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_osc_level",
        name = "Osc Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_osc_freq",
        name = "Osc Freq",
        controlspec = controlspec.new(0.1, 2000, 'exp', 0, 220, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_osc_timbre",
        name = "Osc Timbre",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.3),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_osc_warp",
        name = "Osc Morph",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_osc_mod_rate",
        name = "Osc Mod Rate",
        controlspec = controlspec.new(0.1, 100, 'exp', 0.1, 5.0, 'Hz'),
        formatter = function(p) return string.format("%.1f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_osc_mod_depth",
        name = "Osc Mod Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_file_level",
        name = "File Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_file_speed",
        name = "File Speed",
        controlspec = controlspec.new(-4, 4, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "binary",
        id = "snapshot_c_file_gate",
        name = "File Gate",
        behavior = "toggle",
        default = 0
    }
    params:add {
        type = "control",
        id = "snapshot_c_delay_time",
        name = "Delay Time",
        controlspec = controlspec.new(0.01, 10.0, 'exp', 0.01, 0.5, 's'),
        formatter = function(p) return string.format("%.2fs", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_delay_feedback",
        name = "Delay Feedback",
        controlspec = controlspec.new(0, 1.2, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_delay_mix",
        name = "Delay Mix",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_delay_width",
        name = "Delay Width",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_eq_low_cut",
        name = "EQ Low Cut",
        controlspec = controlspec.new(10, 5000, 'exp', 1, 20, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_eq_high_cut",
        name = "EQ High Cut",
        controlspec = controlspec.new(500, 22000, 'exp', 1, 20000, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_eq_low_gain",
        name = "EQ Low Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_eq_mid_gain",
        name = "EQ Mid Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_c_eq_high_gain",
        name = "EQ High Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }

    for i = 1, num do
        local hz = freqs[i]
        params:add {
            type = "control",
            id = string.format("snapshot_c_%02d_level", i),
            name = string.format("%02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_c_%02d_pan", i),
            name = string.format("%02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_c_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(0, 0.2, 'lin', 0.001, 0),
            formatter = function(p) return string.format("%.3f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_c_%02d_decimate", i),
            name = string.format("%02d Decimate", i),
            controlspec = controlspec.new(100, 48000, 'exp', 1, 48000),
            formatter = function(p) return string.format("%.0f Hz", p:get()) end
        }
    end

    -- Snapshot D
    params:add_group("snapshot D", 91)
    params:add {
        type = "control",
        id = "snapshot_d_q",
        name = "Q",
        controlspec = controlspec.new(1, 2, 'lin', 0, 1.1, ''),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }

    -- Input source settings for snapshot D
    params:add {
        type = "control",
        id = "snapshot_d_audio_in_level",
        name = "Audio In Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_noise_level",
        name = "Noise Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_dust_level",
        name = "Dust Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_noise_lfo_rate",
        name = "Noise LFO Rate",
        controlspec = controlspec.new(0, 20, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p)
            local val = p:get()
            if val == 0 then
                return "Off"
            else
                return string.format("%.2f Hz", val)
            end
        end
    }
    params:add {
        type = "control",
        id = "snapshot_d_noise_lfo_depth",
        name = "Noise LFO Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_noise_lfo_rate_jitter_rate",
        name = "Noise LFO Rate Jitter Rate",
        controlspec = controlspec.new(0, 5, 'lin', 0.01, 0, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_noise_lfo_rate_jitter_depth",
        name = "Noise LFO Rate Jitter Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.0f%%", p:get() * 100) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_dust_density",
        name = "Dust Density",
        controlspec = controlspec.new(1, 1000, 'exp', 1, 10, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_osc_level",
        name = "Osc Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_osc_freq",
        name = "Osc Freq",
        controlspec = controlspec.new(0.1, 2000, 'exp', 0, 220, 'Hz'),
        formatter = function(p) return string.format("%.2f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_osc_timbre",
        name = "Osc Timbre",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.3),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_osc_warp",
        name = "Osc Morph",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_osc_mod_rate",
        name = "Osc Mod Rate",
        controlspec = controlspec.new(0.1, 100, 'exp', 0.1, 5.0, 'Hz'),
        formatter = function(p) return string.format("%.1f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_osc_mod_depth",
        name = "Osc Mod Depth",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_file_level",
        name = "File Level",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_file_speed",
        name = "File Speed",
        controlspec = controlspec.new(-4, 4, 'lin', 0.01, 1.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "binary",
        id = "snapshot_d_file_gate",
        name = "File Gate",
        behavior = "toggle",
        default = 0
    }
    params:add {
        type = "control",
        id = "snapshot_d_delay_time",
        name = "Delay Time",
        controlspec = controlspec.new(0.01, 10.0, 'exp', 0.01, 0.5, 's'),
        formatter = function(p) return string.format("%.2fs", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_delay_feedback",
        name = "Delay Feedback",
        controlspec = controlspec.new(0, 1.2, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_delay_mix",
        name = "Delay Mix",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.0),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_delay_width",
        name = "Delay Width",
        controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.5),
        formatter = function(p) return string.format("%.2f", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_eq_low_cut",
        name = "EQ Low Cut",
        controlspec = controlspec.new(10, 5000, 'exp', 1, 20, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_eq_high_cut",
        name = "EQ High Cut",
        controlspec = controlspec.new(500, 22000, 'exp', 1, 20000, 'Hz'),
        formatter = function(p) return string.format("%.0f Hz", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_eq_low_gain",
        name = "EQ Low Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_eq_mid_gain",
        name = "EQ Mid Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }
    params:add {
        type = "control",
        id = "snapshot_d_eq_high_gain",
        name = "EQ High Gain",
        controlspec = controlspec.new(-48, 24, 'lin', 0.1, 0, 'dB'),
        formatter = function(p) return string.format("%.1f dB", p:get()) end
    }

    for i = 1, num do
        local hz = freqs[i]
        params:add {
            type = "control",
            id = string.format("snapshot_d_%02d_level", i),
            name = string.format("%02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12),
            formatter = function(p) return string.format("%.1f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_d_%02d_pan", i),
            name = string.format("%02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_d_%02d_thresh", i),
            name = string.format("%02d Thresh", i),
            controlspec = controlspec.new(0, 0.2, 'lin', 0.001, 0),
            formatter = function(p) return string.format("%.3f", p:get()) end
        }
        params:add {
            type = "control",
            id = string.format("snapshot_d_%02d_decimate", i),
            name = string.format("%02d Decimate", i),
            controlspec = controlspec.new(100, 48000, 'exp', 1, 48000),
            formatter = function(p) return string.format("%.0f Hz", p:get()) end
        }
    end

    -- ====================
    -- BANDS (Current State)
    -- ====================
    params:add_group("bands", num * 4)
    for i = 1, num do
        params:add {
            type = "control",
            id = string.format("band_%02d_level", i),
            name = string.format("Band %02d Level", i),
            controlspec = controlspec.new(-60, 12, 'lin', 0.1, -12, 'dB'),
            formatter = function(p) return string.format("%.1f dB", p:get()) end,
            action = function(level)
                if engine and engine.level then engine.level(i, level) end
            end
        }
        params:add {
            type = "control",
            id = string.format("band_%02d_pan", i),
            name = string.format("Band %02d Pan", i),
            controlspec = controlspec.new(-1, 1, 'lin', 0.01, 0),
            formatter = function(p) return string.format("%.2f", p:get()) end,
            action = function(pan)
                if engine and engine.pan then engine.pan(i, pan) end
            end
        }
        params:add {
            type = "control",
            id = string.format("band_%02d_thresh", i),
            name = string.format("Band %02d Thresh", i),
            controlspec = controlspec.new(0, 0.2, 'lin', 0.001, 0),
            formatter = function(p) return string.format("%.3f", p:get()) end,
            action = function(thresh)
                if engine and engine.thresh_band then engine.thresh_band(i, thresh) end
            end
        }
        params:add {
            type = "control",
            id = string.format("band_%02d_decimate", i),
            name = string.format("Band %02d Decimate", i),
            controlspec = controlspec.new(100, 48000, 'exp', 1, 48000, 'Hz'),
            formatter = function(p) return string.format("%.0f Hz", p:get()) end,
            action = function(rate)
                if engine and engine.decimate_band then engine.decimate_band(i, rate) end
            end
        }
    end
end
