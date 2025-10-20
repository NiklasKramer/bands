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

-- params
local controlspec = require 'controlspec'
local util = require 'util'

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

-- Get current snapshot based on matrix position
local function get_current_snapshot_from_position()
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
    clipboard.dust_density = params:get("dust_density")
    clipboard.osc_level = params:get("osc_level")
    clipboard.osc_freq = params:get("osc_freq")
    clipboard.osc_timbre = params:get("osc_timbre")
    clipboard.osc_warp = params:get("osc_warp")
    clipboard.osc_mod_rate = params:get("osc_mod_rate")
    clipboard.osc_mod_depth = params:get("osc_mod_depth")
    clipboard.file_level = params:get("file_level")
    clipboard.file_speed = params:get("file_speed")

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
    params:set("dust_density", clipboard.dust_density)
    params:set("osc_level", clipboard.osc_level)
    params:set("osc_freq", clipboard.osc_freq)
    params:set("osc_timbre", clipboard.osc_timbre)
    params:set("osc_warp", clipboard.osc_warp)
    params:set("osc_mod_rate", clipboard.osc_mod_rate)
    params:set("osc_mod_depth", clipboard.osc_mod_depth)
    params:set("file_level", clipboard.file_level)
    params:set("file_speed", clipboard.file_speed)

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
    x = math.max(1, math.min(14, x))
    y = math.max(1, math.min(14, y))

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

    -- Calculate target values
    local target_values = {}

    -- Blend global Q from params
    target_values.q = params:get("snapshot_a_q") * a_w +
        params:get("snapshot_b_q") * b_w +
        params:get("snapshot_c_q") * c_w +
        params:get("snapshot_d_q") * d_w

    -- Blend input settings (all can blend smoothly now)
    target_values.audio_in_level = params:get("snapshot_a_audio_in_level") * a_w +
        params:get("snapshot_b_audio_in_level") * b_w +
        params:get("snapshot_c_audio_in_level") * c_w +
        params:get("snapshot_d_audio_in_level") * d_w

    target_values.noise_level = params:get("snapshot_a_noise_level") * a_w +
        params:get("snapshot_b_noise_level") * b_w +
        params:get("snapshot_c_noise_level") * c_w +
        params:get("snapshot_d_noise_level") * d_w

    target_values.dust_level = params:get("snapshot_a_dust_level") * a_w +
        params:get("snapshot_b_dust_level") * b_w +
        params:get("snapshot_c_dust_level") * c_w +
        params:get("snapshot_d_dust_level") * d_w

    target_values.noise_lfo_rate = params:get("snapshot_a_noise_lfo_rate") * a_w +
        params:get("snapshot_b_noise_lfo_rate") * b_w +
        params:get("snapshot_c_noise_lfo_rate") * c_w +
        params:get("snapshot_d_noise_lfo_rate") * d_w

    target_values.noise_lfo_depth = params:get("snapshot_a_noise_lfo_depth") * a_w +
        params:get("snapshot_b_noise_lfo_depth") * b_w +
        params:get("snapshot_c_noise_lfo_depth") * c_w +
        params:get("snapshot_d_noise_lfo_depth") * d_w

    target_values.dust_density = params:get("snapshot_a_dust_density") * a_w +
        params:get("snapshot_b_dust_density") * b_w +
        params:get("snapshot_c_dust_density") * c_w +
        params:get("snapshot_d_dust_density") * d_w

    target_values.osc_level = params:get("snapshot_a_osc_level") * a_w +
        params:get("snapshot_b_osc_level") * b_w +
        params:get("snapshot_c_osc_level") * c_w +
        params:get("snapshot_d_osc_level") * d_w

    target_values.osc_freq = params:get("snapshot_a_osc_freq") * a_w +
        params:get("snapshot_b_osc_freq") * b_w +
        params:get("snapshot_c_osc_freq") * c_w +
        params:get("snapshot_d_osc_freq") * d_w

    target_values.osc_timbre = params:get("snapshot_a_osc_timbre") * a_w +
        params:get("snapshot_b_osc_timbre") * b_w +
        params:get("snapshot_c_osc_timbre") * c_w +
        params:get("snapshot_d_osc_timbre") * d_w

    target_values.osc_warp = params:get("snapshot_a_osc_warp") * a_w +
        params:get("snapshot_b_osc_warp") * b_w +
        params:get("snapshot_c_osc_warp") * c_w +
        params:get("snapshot_d_osc_warp") * d_w

    target_values.osc_mod_rate = params:get("snapshot_a_osc_mod_rate") * a_w +
        params:get("snapshot_b_osc_mod_rate") * b_w +
        params:get("snapshot_c_osc_mod_rate") * c_w +
        params:get("snapshot_d_osc_mod_rate") * d_w

    target_values.osc_mod_depth = params:get("snapshot_a_osc_mod_depth") * a_w +
        params:get("snapshot_b_osc_mod_depth") * b_w +
        params:get("snapshot_c_osc_mod_depth") * c_w +
        params:get("snapshot_d_osc_mod_depth") * d_w

    target_values.file_level = params:get("snapshot_a_file_level") * a_w +
        params:get("snapshot_b_file_level") * b_w +
        params:get("snapshot_c_file_level") * c_w +
        params:get("snapshot_d_file_level") * d_w

    target_values.file_speed = params:get("snapshot_a_file_speed") * a_w +
        params:get("snapshot_b_file_speed") * b_w +
        params:get("snapshot_c_file_speed") * c_w +
        params:get("snapshot_d_file_speed") * d_w

    target_values.delay_time = params:get("snapshot_a_delay_time") * a_w +
        params:get("snapshot_b_delay_time") * b_w +
        params:get("snapshot_c_delay_time") * c_w +
        params:get("snapshot_d_delay_time") * d_w

    target_values.delay_feedback = params:get("snapshot_a_delay_feedback") * a_w +
        params:get("snapshot_b_delay_feedback") * b_w +
        params:get("snapshot_c_delay_feedback") * c_w +
        params:get("snapshot_d_delay_feedback") * d_w

    target_values.delay_mix = params:get("snapshot_a_delay_mix") * a_w +
        params:get("snapshot_b_delay_mix") * b_w +
        params:get("snapshot_c_delay_mix") * c_w +
        params:get("snapshot_d_delay_mix") * d_w

    target_values.delay_width = params:get("snapshot_a_delay_width") * a_w +
        params:get("snapshot_b_delay_width") * b_w +
        params:get("snapshot_c_delay_width") * c_w +
        params:get("snapshot_d_delay_width") * d_w

    target_values.eq_low_cut = params:get("snapshot_a_eq_low_cut") * a_w +
        params:get("snapshot_b_eq_low_cut") * b_w +
        params:get("snapshot_c_eq_low_cut") * c_w +
        params:get("snapshot_d_eq_low_cut") * d_w

    target_values.eq_high_cut = params:get("snapshot_a_eq_high_cut") * a_w +
        params:get("snapshot_b_eq_high_cut") * b_w +
        params:get("snapshot_c_eq_high_cut") * c_w +
        params:get("snapshot_d_eq_high_cut") * d_w

    target_values.eq_low_gain = params:get("snapshot_a_eq_low_gain") * a_w +
        params:get("snapshot_b_eq_low_gain") * b_w +
        params:get("snapshot_c_eq_low_gain") * c_w +
        params:get("snapshot_d_eq_low_gain") * d_w

    target_values.eq_mid_gain = params:get("snapshot_a_eq_mid_gain") * a_w +
        params:get("snapshot_b_eq_mid_gain") * b_w +
        params:get("snapshot_c_eq_mid_gain") * c_w +
        params:get("snapshot_d_eq_mid_gain") * d_w

    target_values.eq_high_gain = params:get("snapshot_a_eq_high_gain") * a_w +
        params:get("snapshot_b_eq_high_gain") * b_w +
        params:get("snapshot_c_eq_high_gain") * c_w +
        params:get("snapshot_d_eq_high_gain") * d_w

    -- Blend per-band parameters from params
    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)
        local decimate_id = string.format("band_%02d_decimate", i)

        target_values[level_id] = params:get(string.format("snapshot_a_%02d_level", i)) * a_w +
            params:get(string.format("snapshot_b_%02d_level", i)) * b_w +
            params:get(string.format("snapshot_c_%02d_level", i)) * c_w +
            params:get(string.format("snapshot_d_%02d_level", i)) * d_w

        target_values[pan_id] = params:get(string.format("snapshot_a_%02d_pan", i)) * a_w +
            params:get(string.format("snapshot_b_%02d_pan", i)) * b_w +
            params:get(string.format("snapshot_c_%02d_pan", i)) * c_w +
            params:get(string.format("snapshot_d_%02d_pan", i)) * d_w

        target_values[thresh_id] = params:get(string.format("snapshot_a_%02d_thresh", i)) * a_w +
            params:get(string.format("snapshot_b_%02d_thresh", i)) * b_w +
            params:get(string.format("snapshot_c_%02d_thresh", i)) * c_w +
            params:get(string.format("snapshot_d_%02d_thresh", i)) * d_w

        target_values[decimate_id] = params:get(string.format("snapshot_a_%02d_decimate", i)) * a_w +
            params:get(string.format("snapshot_b_%02d_decimate", i)) * b_w +
            params:get(string.format("snapshot_c_%02d_decimate", i)) * c_w +
            params:get(string.format("snapshot_d_%02d_decimate", i)) * d_w
    end

    -- Check if glide is enabled
    local glide_time_param = params:get("glide")
    if glide_time_param > 0 then
        if glide_state.is_gliding then
            -- INTERRUPTION CASE: Use current interpolated position and values as new start
            local current_time = util.time()
            local elapsed = current_time - glide_state.glide_time
            local progress = math.min(elapsed / glide_time_param, 1.0)

            -- Calculate current interpolated position



            local current_x = glide_state.start_pos.x +
                (glide_state.target_pos.x - glide_state.start_pos.x) * progress
            local current_y = glide_state.start_pos.y +
                (glide_state.target_pos.y - glide_state.start_pos.y) * progress

            -- Calculate current interpolated parameter values
            local current_values = {}
            current_values.q = glide_state.current_values.q +
                (glide_state.target_values.q - glide_state.current_values.q) * progress

            -- Interpolate input settings
            current_values.audio_in_level = glide_state.current_values.audio_in_level +
                (glide_state.target_values.audio_in_level - glide_state.current_values.audio_in_level) * progress
            current_values.noise_level = glide_state.current_values.noise_level +
                (glide_state.target_values.noise_level - glide_state.current_values.noise_level) * progress
            current_values.dust_level = glide_state.current_values.dust_level +
                (glide_state.target_values.dust_level - glide_state.current_values.dust_level) * progress
            current_values.noise_lfo_rate = glide_state.current_values.noise_lfo_rate +
                (glide_state.target_values.noise_lfo_rate - glide_state.current_values.noise_lfo_rate) * progress
            current_values.noise_lfo_depth = glide_state.current_values.noise_lfo_depth +
                (glide_state.target_values.noise_lfo_depth - glide_state.current_values.noise_lfo_depth) * progress
            current_values.dust_density = glide_state.current_values.dust_density +
                (glide_state.target_values.dust_density - glide_state.current_values.dust_density) * progress
            current_values.osc_level = glide_state.current_values.osc_level +
                (glide_state.target_values.osc_level - glide_state.current_values.osc_level) * progress
            current_values.osc_freq = glide_state.current_values.osc_freq +
                (glide_state.target_values.osc_freq - glide_state.current_values.osc_freq) * progress
            current_values.osc_timbre = glide_state.current_values.osc_timbre +
                (glide_state.target_values.osc_timbre - glide_state.current_values.osc_timbre) * progress
            current_values.osc_warp = glide_state.current_values.osc_warp +
                (glide_state.target_values.osc_warp - glide_state.current_values.osc_warp) * progress
            current_values.osc_mod_rate = glide_state.current_values.osc_mod_rate +
                (glide_state.target_values.osc_mod_rate - glide_state.current_values.osc_mod_rate) * progress
            current_values.osc_mod_depth = glide_state.current_values.osc_mod_depth +
                (glide_state.target_values.osc_mod_depth - glide_state.current_values.osc_mod_depth) * progress
            current_values.file_level = glide_state.current_values.file_level +
                (glide_state.target_values.file_level - glide_state.current_values.file_level) * progress
            current_values.file_speed = glide_state.current_values.file_speed +
                (glide_state.target_values.file_speed - glide_state.current_values.file_speed) * progress
            current_values.delay_time = glide_state.current_values.delay_time +
                (glide_state.target_values.delay_time - glide_state.current_values.delay_time) * progress
            current_values.delay_feedback = glide_state.current_values.delay_feedback +
                (glide_state.target_values.delay_feedback - glide_state.current_values.delay_feedback) * progress
            current_values.delay_mix = glide_state.current_values.delay_mix +
                (glide_state.target_values.delay_mix - glide_state.current_values.delay_mix) * progress
            current_values.delay_width = glide_state.current_values.delay_width +
                (glide_state.target_values.delay_width - glide_state.current_values.delay_width) * progress
            current_values.eq_low_cut = glide_state.current_values.eq_low_cut +
                (glide_state.target_values.eq_low_cut - glide_state.current_values.eq_low_cut) * progress
            current_values.eq_high_cut = glide_state.current_values.eq_high_cut +
                (glide_state.target_values.eq_high_cut - glide_state.current_values.eq_high_cut) * progress
            current_values.eq_low_gain = glide_state.current_values.eq_low_gain +
                (glide_state.target_values.eq_low_gain - glide_state.current_values.eq_low_gain) * progress
            current_values.eq_mid_gain = glide_state.current_values.eq_mid_gain +
                (glide_state.target_values.eq_mid_gain - glide_state.current_values.eq_mid_gain) * progress
            current_values.eq_high_gain = glide_state.current_values.eq_high_gain +
                (glide_state.target_values.eq_high_gain - glide_state.current_values.eq_high_gain) * progress

            for i = 1, #freqs do
                local level_id = string.format("band_%02d_level", i)
                local pan_id = string.format("band_%02d_pan", i)
                local thresh_id = string.format("band_%02d_thresh", i)
                local decimate_id = string.format("band_%02d_decimate", i)

                current_values[level_id] = glide_state.current_values[level_id] +
                    (glide_state.target_values[level_id] - glide_state.current_values[level_id]) * progress
                current_values[pan_id] = glide_state.current_values[pan_id] +
                    (glide_state.target_values[pan_id] - glide_state.current_values[pan_id]) * progress
                current_values[thresh_id] = glide_state.current_values[thresh_id] +
                    (glide_state.target_values[thresh_id] - glide_state.current_values[thresh_id]) * progress
                current_values[decimate_id] = glide_state.current_values[decimate_id] +
                    (glide_state.target_values[decimate_id] - glide_state.current_values[decimate_id]) * progress
            end


            -- Use current interpolated values as new starting point (ensure they're valid numbers)
            glide_state.start_pos.x = current_x or glide_state.start_pos.x
            glide_state.start_pos.y = current_y or glide_state.start_pos.y
            glide_state.current_values = current_values

            -- Validate that start_pos contains valid numbers
            if not glide_state.start_pos.x or glide_state.start_pos.x ~= glide_state.start_pos.x then
                glide_state.start_pos.x = grid_ui_state.current_matrix_pos.x
            end
            if not glide_state.start_pos.y or glide_state.start_pos.y ~= glide_state.start_pos.y then
                glide_state.start_pos.y = grid_ui_state.current_matrix_pos.y
            end

            -- Update last LED position for smooth visual transition (round to integers)
            glide_state.last_led_pos.x = math.floor(current_x + 0.5)
            glide_state.last_led_pos.y = math.floor(current_y + 0.5)
        else
            -- NORMAL CASE: Start new glide

            glide_state.start_pos.x = old_x or grid_ui_state.current_matrix_pos.x
            glide_state.start_pos.y = old_y or grid_ui_state.current_matrix_pos.y

            -- Store current parameter values as starting point
            glide_state.current_values = {}
            glide_state.current_values.q = params:get("q")
            glide_state.current_values.audio_in_level = params:get("audio_in_level")
            glide_state.current_values.noise_level = params:get("noise_level")
            glide_state.current_values.dust_level = params:get("dust_level")
            glide_state.current_values.noise_lfo_rate = params:get("noise_lfo_rate")
            glide_state.current_values.noise_lfo_depth = params:get("noise_lfo_depth")
            glide_state.current_values.dust_density = params:get("dust_density")
            glide_state.current_values.osc_level = params:get("osc_level")
            glide_state.current_values.osc_freq = params:get("osc_freq")
            glide_state.current_values.osc_timbre = params:get("osc_timbre")
            glide_state.current_values.osc_warp = params:get("osc_warp")
            glide_state.current_values.osc_mod_rate = params:get("osc_mod_rate")
            glide_state.current_values.osc_mod_depth = params:get("osc_mod_depth")
            glide_state.current_values.file_level = params:get("file_level")
            glide_state.current_values.file_speed = params:get("file_speed")
            glide_state.current_values.delay_time = params:get("delay_time")
            glide_state.current_values.delay_feedback = params:get("delay_feedback")
            glide_state.current_values.delay_mix = params:get("delay_mix")
            glide_state.current_values.delay_width = params:get("delay_width")
            glide_state.current_values.eq_low_cut = params:get("eq_low_cut")
            glide_state.current_values.eq_high_cut = params:get("eq_high_cut")
            glide_state.current_values.eq_low_gain = params:get("eq_low_gain")
            glide_state.current_values.eq_mid_gain = params:get("eq_mid_gain")
            glide_state.current_values.eq_high_gain = params:get("eq_high_gain")

            for i = 1, #freqs do
                local level_id = string.format("band_%02d_level", i)
                local pan_id = string.format("band_%02d_pan", i)
                local thresh_id = string.format("band_%02d_thresh", i)
                local decimate_id = string.format("band_%02d_decimate", i)

                glide_state.current_values[level_id] = params:get(level_id)
                glide_state.current_values[pan_id] = params:get(pan_id)
                glide_state.current_values[thresh_id] = params:get(thresh_id)
                glide_state.current_values[decimate_id] = params:get(decimate_id)
            end

            -- Initialize last LED position to start position
            glide_state.last_led_pos.x = glide_state.start_pos.x
            glide_state.last_led_pos.y = glide_state.start_pos.y
        end

        -- Set new target (common for both cases)
        glide_state.target_pos.x = x
        glide_state.target_pos.y = y
        glide_state.target_values = target_values
        glide_state.glide_time = util.time() -- Reset glide start time
        glide_state.is_gliding = true
    else
        -- Apply immediately to params (this will update the engine automatically)
        params:set("q", target_values.q)
        params:set("audio_in_level", target_values.audio_in_level)
        params:set("noise_level", target_values.noise_level)
        params:set("dust_level", target_values.dust_level)
        params:set("noise_lfo_rate", target_values.noise_lfo_rate)
        params:set("noise_lfo_depth", target_values.noise_lfo_depth)
        params:set("dust_density", target_values.dust_density)
        params:set("osc_level", target_values.osc_level)
        params:set("osc_freq", target_values.osc_freq)
        params:set("osc_timbre", target_values.osc_timbre)
        params:set("osc_warp", target_values.osc_warp)
        params:set("osc_mod_rate", target_values.osc_mod_rate)
        params:set("osc_mod_depth", target_values.osc_mod_depth)
        params:set("file_level", target_values.file_level)
        params:set("file_speed", target_values.file_speed)
        params:set("delay_time", target_values.delay_time)
        params:set("delay_feedback", target_values.delay_feedback)
        params:set("delay_mix", target_values.delay_mix)
        params:set("delay_width", target_values.delay_width)
        params:set("eq_low_cut", target_values.eq_low_cut)
        params:set("eq_high_cut", target_values.eq_high_cut)
        params:set("eq_low_gain", target_values.eq_low_gain)
        params:set("eq_mid_gain", target_values.eq_mid_gain)
        params:set("eq_high_gain", target_values.eq_high_gain)

        for i = 1, #freqs do
            local level_id = string.format("band_%02d_level", i)
            local pan_id = string.format("band_%02d_pan", i)
            local thresh_id = string.format("band_%02d_thresh", i)
            local decimate_id = string.format("band_%02d_decimate", i)

            params:set(level_id, target_values[level_id])
            params:set(pan_id, target_values[pan_id])
            params:set(thresh_id, target_values[thresh_id])
            params:set(decimate_id, target_values[decimate_id])
        end

        -- Only auto-save when at a snapshot corner (100% on one snapshot)
        -- This prevents blended values from overwriting snapshots
        local was_at_corner = is_at_snapshot_corner(old_x, old_y)
        local now_at_corner = is_at_snapshot_corner(x, y)

        if now_at_corner then
            -- Get which snapshot we're at based on position
            local current_snapshot = get_current_snapshot_from_position()

            -- Show banner when arriving at a corner
            if not was_at_corner then
                if params:get("info_banner") == 2 then
                    info_banner_mod.show("EDITING: " .. current_snapshot)
                end
            end

            store_snapshot(current_snapshot)
        elseif was_at_corner and not now_at_corner then
            -- Just left a corner, entering blend zone
            if params:get("info_banner") == 2 then
                info_banner_mod.show("BLEND MODE (NO SAVE)")
            end
        end
    end
end

-- Switch to a snapshot
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

-- Helper function to draw snapshot letters with blend weights
local function draw_snapshot_letters()
    -- Get blend weights from current matrix position
    local a_w, b_w, c_w, d_w = calculate_blend_weights(
        grid_ui_state.current_matrix_pos.x,
        grid_ui_state.current_matrix_pos.y
    )

    -- Position on right side of screen (stacked vertically)
    local MARGIN_RIGHT = 8
    local letter_x = 128 - MARGIN_RIGHT
    local letters = { "A", "B", "C", "D" }
    local weights = { a_w, b_w, c_w, d_w }
    local letter_spacing = 12
    local start_y = 20

    -- Draw each letter with brightness based on weight
    screen.font_face(1)
    screen.font_size(8)
    for i = 1, 4 do
        local brightness = math.floor(weights[i] * 15)
        screen.level(brightness)
        screen.move(letter_x, start_y + (i - 1) * letter_spacing)
        screen.text(letters[i])
    end
end

-- screen redraw
function redraw()
    screen.clear()
    screen.level(15)

    -- Consistent layout constants
    local MARGIN_LEFT = 9
    local MARGIN_TOP = 9
    local LABEL_Y = 20
    local VALUE_Y = 42
    local DOT_Y = 58

    -- Mode-specific screens
    if norns_mode == 0 then
        -- Inputs mode - Centered layout with symbols
        local input_symbols = { "I", "~", ".", "*", ">" } -- input, osc, dust, noise, file
        local content_x = 64                              -- Center x for content

        -- Draw input type selector at top
        screen.font_face(1)
        screen.font_size(8)

        -- Evenly space symbols across the screen
        local margin = 10
        local available_width = 128 - (margin * 2)
        local item_spacing = available_width / 5

        -- Draw each symbol
        for i = 1, 5 do
            local x_pos = margin + (i - 0.5) * item_spacing
            local brightness = (input_mode_state.selected_input == i) and 15 or 4
            screen.level(brightness)
            screen.move(x_pos, 8)
            screen.text_center(input_symbols[i])
        end

        -- Draw parameter values (centered)
        if input_mode_state.selected_input == 1 then
            -- Input audio
            local audio_level = params:get("audio_in_level")

            screen.font_face(1)
            screen.font_size(8)
            screen.level(8)
            screen.move(content_x, 28)
            screen.text_center("LEVEL")

            screen.font_face(1)
            screen.font_size(16)
            screen.level(15)
            screen.move(content_x, 45)
            screen.text_center(string.format("%.2f", audio_level))

            -- Parameter indicator (1 of 1)
            screen.level(15)
            screen.circle(content_x, 54, 1.5)
            screen.fill()
        elseif input_mode_state.selected_input == 2 then
            -- Oscillator
            local osc_level = params:get("osc_level")
            local osc_freq = params:get("osc_freq")
            local osc_timbre = params:get("osc_timbre")
            local osc_warp = params:get("osc_warp")
            local osc_mod_rate = params:get("osc_mod_rate")

            local param_names = { "LEVEL", "FREQ", "TIMBRE", "MORPH", "MOD RATE" }
            local param_values = {
                string.format("%.2f", osc_level),
                string.format("%.1f Hz", osc_freq),
                string.format("%.2f", osc_timbre),
                string.format("%.2f", osc_warp),
                string.format("%.1f Hz", osc_mod_rate)
            }

            -- Display current parameter name
            screen.font_face(1)
            screen.font_size(8)
            screen.level(8)
            screen.move(content_x, 28)
            screen.text_center(param_names[input_mode_state.selected_param])

            -- Display current value
            screen.font_face(1)
            screen.font_size(16)
            screen.level(15)
            screen.move(content_x, 45)
            screen.text_center(param_values[input_mode_state.selected_param])

            -- Parameter indicator (5 dots, current one bright, centered)
            local dot_spacing = 6
            local dots_width = 5 * dot_spacing - dot_spacing
            local dot_start_x = (128 - dots_width) / 2
            for i = 1, 5 do
                local brightness = (i == input_mode_state.selected_param) and 15 or 4
                screen.level(brightness)
                screen.circle(dot_start_x + (i - 1) * dot_spacing, 54, 1.5)
                screen.fill()
            end
        elseif input_mode_state.selected_input == 3 then
            -- Dust
            local dust_level = params:get("dust_level")
            local dust_density = params:get("dust_density")

            local param_names = { "LEVEL", "DENSITY" }
            local param_values = {
                string.format("%.2f", dust_level),
                string.format("%d Hz", dust_density)
            }

            -- Display current parameter name
            screen.font_face(1)
            screen.font_size(8)
            screen.level(8)
            screen.move(content_x, 28)
            screen.text_center(param_names[input_mode_state.selected_param])

            -- Display current value
            screen.font_face(1)
            screen.font_size(16)
            screen.level(15)
            screen.move(content_x, 45)
            screen.text_center(param_values[input_mode_state.selected_param])

            -- Parameter indicator (2 dots, current one bright, centered)
            local dot_spacing = 6
            local dots_width = 2 * dot_spacing - dot_spacing
            local dot_start_x = (128 - dots_width) / 2
            for i = 1, 2 do
                local brightness = (i == input_mode_state.selected_param) and 15 or 4
                screen.level(brightness)
                screen.circle(dot_start_x + (i - 1) * dot_spacing, 54, 1.5)
                screen.fill()
            end
        elseif input_mode_state.selected_input == 4 then
            -- Noise
            local noise_level = params:get("noise_level")
            local noise_lfo_rate = params:get("noise_lfo_rate")
            local noise_lfo_depth = params:get("noise_lfo_depth")

            local param_names = { "LEVEL", "LFO RATE", "LFO DEPTH" }
            local param_values = {
                string.format("%.2f", noise_level),
                string.format("%.1f Hz", noise_lfo_rate),
                string.format("%.0f%%", noise_lfo_depth * 100)
            }

            -- Display current parameter name
            screen.font_face(1)
            screen.font_size(8)
            screen.level(8)
            screen.move(content_x, 28)
            screen.text_center(param_names[input_mode_state.selected_param])

            -- Display current value
            screen.font_face(1)
            screen.font_size(16)
            screen.level(15)
            screen.move(content_x, 45)
            screen.text_center(param_values[input_mode_state.selected_param])

            -- Parameter indicator (3 dots, current one bright, centered)
            local dot_spacing = 6
            local dots_width = 3 * dot_spacing - dot_spacing
            local dot_start_x = (128 - dots_width) / 2
            for i = 1, 3 do
                local brightness = (i == input_mode_state.selected_param) and 15 or 4
                screen.level(brightness)
                screen.circle(dot_start_x + (i - 1) * dot_spacing, 54, 1.5)
                screen.fill()
            end
        elseif input_mode_state.selected_input == 5 then
            -- File playback
            local file_level = params:get("file_level")
            local file_speed = params:get("file_speed")
            local file_gate = params:get("file_gate")

            local param_names = { "LEVEL", "SPEED", "PLAY", "SELECT" }
            local param_values = {
                string.format("%.2f", file_level),
                string.format("%.2f", file_speed),
                file_gate == 1 and "ON" or "OFF",
                "..."
            }

            -- Display current parameter name
            screen.font_face(1)
            screen.font_size(8)
            screen.level(8)
            screen.move(content_x, 28)
            screen.text_center(param_names[input_mode_state.selected_param])

            -- Display current value
            screen.font_face(1)
            screen.font_size(16)
            screen.level(15)
            screen.move(content_x, 45)
            screen.text_center(param_values[input_mode_state.selected_param])

            -- Parameter indicator (4 dots, current one bright, centered)
            local dot_spacing = 6
            local dots_width = 4 * dot_spacing - dot_spacing
            local dot_start_x = (128 - dots_width) / 2
            for i = 1, 4 do
                local brightness = (i == input_mode_state.selected_param) and 15 or 4
                screen.level(brightness)
                screen.circle(dot_start_x + (i - 1) * dot_spacing, 54, 1.5)
                screen.fill()
            end
        end

        -- Draw snapshot letters
        draw_snapshot_letters()
    elseif norns_mode == 1 then
        -- Levels screen - Visual meters
        local num_bands = math.min(16, #freqs)
        local meter_width = 3
        local meter_spacing = 5
        local total_width = num_bands * meter_spacing - (meter_spacing - meter_width)
        local start_x = (128 - total_width) / 2
        local meter_height = 48
        local meter_y = (64 - meter_height) / 2

        for i = 1, num_bands do
            local x = start_x + (i - 1) * meter_spacing
            local meter_v = band_meters[i] or 0
            local level_db = params:get(string.format("band_%02d_level", i))

            -- Convert level to meter height
            local level_height = math.max(0, (level_db + 60) * meter_height / 72) -- -60dB to +12dB range

            -- Convert audio meter value to dB, then to height
            local meter_db = 0
            if meter_v > 0 then
                meter_db = 20 * math.log10(meter_v) -- Convert linear to dB
            else
                meter_db = -60                      -- Silent
            end
            local peak_height = math.max(0, (meter_db + 60) * meter_height / 72)

            -- Draw meter background (dark)
            screen.level(2)
            screen.rect(x, meter_y, meter_width, meter_height)
            screen.fill()

            -- Draw level indicator (green) - always show this
            screen.level(8)
            screen.rect(x, meter_y + meter_height - level_height, meter_width, level_height)
            screen.fill()

            -- Draw meter peak (bright) - show even if no audio
            screen.level(15)
            if peak_height > 0 then
                screen.rect(x, meter_y + meter_height - peak_height, meter_width, peak_height)
                screen.fill()
            else
                -- Show a small indicator even when no audio
                screen.rect(x, meter_y + meter_height - 2, meter_width, 2)
                screen.fill()
            end
        end

        -- Draw cursor below selected band
        if selected_band >= 1 and selected_band <= num_bands then
            local cursor_x = start_x + (selected_band - 1) * meter_spacing
            screen.level(15)
            screen.rect(cursor_x, meter_y + meter_height + 3, meter_width, 2)
            screen.fill()
        end

        -- Draw snapshot letters
        draw_snapshot_letters()
    elseif norns_mode == 2 then
        -- Pans screen - Visual pan indicators
        local num_bands = math.min(16, #freqs)
        local indicator_width = 3
        local indicator_spacing = 5
        local total_width = num_bands * indicator_spacing - (indicator_spacing - indicator_width)
        local start_x = (128 - total_width) / 2
        local indicator_height = 48
        local indicator_y = (64 - indicator_height) / 2

        for i = 1, num_bands do
            local x = start_x + (i - 1) * indicator_spacing
            local pan = params:get(string.format("band_%02d_pan", i))

            -- Convert pan (-1 to 1) to position (0 to indicator_height)
            -- Invert so left pan (-1) is at top, right pan (+1) is at bottom
            local pan_position = (1 - pan) * indicator_height / 2
            pan_position = math.max(0, math.min(indicator_height, pan_position))

            -- Draw background line
            screen.level(2)
            screen.rect(x, indicator_y, indicator_width, indicator_height)
            screen.fill()

            -- Draw center line
            screen.level(4)
            screen.rect(x, indicator_y + indicator_height / 2 - 1, indicator_width, 2)
            screen.fill()

            -- Draw pan indicator
            screen.level(15)
            screen.rect(x, indicator_y + indicator_height - pan_position - 2, indicator_width, 4)
            screen.fill()
        end

        -- Draw cursor below selected band
        if selected_band >= 1 and selected_band <= num_bands then
            local cursor_x = start_x + (selected_band - 1) * indicator_spacing
            screen.level(15)
            screen.rect(cursor_x, indicator_y + indicator_height + 3, indicator_width, 2)
            screen.fill()
        end

        -- Draw snapshot letters
        draw_snapshot_letters()
    elseif norns_mode == 3 then
        -- Thresholds screen - Visual threshold indicators
        local num_bands = math.min(16, #freqs)
        local indicator_width = 3
        local indicator_spacing = 5
        local total_width = num_bands * indicator_spacing - (indicator_spacing - indicator_width)
        local start_x = (128 - total_width) / 2
        local indicator_height = 48
        local indicator_y = (64 - indicator_height) / 2

        for i = 1, num_bands do
            local x = start_x + (i - 1) * indicator_spacing
            local thresh = params:get(string.format("band_%02d_thresh", i))

            -- Convert threshold (0.0 to 0.2) to position (0 to indicator_height)
            -- Higher thresholds appear higher on screen
            local thresh_position = (thresh / 0.2) * indicator_height
            thresh_position = math.max(0, math.min(indicator_height, thresh_position))

            -- Draw background line
            screen.level(2)
            screen.rect(x, indicator_y, indicator_width, indicator_height)
            screen.fill()

            -- Draw threshold indicator
            screen.level(15)
            screen.rect(x, indicator_y + thresh_position - 2, indicator_width, 4)
            screen.fill()
        end

        -- Draw cursor below selected band
        if selected_band >= 1 and selected_band <= num_bands then
            local cursor_x = start_x + (selected_band - 1) * indicator_spacing
            screen.level(15)
            screen.rect(cursor_x, indicator_y + indicator_height + 3, indicator_width, 2)
            screen.fill()
        end

        -- Draw snapshot letters
        draw_snapshot_letters()
    elseif norns_mode == 4 then
        -- Decimate screen - Visual decimate rate indicators
        local num_bands = math.min(16, #freqs)
        local indicator_width = 3
        local indicator_spacing = 5
        local total_width = num_bands * indicator_spacing - (indicator_spacing - indicator_width)
        local start_x = (128 - total_width) / 2
        local indicator_height = 48
        local indicator_y = (64 - indicator_height) / 2

        for i = 1, num_bands do
            local x = start_x + (i - 1) * indicator_spacing
            local rate = params:get(string.format("band_%02d_decimate", i))

            -- Convert rate (100 to 48000 Hz) to position using exponential scale
            -- Lower rates (more decimation) appear lower on screen
            local normalized = -math.log(rate / 48000) / 6.2 -- 0 (48k) to 1 (100)
            local decimate_position = normalized * indicator_height
            decimate_position = math.max(0, math.min(indicator_height, decimate_position))

            -- Draw background line
            screen.level(2)
            screen.rect(x, indicator_y, indicator_width, indicator_height)
            screen.fill()

            -- Draw decimate indicator
            screen.level(15)
            screen.rect(x, indicator_y + decimate_position - 2, indicator_width, 4)
            screen.fill()
        end

        -- Draw cursor below selected band
        if selected_band >= 1 and selected_band <= num_bands then
            local cursor_x = start_x + (selected_band - 1) * indicator_spacing
            screen.level(15)
            screen.rect(cursor_x, indicator_y + indicator_height + 3, indicator_width, 2)
            screen.fill()
        end

        -- Draw snapshot letters
        draw_snapshot_letters()
    elseif norns_mode == 6 then
        -- Matrix screen - Visual matrix display (spacious, centered)
        local matrix_size = 14
        local cell_size = 4
        local matrix_width = matrix_size * cell_size
        local start_x = (128 - matrix_width) / 2
        local start_y = (64 - matrix_width) / 2

        -- Draw matrix grid
        for x = 1, matrix_size do
            for y = 1, matrix_size do
                local cell_x = start_x + (x - 1) * cell_size
                local cell_y = start_y + (y - 1) * cell_size

                -- Current position indicator
                if x == grid_ui_state.current_matrix_pos.x and y == grid_ui_state.current_matrix_pos.y then
                    screen.level(15) -- Bright white for current position
                else
                    screen.level(2)  -- Dark for other positions
                end

                screen.rect(cell_x, cell_y, cell_size - 1, cell_size - 1)
                screen.fill()
            end
        end

        -- Draw path points if in path mode
        if path_state.mode and #path_state.points > 0 then
            screen.level(8) -- Medium brightness for path points
            for i, point in ipairs(path_state.points) do
                local cell_x = start_x + (point.x - 1) * cell_size
                local cell_y = start_y + (point.y - 1) * cell_size
                screen.rect(cell_x, cell_y, cell_size - 1, cell_size - 1)
                screen.fill()
            end
        end

        -- Draw glide animation if active
        if glide_state.is_gliding then
            -- Calculate current glide position with sub-pixel interpolation
            local current_time = util.time()
            local elapsed = current_time - glide_state.glide_time
            local glide_time = params:get("glide")
            local progress = math.min(1, elapsed / glide_time)

            -- Interpolate between start and target positions
            local current_x = glide_state.start_pos.x + (glide_state.target_pos.x - glide_state.start_pos.x) * progress
            local current_y = glide_state.start_pos.y + (glide_state.target_pos.y - glide_state.start_pos.y) * progress

            -- Draw current glide position
            local glide_x = start_x + (current_x - 1) * cell_size
            local glide_y = start_y + (current_y - 1) * cell_size

            -- Bright pulsing effect for glide position
            local pulse = math.sin(util.time() * 10) * 0.5 + 0.5 -- 0 to 1 pulse
            screen.level(8 + math.floor(pulse * 7))              -- 8 to 15 brightness
            screen.rect(glide_x, glide_y, cell_size - 1, cell_size - 1)
            screen.fill()

            -- Draw target position
            if glide_state.target_pos then
                local target_x = start_x + (glide_state.target_pos.x - 1) * cell_size
                local target_y = start_y + (glide_state.target_pos.y - 1) * cell_size
                screen.level(12) -- Medium brightness for target
                screen.rect(target_x, target_y, cell_size - 1, cell_size - 1)
                screen.fill()
            end
        end

        -- Draw selected position indicator (if different from current)
        if selected_matrix_pos.x ~= grid_ui_state.current_matrix_pos.x or
            selected_matrix_pos.y ~= grid_ui_state.current_matrix_pos.y then
            local sel_x = start_x + (selected_matrix_pos.x - 1) * cell_size
            local sel_y = start_y + (selected_matrix_pos.y - 1) * cell_size
            screen.level(8) -- Medium brightness for selected position
            -- Draw a frame around the selected position
            screen.rect(sel_x, sel_y, cell_size - 1, cell_size - 1)
            screen.stroke()
        end

        -- Draw snapshot letters
        draw_snapshot_letters()
    elseif norns_mode == 5 then
        -- Effects screen - Centered layout with symbols
        local effect_symbols = { "|..", "=-=" } -- delay (echo), eq (bands)
        local content_x = 64

        -- Draw effect type selector at top
        screen.font_face(1)
        screen.font_size(8)

        -- Evenly space symbols across the screen
        local spacing = 128 / 3
        local positions = { spacing * 1, spacing * 2 }

        -- Draw each symbol
        for i = 1, 2 do
            local brightness = (effects_mode_state.selected_effect == i) and 15 or 4
            screen.level(brightness)
            screen.move(positions[i], 8)
            screen.text_center(effect_symbols[i])
        end

        -- Draw parameter values based on selected effect
        if effects_mode_state.selected_effect == 1 then
            -- Delay parameters
            local delay_time = params:get("delay_time")
            local delay_feedback = params:get("delay_feedback")
            local delay_mix = params:get("delay_mix")
            local delay_width = params:get("delay_width")

            local param_names = { "TIME", "FEEDBACK", "MIX", "WIDTH" }
            local param_values = {
                string.format("%.2fs", delay_time),
                string.format("%.2f", delay_feedback),
                string.format("%.2f", delay_mix),
                string.format("%.2f", delay_width)
            }

            -- Display current parameter name
            screen.font_face(1)
            screen.font_size(8)
            screen.level(8)
            screen.move(content_x, 30)
            screen.text_center(param_names[effects_mode_state.selected_param])

            -- Display current value
            screen.font_face(1)
            screen.font_size(16)
            screen.level(15)
            screen.move(content_x, 46)
            screen.text_center(param_values[effects_mode_state.selected_param])

            -- Parameter indicator (4 dots, current one bright, centered)
            local dot_spacing = 6
            local dots_width = 4 * dot_spacing - dot_spacing
            local dot_start_x = (128 - dots_width) / 2
            for i = 1, 4 do
                local brightness = (i == effects_mode_state.selected_param) and 15 or 4
                screen.level(brightness)
                screen.circle(dot_start_x + (i - 1) * dot_spacing, 56, 1.5)
                screen.fill()
            end
        elseif effects_mode_state.selected_effect == 2 then
            -- EQ parameters
            local eq_low_cut = params:get("eq_low_cut")
            local eq_high_cut = params:get("eq_high_cut")
            local eq_low_gain = params:get("eq_low_gain")
            local eq_mid_gain = params:get("eq_mid_gain")
            local eq_high_gain = params:get("eq_high_gain")

            local param_names = { "LOW CUT", "HIGH CUT", "LOW", "MID", "HIGH" }
            local param_values = {
                string.format("%.0f Hz", eq_low_cut),
                string.format("%.0f Hz", eq_high_cut),
                string.format("%.1f dB", eq_low_gain),
                string.format("%.1f dB", eq_mid_gain),
                string.format("%.1f dB", eq_high_gain)
            }

            -- Display current parameter name
            screen.font_face(1)
            screen.font_size(8)
            screen.level(8)
            screen.move(content_x, 30)
            screen.text_center(param_names[effects_mode_state.selected_param])

            -- Display current value
            screen.font_face(1)
            screen.font_size(16)
            screen.level(15)
            screen.move(content_x, 46)
            screen.text_center(param_values[effects_mode_state.selected_param])

            -- Parameter indicator (5 dots, current one bright, centered)
            local dot_spacing = 6
            local dots_width = 5 * dot_spacing - dot_spacing
            local dot_start_x = (128 - dots_width) / 2
            for i = 1, 5 do
                local brightness = (i == effects_mode_state.selected_param) and 15 or 4
                screen.level(brightness)
                screen.circle(dot_start_x + (i - 1) * dot_spacing, 56, 1.5)
                screen.fill()
            end
        end

        -- Draw snapshot letters
        draw_snapshot_letters()
    end

    -- Draw screen indicators on the left side (7 modes total)
    screen_indicators.draw_screen_indicator(7, norns_mode + 1)

    -- Draw info banner on top of everything
    info_banner_mod.draw()

    screen.update()
end

-- cleanup
function cleanup()
    meters_mod.cleanup(band_meter_polls)
    if metro_grid_refresh then
        metro_grid_refresh:stop()
        metro_grid_refresh = nil
    end
    if metro_glide then
        metro_glide:stop()
        metro_glide = nil
    end
    if metro_screen_refresh then
        metro_screen_refresh:stop()
        metro_screen_refresh = nil
    end
    if path_state.playback_metro then
        path_state.playback_metro:stop()
        path_state.playback_metro = nil
    end
end

-- key/enc handlers
function key(n, z)
    if n == 1 then
        -- Key 1: Shift functionality
        grid_ui_state.shift_held = (z == 1)
        -- Update grid shift LED
        if grid_device then
            grid_device:led(16, 8, grid_ui_state.shift_held and 15 or 0)
            grid_device:refresh()
        end
    elseif z == 1 then -- Key press (not release)
        if n == 2 then
            -- Key 2: Copy snapshot (with shift) or context-dependent action
            if grid_ui_state.shift_held then
                copy_snapshot()
            elseif norns_mode == 0 then
                -- Inputs mode: Previous input type
                input_mode_state.selected_input = util.clamp(input_mode_state.selected_input - 1, 1, 5)
                input_mode_state.selected_param = 1 -- Reset param selection
                -- Show input name in banner
                local input_names = { "INPUT", "OSCILLATOR", "DUST", "NOISE", "FILE" }
                if params:get("info_banner") == 2 then
                    info_banner_mod.show(input_names[input_mode_state.selected_input])
                end
            elseif norns_mode == 5 then
                -- Effects mode: Previous effect type
                effects_mode_state.selected_effect = util.clamp(effects_mode_state.selected_effect - 1, 1, 2)
                effects_mode_state.selected_param = 1 -- Reset param selection
                -- Show effect name in banner
                local effect_names = { "DELAY", "EQ" }
                if params:get("info_banner") == 2 then
                    info_banner_mod.show(effect_names[effects_mode_state.selected_effect])
                end
            elseif norns_mode == 6 then
                -- Matrix mode: Go to selected position
                local old_x = grid_ui_state.current_matrix_pos.x
                local old_y = grid_ui_state.current_matrix_pos.y
                apply_blend(selected_matrix_pos.x, selected_matrix_pos.y, old_x, old_y)
                if params:get("info_banner") == 2 then
                    info_banner_mod.show(string.format("POSITION %d,%d", selected_matrix_pos.x, selected_matrix_pos.y))
                end
            elseif norns_mode >= 1 and norns_mode <= 4 then
                -- Band modes: Reset functions (require being at corner)
                local at_corner = is_at_snapshot_corner(grid_ui_state.current_matrix_pos.x,
                    grid_ui_state.current_matrix_pos.y)
                if not at_corner then
                    if params:get("info_banner") == 2 then
                        info_banner_mod.show("MOVE TO CORNER TO EDIT")
                    end
                    return
                end

                if norns_mode == 1 then
                    -- Reset levels to -12dB
                    for i = 1, #freqs do
                        params:set(string.format("band_%02d_level", i), -12)
                    end
                    store_snapshot(get_current_snapshot_from_position())
                elseif norns_mode == 2 then
                    -- Reset pans to center (0)
                    for i = 1, #freqs do
                        params:set(string.format("band_%02d_pan", i), 0)
                    end
                    store_snapshot(get_current_snapshot_from_position())
                elseif norns_mode == 3 then
                    -- Reset thresholds to 0.0 (all audio passes through)
                    for i = 1, #freqs do
                        params:set(string.format("band_%02d_thresh", i), 0.0)
                    end
                    store_snapshot(get_current_snapshot_from_position())
                elseif norns_mode == 4 then
                    -- Reset decimate to 48000 Hz (no decimation)
                    for i = 1, #freqs do
                        params:set(string.format("band_%02d_decimate", i), 48000)
                    end
                    store_snapshot(get_current_snapshot_from_position())
                end
            end
        elseif n == 3 then
            -- Key 3: Paste snapshot (with shift) or context-dependent action
            if grid_ui_state.shift_held then
                paste_snapshot()
            elseif norns_mode == 0 then
                -- Inputs mode: Next input type
                input_mode_state.selected_input = util.clamp(input_mode_state.selected_input + 1, 1, 5)
                input_mode_state.selected_param = 1 -- Reset param selection
                -- Show input name in banner
                local input_names = { "INPUT", "OSCILLATOR", "DUST", "NOISE", "FILE" }
                if params:get("info_banner") == 2 then
                    info_banner_mod.show(input_names[input_mode_state.selected_input])
                end
            elseif norns_mode == 5 then
                -- Effects mode: Next effect type
                effects_mode_state.selected_effect = util.clamp(effects_mode_state.selected_effect + 1, 1, 2)
                effects_mode_state.selected_param = 1 -- Reset param selection
                -- Show effect name in banner
                local effect_names = { "DELAY", "EQ" }
                if params:get("info_banner") == 2 then
                    info_banner_mod.show(effect_names[effects_mode_state.selected_effect])
                end
            elseif norns_mode == 6 then
                -- Matrix mode: Set selector to random position
                selected_matrix_pos.x = math.random(1, 14)
                selected_matrix_pos.y = math.random(1, 14)
            elseif norns_mode >= 1 and norns_mode <= 4 then
                -- Band modes: Randomize functions (require being at corner)
                local at_corner = is_at_snapshot_corner(grid_ui_state.current_matrix_pos.x,
                    grid_ui_state.current_matrix_pos.y)
                if not at_corner then
                    if params:get("info_banner") == 2 then
                        info_banner_mod.show("MOVE TO CORNER TO EDIT")
                    end
                    return
                end

                if norns_mode == 1 then
                    -- Randomize levels (-60dB to +12dB)
                    for i = 1, #freqs do
                        local random_level = math.random(-60, 12)
                        params:set(string.format("band_%02d_level", i), random_level)
                    end
                    store_snapshot(get_current_snapshot_from_position())
                elseif norns_mode == 2 then
                    -- Randomize pans (-1 to +1)
                    for i = 1, #freqs do
                        local random_pan = (math.random() - 0.5) * 2
                        params:set(string.format("band_%02d_pan", i), random_pan)
                    end
                    store_snapshot(get_current_snapshot_from_position())
                elseif norns_mode == 3 then
                    -- Randomize thresholds (0.0 to 0.2)
                    for i = 1, #freqs do
                        local random_thresh = math.random() * 0.2 -- Returns value between 0.0 and 0.2
                        params:set(string.format("band_%02d_thresh", i), random_thresh)
                    end
                    store_snapshot(get_current_snapshot_from_position())
                elseif norns_mode == 4 then
                    -- Randomize decimate rates (100 to 48000 Hz)
                    for i = 1, #freqs do
                        -- Random exponential value
                        local random_normalized = math.random()
                        local random_rate = math.floor(48000 * math.exp(-random_normalized * 6.2))
                        params:set(string.format("band_%02d_decimate", i), random_rate)
                    end
                    store_snapshot(get_current_snapshot_from_position())
                end
            end
        end
    end
end

function enc(n, d)
    if n == 1 then
        if grid_ui_state.shift_held then
            -- Shift + Encoder 1: Switch snapshots
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
            if new_index < 1 then new_index = 4 end
            if new_index > 4 then new_index = 1 end

            switch_to_snapshot(snapshots_list[new_index])

            -- Show snapshot change banner
            if params:get("info_banner") == 2 then
                info_banner_mod.show("SNAPSHOT " .. snapshots_list[new_index])
            end
        else
            -- Encoder 1: Switch between all 7 modes on Norns screen (independent from grid)
            norns_mode = util.clamp(norns_mode + d, 0, 6)

            -- Show mode change banner
            if params:get("info_banner") == 2 then
                local mode_name = mode_names[norns_mode + 1] or "unknown"
                info_banner_mod.show(mode_name)
            end
        end
    elseif n == 2 then
        if norns_mode == 0 then
            -- Inputs mode: Select parameter within current input type
            local max_params = 1 -- Default for Live (only 1 param)
            local param_names = {}

            if input_mode_state.selected_input == 1 then
                max_params = 1
                param_names = { "LEVEL" }
            elseif input_mode_state.selected_input == 2 then
                max_params = 5
                param_names = { "LEVEL", "FREQ", "TIMBRE", "MORPH", "MOD RATE" }
            elseif input_mode_state.selected_input == 3 then
                max_params = 2
                param_names = { "LEVEL", "DENSITY" }
            elseif input_mode_state.selected_input == 4 then
                max_params = 3
                param_names = { "LEVEL", "LFO RATE", "LFO DEPTH" }
            elseif input_mode_state.selected_input == 5 then
                max_params = 4
                param_names = { "LEVEL", "SPEED", "PLAY", "SELECT" }
            end

            input_mode_state.selected_param = util.clamp(input_mode_state.selected_param + d, 1, max_params)
        elseif norns_mode == 5 then
            -- Effects mode: Select parameter within current effect type
            local max_params = (effects_mode_state.selected_effect == 1) and 4 or 5
            effects_mode_state.selected_param = util.clamp(effects_mode_state.selected_param + d, 1, max_params)
        elseif norns_mode == 6 then
            -- Matrix mode: Navigate X position
            selected_matrix_pos.x = selected_matrix_pos.x + d
            selected_matrix_pos.x = math.max(1, math.min(14, selected_matrix_pos.x))
        elseif norns_mode >= 1 and norns_mode <= 4 then
            -- Other modes: Select band
            selected_band = selected_band + d
            -- Clamp to bounds: 1-16
            selected_band = math.max(1, math.min(#freqs, selected_band))
        end
    elseif n == 3 then
        -- Allow Enc 3 freely on matrix screen; otherwise enforce corner-only edits
        if norns_mode ~= 6 then
            -- Check if we're at a snapshot corner before allowing edits
            local at_corner = is_at_snapshot_corner(grid_ui_state.current_matrix_pos.x,
                grid_ui_state.current_matrix_pos.y)

            if not at_corner then
                -- Not at a corner - show warning and block edits
                if params:get("info_banner") == 2 then
                    info_banner_mod.show("MOVE TO CORNER TO EDIT")
                end
                return
            end
        end

        if norns_mode == 0 then
            -- Inputs mode: Adjust selected parameter (E3)
            if input_mode_state.selected_input == 1 then
                -- Live: Audio In Level
                local current = params:get("audio_in_level")
                local new_val = util.clamp(current + d * 0.01, 0, 1)
                params:set("audio_in_level", new_val)
                store_snapshot(get_current_snapshot_from_position())
            elseif input_mode_state.selected_input == 2 then
                -- Osc: Adjust selected parameter
                if input_mode_state.selected_param == 1 then
                    local current = params:get("osc_level")
                    local new_val = util.clamp(current + d * 0.01, 0, 1)
                    params:set("osc_level", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif input_mode_state.selected_param == 2 then
                    local current = params:get("osc_freq")
                    local new_val = util.clamp(current * math.exp(d * 0.05), 0.1, 2000)
                    params:set("osc_freq", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif input_mode_state.selected_param == 3 then
                    local current = params:get("osc_timbre")
                    local new_val = util.clamp(current + d * 0.01, 0, 1)
                    params:set("osc_timbre", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif input_mode_state.selected_param == 4 then
                    local current = params:get("osc_warp")
                    local new_val = util.clamp(current + d * 0.01, 0, 1)
                    params:set("osc_warp", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif input_mode_state.selected_param == 5 then
                    local current = params:get("osc_mod_rate")
                    local new_val = util.clamp(current * math.exp(d * 0.05), 0.1, 100)
                    params:set("osc_mod_rate", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                end
            elseif input_mode_state.selected_input == 3 then
                -- Dust: Adjust selected parameter
                if input_mode_state.selected_param == 1 then
                    local current = params:get("dust_level")
                    local new_val = util.clamp(current + d * 0.01, 0, 1)
                    params:set("dust_level", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif input_mode_state.selected_param == 2 then
                    local current = params:get("dust_density")
                    local new_val = util.clamp(current + d * 10, 1, 1000)
                    params:set("dust_density", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                end
            elseif input_mode_state.selected_input == 4 then
                -- Noise: Adjust selected parameter
                if input_mode_state.selected_param == 1 then
                    local current = params:get("noise_level")
                    local new_val = util.clamp(current + d * 0.01, 0, 1)
                    params:set("noise_level", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif input_mode_state.selected_param == 2 then
                    local current = params:get("noise_lfo_rate")
                    local new_val = util.clamp(current + d * 0.5, 0, 20)
                    params:set("noise_lfo_rate", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif input_mode_state.selected_param == 3 then
                    local current = params:get("noise_lfo_depth")
                    local new_val = util.clamp(current + d * 0.01, 0, 1)
                    params:set("noise_lfo_depth", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                end
            elseif input_mode_state.selected_input == 5 then
                -- File: Adjust selected parameter via Enc 3
                if input_mode_state.selected_param == 1 then
                    -- Level
                    local current = params:get("file_level")
                    local new_val = util.clamp(current + d * 0.01, 0, 1)
                    params:set("file_level", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif input_mode_state.selected_param == 2 then
                    -- Speed
                    local current = params:get("file_speed")
                    local new_val = util.clamp(current + d * 0.1, -4, 4)
                    params:set("file_speed", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif input_mode_state.selected_param == 3 then
                    -- Play/Stop (toggle on any encoder turn)
                    if d ~= 0 then
                        local current = params:get("file_gate")
                        params:set("file_gate", 1 - current)
                        if params:get("info_banner") == 2 then
                            info_banner_mod.show(current == 0 and "FILE PLAY" or "FILE STOP")
                        end
                    end
                elseif input_mode_state.selected_param == 4 then
                    -- Select file (open file browser on any encoder turn)
                    if d ~= 0 then
                        _menu.fileselect(params:lookup_param("file_path"))
                    end
                end
            end
        elseif norns_mode == 5 then
            -- Effects mode: Adjust selected effect parameter
            if effects_mode_state.selected_effect == 1 then
                -- Delay effect
                if effects_mode_state.selected_param == 1 then
                    -- Delay Time (exponential)
                    local current = params:get("delay_time")
                    local new_val = math.max(0.01, math.min(2.0, current * math.exp(d * 0.05)))
                    params:set("delay_time", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif effects_mode_state.selected_param == 2 then
                    -- Delay Feedback
                    local current = params:get("delay_feedback")
                    local new_val = util.clamp(current + d * 0.01, 0, 1.2) -- Allow up to 1.2 for extreme feedback
                    params:set("delay_feedback", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif effects_mode_state.selected_param == 3 then
                    -- Delay Mix
                    local current = params:get("delay_mix")
                    local new_val = util.clamp(current + d * 0.01, 0, 1)
                    params:set("delay_mix", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif effects_mode_state.selected_param == 4 then
                    -- Delay Width
                    local current = params:get("delay_width")
                    local new_val = util.clamp(current + d * 0.01, 0, 1)
                    params:set("delay_width", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                end
            elseif effects_mode_state.selected_effect == 2 then
                -- EQ effect
                if effects_mode_state.selected_param == 1 then
                    -- Low Cut (exponential)
                    local current = params:get("eq_low_cut")
                    local new_val = math.max(10, math.min(5000, current * math.exp(d * 0.05)))
                    params:set("eq_low_cut", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif effects_mode_state.selected_param == 2 then
                    -- High Cut (exponential)
                    local current = params:get("eq_high_cut")
                    local new_val = math.max(500, math.min(22000, current * math.exp(d * 0.05)))
                    params:set("eq_high_cut", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif effects_mode_state.selected_param == 3 then
                    -- Low Gain
                    local current = params:get("eq_low_gain")
                    local new_val = util.clamp(current + d * 0.5, -48, 24)
                    params:set("eq_low_gain", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif effects_mode_state.selected_param == 4 then
                    -- Mid Gain
                    local current = params:get("eq_mid_gain")
                    local new_val = util.clamp(current + d * 0.5, -48, 24)
                    params:set("eq_mid_gain", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                elseif effects_mode_state.selected_param == 5 then
                    -- High Gain
                    local current = params:get("eq_high_gain")
                    local new_val = util.clamp(current + d * 0.5, -48, 24)
                    params:set("eq_high_gain", new_val)
                    store_snapshot(get_current_snapshot_from_position())
                end
            end
        elseif norns_mode == 6 then
            -- Matrix mode: Navigate Y position or adjust glide
            if grid_ui_state.shift_held then
                -- Shift + enc 3: Adjust glide time
                local current_glide = params:get("glide")
                local new_glide = math.max(0.05, math.min(20, current_glide + d * 0.1))
                params:set("glide", new_glide)
                if params:get("info_banner") == 2 then
                    info_banner_mod.show(string.format("GLIDE: %.2fs", new_glide))
                end
            else
                -- Normal: Navigate Y position
                selected_matrix_pos.y = selected_matrix_pos.y + d
                selected_matrix_pos.y = math.max(1, math.min(14, selected_matrix_pos.y))
            end
        elseif norns_mode >= 1 and norns_mode <= 4 then
            -- Other modes: Adjust parameter for selected band
            if grid_ui_state.shift_held then
                -- Shift held: Adjust all bands
                if norns_mode == 1 then
                    -- Adjust all levels
                    local step = d * 0.5 -- 0.5dB per turn for levels
                    for i = 1, #freqs do
                        local current_level = params:get(string.format("band_%02d_level", i))
                        local new_level = math.max(-60, math.min(12, current_level + step))
                        params:set(string.format("band_%02d_level", i), new_level)
                    end
                elseif norns_mode == 2 then
                    -- Adjust all pans
                    local step = d * 0.01 -- 0.01 per turn for pan
                    for i = 1, #freqs do
                        local current_pan = params:get(string.format("band_%02d_pan", i))
                        local new_pan = math.max(-1, math.min(1, current_pan + step))
                        params:set(string.format("band_%02d_pan", i), new_pan)
                    end
                elseif norns_mode == 3 then
                    -- Adjust all thresholds
                    local step = d * 0.01 -- 0.01 per turn for thresholds (0.0-1.0 range)
                    for i = 1, #freqs do
                        local current_thresh = params:get(string.format("band_%02d_thresh", i))
                        local new_thresh = math.max(0, math.min(1, current_thresh + step))
                        params:set(string.format("band_%02d_thresh", i), new_thresh)
                    end
                elseif norns_mode == 4 then
                    -- Adjust all decimate rates
                    -- Use exponential steps for musical feel
                    local step = d * 500 -- 500 Hz steps
                    for i = 1, #freqs do
                        local current_rate = params:get(string.format("band_%02d_decimate", i))
                        local new_rate = math.max(100, math.min(48000, current_rate + step))
                        params:set(string.format("band_%02d_decimate", i), new_rate)
                    end
                end
                -- Save to current snapshot
                store_snapshot(get_current_snapshot_from_position())
            else
                -- No shift: Adjust selected band only
                local band_idx = selected_band

                if norns_mode == 1 then
                    -- Adjust level - faster steps for easier adjustment
                    local step = d * 0.5 -- 0.5dB per turn for levels
                    local current_level = params:get(string.format("band_%02d_level", band_idx))
                    local new_level = math.max(-60, math.min(12, current_level + step))
                    params:set(string.format("band_%02d_level", band_idx), new_level)
                    -- Save to current snapshot
                    store_snapshot(get_current_snapshot_from_position())
                elseif norns_mode == 2 then
                    -- Adjust pan - fine control
                    local step = d * 0.01 -- 0.01 per turn for pan
                    local current_pan = params:get(string.format("band_%02d_pan", band_idx))
                    local new_pan = math.max(-1, math.min(1, current_pan + step))
                    params:set(string.format("band_%02d_pan", band_idx), new_pan)
                    -- Save to current snapshot
                    store_snapshot(get_current_snapshot_from_position())
                elseif norns_mode == 3 then
                    -- Adjust threshold - fine control
                    local step = d * 0.01 -- 0.01 per turn for thresholds (0.0-1.0 range)
                    local current_thresh = params:get(string.format("band_%02d_thresh", band_idx))
                    local new_thresh = math.max(0, math.min(1, current_thresh + step))
                    params:set(string.format("band_%02d_thresh", band_idx), new_thresh)
                    -- Save to current snapshot
                    store_snapshot(get_current_snapshot_from_position())
                elseif norns_mode == 4 then
                    -- Adjust decimate rate
                    local step = d * 500 -- 500 Hz steps
                    local current_rate = params:get(string.format("band_%02d_decimate", band_idx))
                    local new_rate = math.max(100, math.min(48000, current_rate + step))
                    params:set(string.format("band_%02d_decimate", band_idx), new_rate)
                    -- Save to current snapshot
                    store_snapshot(get_current_snapshot_from_position())
                end
            end
        end
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
        controlspec = controlspec.new(0.01, 2.0, 'exp', 0.01, 0.5, 's'),
        formatter = function(p) return string.format("%.2fs", p:get()) end,
        action = function(time)
            if engine and engine.delay_time then engine.delay_time(time) end
        end
    }

    params:add {
        type = "control",
        id = "delay_feedback",
        name = "Feedback",
        controlspec = controlspec.new(0, 1.2, 'lin', 0.01, 0.5), -- Max 1.2 for extreme/self-oscillating feedback
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
    params:add_group("snapshot A", 88)
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
        type = "control",
        id = "snapshot_a_delay_time",
        name = "Delay Time",
        controlspec = controlspec.new(0.01, 2.0, 'exp', 0.01, 0.5, 's'),
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
    params:add_group("snapshot B", 88)
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
        type = "control",
        id = "snapshot_b_delay_time",
        name = "Delay Time",
        controlspec = controlspec.new(0.01, 2.0, 'exp', 0.01, 0.5, 's'),
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
    params:add_group("snapshot C", 88)
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
        type = "control",
        id = "snapshot_c_delay_time",
        name = "Delay Time",
        controlspec = controlspec.new(0.01, 2.0, 'exp', 0.01, 0.5, 's'),
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
    params:add_group("snapshot D", 88)
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
        type = "control",
        id = "snapshot_d_delay_time",
        name = "Delay Time",
        controlspec = controlspec.new(0.01, 2.0, 'exp', 0.01, 0.5, 's'),
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
