-- Snapshot management module
-- Handles snapshot storage, recall, and switching

local Snapshot = {}

-- Initialize current state from snapshot A
function Snapshot.init_current_state(params, freqs)
    -- Initialize from current snapshot (A by default)
    params:set("q", params:get("snapshot_a_q"))

    -- Initialize input settings from snapshot A
    params:set("audio_in_level", params:get("snapshot_a_audio_in_level"))
    params:set("noise_level", params:get("snapshot_a_noise_level"))
    params:set("dust_level", params:get("snapshot_a_dust_level"))
    params:set("noise_lfo_rate", params:get("snapshot_a_noise_lfo_rate"))
    params:set("noise_lfo_depth", params:get("snapshot_a_noise_lfo_depth"))
    params:set("dust_density", params:get("snapshot_a_dust_density"))
    params:set("osc_level", params:get("snapshot_a_osc_level"))
    params:set("osc_freq", params:get("snapshot_a_osc_freq"))
    params:set("osc_timbre", params:get("snapshot_a_osc_timbre"))
    params:set("osc_warp", params:get("snapshot_a_osc_warp"))
    params:set("osc_mod_rate", params:get("snapshot_a_osc_mod_rate"))
    params:set("osc_mod_depth", params:get("snapshot_a_osc_mod_depth"))
    params:set("file_level", params:get("snapshot_a_file_level"))
    params:set("file_speed", params:get("snapshot_a_file_speed"))
    params:set("delay_time", params:get("snapshot_a_delay_time"))
    params:set("delay_feedback", params:get("snapshot_a_delay_feedback"))
    params:set("delay_mix", params:get("snapshot_a_delay_mix"))
    params:set("delay_width", params:get("snapshot_a_delay_width"))
    params:set("eq_low_cut", params:get("snapshot_a_eq_low_cut"))
    params:set("eq_high_cut", params:get("snapshot_a_eq_high_cut"))
    params:set("eq_low_gain", params:get("snapshot_a_eq_low_gain"))
    params:set("eq_mid_gain", params:get("snapshot_a_eq_mid_gain"))
    params:set("eq_high_gain", params:get("snapshot_a_eq_high_gain"))

    for i = 1, #freqs do
        local level = params:get(string.format("snapshot_a_%02d_level", i))
        local pan = params:get(string.format("snapshot_a_%02d_pan", i))
        local thresh = params:get(string.format("snapshot_a_%02d_thresh", i))
        local decimate = params:get(string.format("snapshot_a_%02d_decimate", i))

        -- Initialize hidden band parameters
        params:set(string.format("band_%02d_level", i), level)
        params:set(string.format("band_%02d_pan", i), pan)
        params:set(string.format("band_%02d_thresh", i), thresh)
        params:set(string.format("band_%02d_decimate", i), decimate)
    end
end

-- Initialize snapshot parameters (placeholder for future use)
function Snapshot.init_snapshots()
    -- Snapshots are now stored in Norns params with default values
    -- All snapshots: Center pan (0.0), thresholds (0.0 - all audio passes through)
    -- No initialization needed - params handle persistence automatically
end

-- Store current state to snapshot
function Snapshot.store_snapshot(snapshot_name, params, freqs)
    -- Store to Norns params for persistence
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_q", params:get("q"))

    -- Store input settings
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_audio_in_level", params:get("audio_in_level"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_noise_level", params:get("noise_level"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_dust_level", params:get("dust_level"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_noise_lfo_rate", params:get("noise_lfo_rate"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_noise_lfo_depth", params:get("noise_lfo_depth"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_noise_lfo_rate_jitter_rate", params:get("noise_lfo_rate_jitter_rate"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_noise_lfo_rate_jitter_depth", params:get("noise_lfo_rate_jitter_depth"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_dust_density", params:get("dust_density"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_osc_level", params:get("osc_level"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_osc_freq", params:get("osc_freq"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_osc_timbre", params:get("osc_timbre"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_osc_warp", params:get("osc_warp"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_osc_mod_rate", params:get("osc_mod_rate"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_osc_mod_depth", params:get("osc_mod_depth"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_file_level", params:get("file_level"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_file_speed", params:get("file_speed"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_file_gate", params:get("file_gate"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_delay_time", params:get("delay_time"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_delay_feedback", params:get("delay_feedback"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_delay_mix", params:get("delay_mix"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_delay_width", params:get("delay_width"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_eq_low_cut", params:get("eq_low_cut"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_eq_high_cut", params:get("eq_high_cut"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_eq_low_gain", params:get("eq_low_gain"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_eq_mid_gain", params:get("eq_mid_gain"))
    params:set("snapshot_" .. string.lower(snapshot_name) .. "_eq_high_gain", params:get("eq_high_gain"))

    for i = 1, #freqs do
        local level_id = string.format("snapshot_%s_%02d_level", string.lower(snapshot_name), i)
        local pan_id = string.format("snapshot_%s_%02d_pan", string.lower(snapshot_name), i)
        local thresh_id = string.format("snapshot_%s_%02d_thresh", string.lower(snapshot_name), i)
        local decimate_id = string.format("snapshot_%s_%02d_decimate", string.lower(snapshot_name), i)

        params:set(level_id, params:get(string.format("band_%02d_level", i)))
        params:set(pan_id, params:get(string.format("band_%02d_pan", i)))
        params:set(thresh_id, params:get(string.format("band_%02d_thresh", i)))
        params:set(decimate_id, params:get(string.format("band_%02d_decimate", i)))
    end
end

-- Recall snapshot
function Snapshot.recall_snapshot(snapshot_name, params, freqs)
    -- Read from Norns params and update current state
    local snapshot_q = params:get("snapshot_" .. string.lower(snapshot_name) .. "_q")
    params:set("q", snapshot_q)

    -- Recall input settings
    params:set("audio_in_level", params:get("snapshot_" .. string.lower(snapshot_name) .. "_audio_in_level"))
    params:set("noise_level", params:get("snapshot_" .. string.lower(snapshot_name) .. "_noise_level"))
    params:set("dust_level", params:get("snapshot_" .. string.lower(snapshot_name) .. "_dust_level"))
    params:set("noise_lfo_rate", params:get("snapshot_" .. string.lower(snapshot_name) .. "_noise_lfo_rate"))
    params:set("noise_lfo_depth", params:get("snapshot_" .. string.lower(snapshot_name) .. "_noise_lfo_depth"))
    params:set("noise_lfo_rate_jitter_rate", params:get("snapshot_" .. string.lower(snapshot_name) .. "_noise_lfo_rate_jitter_rate"))
    params:set("noise_lfo_rate_jitter_depth", params:get("snapshot_" .. string.lower(snapshot_name) .. "_noise_lfo_rate_jitter_depth"))
    params:set("dust_density", params:get("snapshot_" .. string.lower(snapshot_name) .. "_dust_density"))
    params:set("osc_level", params:get("snapshot_" .. string.lower(snapshot_name) .. "_osc_level"))
    params:set("osc_freq", params:get("snapshot_" .. string.lower(snapshot_name) .. "_osc_freq"))
    params:set("osc_timbre", params:get("snapshot_" .. string.lower(snapshot_name) .. "_osc_timbre"))
    params:set("osc_warp", params:get("snapshot_" .. string.lower(snapshot_name) .. "_osc_warp"))
    params:set("osc_mod_rate", params:get("snapshot_" .. string.lower(snapshot_name) .. "_osc_mod_rate"))
    params:set("osc_mod_depth", params:get("snapshot_" .. string.lower(snapshot_name) .. "_osc_mod_depth"))
    params:set("file_level", params:get("snapshot_" .. string.lower(snapshot_name) .. "_file_level"))
    params:set("file_speed", params:get("snapshot_" .. string.lower(snapshot_name) .. "_file_speed"))
    params:set("file_gate", params:get("snapshot_" .. string.lower(snapshot_name) .. "_file_gate"))
    params:set("delay_time", params:get("snapshot_" .. string.lower(snapshot_name) .. "_delay_time"))
    params:set("delay_feedback", params:get("snapshot_" .. string.lower(snapshot_name) .. "_delay_feedback"))
    params:set("delay_mix", params:get("snapshot_" .. string.lower(snapshot_name) .. "_delay_mix"))
    params:set("delay_width", params:get("snapshot_" .. string.lower(snapshot_name) .. "_delay_width"))
    params:set("eq_low_cut", params:get("snapshot_" .. string.lower(snapshot_name) .. "_eq_low_cut"))
    params:set("eq_high_cut", params:get("snapshot_" .. string.lower(snapshot_name) .. "_eq_high_cut"))
    params:set("eq_low_gain", params:get("snapshot_" .. string.lower(snapshot_name) .. "_eq_low_gain"))
    params:set("eq_mid_gain", params:get("snapshot_" .. string.lower(snapshot_name) .. "_eq_mid_gain"))
    params:set("eq_high_gain", params:get("snapshot_" .. string.lower(snapshot_name) .. "_eq_high_gain"))

    for i = 1, #freqs do
        local level_id = string.format("snapshot_%s_%02d_level", string.lower(snapshot_name), i)
        local pan_id = string.format("snapshot_%s_%02d_pan", string.lower(snapshot_name), i)
        local thresh_id = string.format("snapshot_%s_%02d_thresh", string.lower(snapshot_name), i)

        local level_val = params:get(level_id)
        local pan_val = params:get(pan_id)
        local thresh_val = params:get(thresh_id)

        -- Update hidden band parameters (this will update the engine automatically)
        params:set(string.format("band_%02d_level", i), level_val)
        params:set(string.format("band_%02d_pan", i), pan_val)
        params:set(string.format("band_%02d_thresh", i), thresh_val)
    end
end

-- Switch to a snapshot
function Snapshot.switch_to_snapshot(snapshot_name, params, freqs, grid_ui_state, glide_state, apply_blend, redraw,
                                     redraw_grid)
    -- Recall the snapshot parameters
    Snapshot.recall_snapshot(snapshot_name, params, freqs)

    -- Stop any ongoing glide when switching snapshots
    glide_state.is_gliding = false

    -- Move matrix position to corresponding corner
    local old_x = grid_ui_state.current_matrix_pos.x
    local old_y = grid_ui_state.current_matrix_pos.y

    if snapshot_name == "A" then
        grid_ui_state.current_matrix_pos = { x = 1, y = 1 }   -- Top-left (2,2 on grid)
    elseif snapshot_name == "B" then
        grid_ui_state.current_matrix_pos = { x = 14, y = 1 }  -- Top-right (15,2 on grid)
    elseif snapshot_name == "C" then
        grid_ui_state.current_matrix_pos = { x = 1, y = 14 }  -- Bottom-left (2,15 on grid)
    elseif snapshot_name == "D" then
        grid_ui_state.current_matrix_pos = { x = 14, y = 14 } -- Bottom-right (15,15 on grid)
    end

    -- Apply the blend for the new matrix position WITHOUT glide (force immediate)
    local saved_glide_param = params:get("glide")
    params:set("glide", 0)                 -- Temporarily disable glide
    apply_blend(grid_ui_state.current_matrix_pos.x, grid_ui_state.current_matrix_pos.y, old_x, old_y)
    params:set("glide", saved_glide_param) -- Restore glide setting

    redraw()                               -- Update the screen to show the new snapshot
    redraw_grid()                          -- Update the grid to show the new snapshot
end

return Snapshot
