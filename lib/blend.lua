-- Blend calculation and application helpers
-- Handles blending between snapshots and glide interpolation

local Blend = {}
Blend.__index = Blend

function Blend.new(params_ref, freqs_ref, glide_state_ref, grid_ui_state_ref, util_ref, engine_ref, 
                   is_at_snapshot_corner_fn, get_current_snapshot_from_position_fn, store_snapshot_fn, info_banner_mod_ref)
    local self = setmetatable({}, Blend)
    
    self.params = params_ref
    self.freqs = freqs_ref
    self.glide_state = glide_state_ref
    self.grid_ui_state = grid_ui_state_ref
    self.util = util_ref
    self.engine = engine_ref
    self.is_at_snapshot_corner = is_at_snapshot_corner_fn
    self.get_current_snapshot_from_position = get_current_snapshot_from_position_fn
    self.store_snapshot = store_snapshot_fn
    self.info_banner_mod = info_banner_mod_ref
    
    return self
end

-- Calculate blended target values from snapshots
function Blend:calculate_target_values(a_w, b_w, c_w, d_w)
    local target_values = {}

    -- Blend global Q
    target_values.q = self.params:get("snapshot_a_q") * a_w +
        self.params:get("snapshot_b_q") * b_w +
        self.params:get("snapshot_c_q") * c_w +
        self.params:get("snapshot_d_q") * d_w

    -- Blend input settings
    target_values.audio_in_level = self.params:get("snapshot_a_audio_in_level") * a_w +
        self.params:get("snapshot_b_audio_in_level") * b_w +
        self.params:get("snapshot_c_audio_in_level") * c_w +
        self.params:get("snapshot_d_audio_in_level") * d_w

    target_values.noise_level = self.params:get("snapshot_a_noise_level") * a_w +
        self.params:get("snapshot_b_noise_level") * b_w +
        self.params:get("snapshot_c_noise_level") * c_w +
        self.params:get("snapshot_d_noise_level") * d_w

    target_values.dust_level = self.params:get("snapshot_a_dust_level") * a_w +
        self.params:get("snapshot_b_dust_level") * b_w +
        self.params:get("snapshot_c_dust_level") * c_w +
        self.params:get("snapshot_d_dust_level") * d_w

    target_values.noise_lfo_rate = self.params:get("snapshot_a_noise_lfo_rate") * a_w +
        self.params:get("snapshot_b_noise_lfo_rate") * b_w +
        self.params:get("snapshot_c_noise_lfo_rate") * c_w +
        self.params:get("snapshot_d_noise_lfo_rate") * d_w

    target_values.noise_lfo_depth = self.params:get("snapshot_a_noise_lfo_depth") * a_w +
        self.params:get("snapshot_b_noise_lfo_depth") * b_w +
        self.params:get("snapshot_c_noise_lfo_depth") * c_w +
        self.params:get("snapshot_d_noise_lfo_depth") * d_w

    target_values.noise_lfo_rate_jitter_rate = self.params:get("snapshot_a_noise_lfo_rate_jitter_rate") * a_w +
        self.params:get("snapshot_b_noise_lfo_rate_jitter_rate") * b_w +
        self.params:get("snapshot_c_noise_lfo_rate_jitter_rate") * c_w +
        self.params:get("snapshot_d_noise_lfo_rate_jitter_rate") * d_w

    target_values.noise_lfo_rate_jitter_depth = self.params:get("snapshot_a_noise_lfo_rate_jitter_depth") * a_w +
        self.params:get("snapshot_b_noise_lfo_rate_jitter_depth") * b_w +
        self.params:get("snapshot_c_noise_lfo_rate_jitter_depth") * c_w +
        self.params:get("snapshot_d_noise_lfo_rate_jitter_depth") * d_w

    target_values.dust_density = self.params:get("snapshot_a_dust_density") * a_w +
        self.params:get("snapshot_b_dust_density") * b_w +
        self.params:get("snapshot_c_dust_density") * c_w +
        self.params:get("snapshot_d_dust_density") * d_w

    target_values.osc_level = self.params:get("snapshot_a_osc_level") * a_w +
        self.params:get("snapshot_b_osc_level") * b_w +
        self.params:get("snapshot_c_osc_level") * c_w +
        self.params:get("snapshot_d_osc_level") * d_w

    target_values.osc_freq = self.params:get("snapshot_a_osc_freq") * a_w +
        self.params:get("snapshot_b_osc_freq") * b_w +
        self.params:get("snapshot_c_osc_freq") * c_w +
        self.params:get("snapshot_d_osc_freq") * d_w

    target_values.osc_timbre = self.params:get("snapshot_a_osc_timbre") * a_w +
        self.params:get("snapshot_b_osc_timbre") * b_w +
        self.params:get("snapshot_c_osc_timbre") * c_w +
        self.params:get("snapshot_d_osc_timbre") * d_w

    target_values.osc_warp = self.params:get("snapshot_a_osc_warp") * a_w +
        self.params:get("snapshot_b_osc_warp") * b_w +
        self.params:get("snapshot_c_osc_warp") * c_w +
        self.params:get("snapshot_d_osc_warp") * d_w

    target_values.osc_mod_rate = self.params:get("snapshot_a_osc_mod_rate") * a_w +
        self.params:get("snapshot_b_osc_mod_rate") * b_w +
        self.params:get("snapshot_c_osc_mod_rate") * c_w +
        self.params:get("snapshot_d_osc_mod_rate") * d_w

    target_values.osc_mod_depth = self.params:get("snapshot_a_osc_mod_depth") * a_w +
        self.params:get("snapshot_b_osc_mod_depth") * b_w +
        self.params:get("snapshot_c_osc_mod_depth") * c_w +
        self.params:get("snapshot_d_osc_mod_depth") * d_w

    target_values.file_level = self.params:get("snapshot_a_file_level") * a_w +
        self.params:get("snapshot_b_file_level") * b_w +
        self.params:get("snapshot_c_file_level") * c_w +
        self.params:get("snapshot_d_file_level") * d_w

    target_values.file_speed = self.params:get("snapshot_a_file_speed") * a_w +
        self.params:get("snapshot_b_file_speed") * b_w +
        self.params:get("snapshot_c_file_speed") * c_w +
        self.params:get("snapshot_d_file_speed") * d_w

    target_values.file_gate = self.params:get("snapshot_a_file_gate") * a_w +
        self.params:get("snapshot_b_file_gate") * b_w +
        self.params:get("snapshot_c_file_gate") * c_w +
        self.params:get("snapshot_d_file_gate") * d_w

    target_values.delay_time = self.params:get("snapshot_a_delay_time") * a_w +
        self.params:get("snapshot_b_delay_time") * b_w +
        self.params:get("snapshot_c_delay_time") * c_w +
        self.params:get("snapshot_d_delay_time") * d_w

    target_values.delay_feedback = self.params:get("snapshot_a_delay_feedback") * a_w +
        self.params:get("snapshot_b_delay_feedback") * b_w +
        self.params:get("snapshot_c_delay_feedback") * c_w +
        self.params:get("snapshot_d_delay_feedback") * d_w

    target_values.delay_mix = self.params:get("snapshot_a_delay_mix") * a_w +
        self.params:get("snapshot_b_delay_mix") * b_w +
        self.params:get("snapshot_c_delay_mix") * c_w +
        self.params:get("snapshot_d_delay_mix") * d_w

    target_values.delay_width = self.params:get("snapshot_a_delay_width") * a_w +
        self.params:get("snapshot_b_delay_width") * b_w +
        self.params:get("snapshot_c_delay_width") * c_w +
        self.params:get("snapshot_d_delay_width") * d_w

    target_values.eq_low_cut = self.params:get("snapshot_a_eq_low_cut") * a_w +
        self.params:get("snapshot_b_eq_low_cut") * b_w +
        self.params:get("snapshot_c_eq_low_cut") * c_w +
        self.params:get("snapshot_d_eq_low_cut") * d_w

    target_values.eq_high_cut = self.params:get("snapshot_a_eq_high_cut") * a_w +
        self.params:get("snapshot_b_eq_high_cut") * b_w +
        self.params:get("snapshot_c_eq_high_cut") * c_w +
        self.params:get("snapshot_d_eq_high_cut") * d_w

    target_values.eq_low_gain = self.params:get("snapshot_a_eq_low_gain") * a_w +
        self.params:get("snapshot_b_eq_low_gain") * b_w +
        self.params:get("snapshot_c_eq_low_gain") * c_w +
        self.params:get("snapshot_d_eq_low_gain") * d_w

    target_values.eq_mid_gain = self.params:get("snapshot_a_eq_mid_gain") * a_w +
        self.params:get("snapshot_b_eq_mid_gain") * b_w +
        self.params:get("snapshot_c_eq_mid_gain") * c_w +
        self.params:get("snapshot_d_eq_mid_gain") * d_w

    target_values.eq_high_gain = self.params:get("snapshot_a_eq_high_gain") * a_w +
        self.params:get("snapshot_b_eq_high_gain") * b_w +
        self.params:get("snapshot_c_eq_high_gain") * c_w +
        self.params:get("snapshot_d_eq_high_gain") * d_w

    -- Blend per-band parameters
    for i = 1, #self.freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)
        local decimate_id = string.format("band_%02d_decimate", i)

        target_values[level_id] = self.params:get(string.format("snapshot_a_%02d_level", i)) * a_w +
            self.params:get(string.format("snapshot_b_%02d_level", i)) * b_w +
            self.params:get(string.format("snapshot_c_%02d_level", i)) * c_w +
            self.params:get(string.format("snapshot_d_%02d_level", i)) * d_w

        target_values[pan_id] = self.params:get(string.format("snapshot_a_%02d_pan", i)) * a_w +
            self.params:get(string.format("snapshot_b_%02d_pan", i)) * b_w +
            self.params:get(string.format("snapshot_c_%02d_pan", i)) * c_w +
            self.params:get(string.format("snapshot_d_%02d_pan", i)) * d_w

        target_values[thresh_id] = self.params:get(string.format("snapshot_a_%02d_thresh", i)) * a_w +
            self.params:get(string.format("snapshot_b_%02d_thresh", i)) * b_w +
            self.params:get(string.format("snapshot_c_%02d_thresh", i)) * c_w +
            self.params:get(string.format("snapshot_d_%02d_thresh", i)) * d_w

        target_values[decimate_id] = self.params:get(string.format("snapshot_a_%02d_decimate", i)) * a_w +
            self.params:get(string.format("snapshot_b_%02d_decimate", i)) * b_w +
            self.params:get(string.format("snapshot_c_%02d_decimate", i)) * c_w +
            self.params:get(string.format("snapshot_d_%02d_decimate", i)) * d_w
    end

    return target_values
end

-- Handle glide interruption: calculate current interpolated values and use as new start
function Blend:handle_glide_interruption(glide_time_param)
    local current_time = self.util.time()
    local elapsed = current_time - self.glide_state.glide_time
    local progress = math.min(elapsed / glide_time_param, 1.0)

    -- Calculate current interpolated position
    local current_x = self.glide_state.start_pos.x +
        (self.glide_state.target_pos.x - self.glide_state.start_pos.x) * progress
    local current_y = self.glide_state.start_pos.y +
        (self.glide_state.target_pos.y - self.glide_state.start_pos.y) * progress

    -- Calculate current interpolated parameter values
    local current_values = {}
    current_values.q = self.glide_state.current_values.q +
        (self.glide_state.target_values.q - self.glide_state.current_values.q) * progress

    -- Interpolate all input/effect parameters
    current_values.audio_in_level = self.glide_state.current_values.audio_in_level +
        (self.glide_state.target_values.audio_in_level - self.glide_state.current_values.audio_in_level) * progress
    current_values.noise_level = self.glide_state.current_values.noise_level +
        (self.glide_state.target_values.noise_level - self.glide_state.current_values.noise_level) * progress
    current_values.dust_level = self.glide_state.current_values.dust_level +
        (self.glide_state.target_values.dust_level - self.glide_state.current_values.dust_level) * progress
    current_values.noise_lfo_rate = self.glide_state.current_values.noise_lfo_rate +
        (self.glide_state.target_values.noise_lfo_rate - self.glide_state.current_values.noise_lfo_rate) * progress
    current_values.noise_lfo_depth = self.glide_state.current_values.noise_lfo_depth +
        (self.glide_state.target_values.noise_lfo_depth - self.glide_state.current_values.noise_lfo_depth) * progress
    current_values.noise_lfo_rate_jitter_rate = self.glide_state.current_values.noise_lfo_rate_jitter_rate +
        (self.glide_state.target_values.noise_lfo_rate_jitter_rate - self.glide_state.current_values.noise_lfo_rate_jitter_rate) *
        progress
    current_values.noise_lfo_rate_jitter_depth = self.glide_state.current_values.noise_lfo_rate_jitter_depth +
        (self.glide_state.target_values.noise_lfo_rate_jitter_depth - self.glide_state.current_values.noise_lfo_rate_jitter_depth) *
        progress
    current_values.dust_density = self.glide_state.current_values.dust_density +
        (self.glide_state.target_values.dust_density - self.glide_state.current_values.dust_density) * progress
    current_values.osc_level = self.glide_state.current_values.osc_level +
        (self.glide_state.target_values.osc_level - self.glide_state.current_values.osc_level) * progress
    current_values.osc_freq = self.glide_state.current_values.osc_freq +
        (self.glide_state.target_values.osc_freq - self.glide_state.current_values.osc_freq) * progress
    current_values.osc_timbre = self.glide_state.current_values.osc_timbre +
        (self.glide_state.target_values.osc_timbre - self.glide_state.current_values.osc_timbre) * progress
    current_values.osc_warp = self.glide_state.current_values.osc_warp +
        (self.glide_state.target_values.osc_warp - self.glide_state.current_values.osc_warp) * progress
    current_values.osc_mod_rate = self.glide_state.current_values.osc_mod_rate +
        (self.glide_state.target_values.osc_mod_rate - self.glide_state.current_values.osc_mod_rate) * progress
    current_values.osc_mod_depth = self.glide_state.current_values.osc_mod_depth +
        (self.glide_state.target_values.osc_mod_depth - self.glide_state.current_values.osc_mod_depth) * progress
    current_values.file_level = self.glide_state.current_values.file_level +
        (self.glide_state.target_values.file_level - self.glide_state.current_values.file_level) * progress
    current_values.file_speed = self.glide_state.current_values.file_speed +
        (self.glide_state.target_values.file_speed - self.glide_state.current_values.file_speed) * progress
    current_values.file_gate = self.glide_state.current_values.file_gate +
        (self.glide_state.target_values.file_gate - self.glide_state.current_values.file_gate) * progress
    current_values.delay_time = self.glide_state.current_values.delay_time +
        (self.glide_state.target_values.delay_time - self.glide_state.current_values.delay_time) * progress
    current_values.delay_feedback = self.glide_state.current_values.delay_feedback +
        (self.glide_state.target_values.delay_feedback - self.glide_state.current_values.delay_feedback) * progress
    current_values.delay_mix = self.glide_state.current_values.delay_mix +
        (self.glide_state.target_values.delay_mix - self.glide_state.current_values.delay_mix) * progress
    current_values.delay_width = self.glide_state.current_values.delay_width +
        (self.glide_state.target_values.delay_width - self.glide_state.current_values.delay_width) * progress
    current_values.eq_low_cut = self.glide_state.current_values.eq_low_cut +
        (self.glide_state.target_values.eq_low_cut - self.glide_state.current_values.eq_low_cut) * progress
    current_values.eq_high_cut = self.glide_state.current_values.eq_high_cut +
        (self.glide_state.target_values.eq_high_cut - self.glide_state.current_values.eq_high_cut) * progress
    current_values.eq_low_gain = self.glide_state.current_values.eq_low_gain +
        (self.glide_state.target_values.eq_low_gain - self.glide_state.current_values.eq_low_gain) * progress
    current_values.eq_mid_gain = self.glide_state.current_values.eq_mid_gain +
        (self.glide_state.target_values.eq_mid_gain - self.glide_state.current_values.eq_mid_gain) * progress
    current_values.eq_high_gain = self.glide_state.current_values.eq_high_gain +
        (self.glide_state.target_values.eq_high_gain - self.glide_state.current_values.eq_high_gain) * progress

    -- Interpolate per-band parameters
    for i = 1, #self.freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)
        local decimate_id = string.format("band_%02d_decimate", i)

        current_values[level_id] = self.glide_state.current_values[level_id] +
            (self.glide_state.target_values[level_id] - self.glide_state.current_values[level_id]) * progress
        current_values[pan_id] = self.glide_state.current_values[pan_id] +
            (self.glide_state.target_values[pan_id] - self.glide_state.current_values[pan_id]) * progress
        current_values[thresh_id] = self.glide_state.current_values[thresh_id] +
            (self.glide_state.target_values[thresh_id] - self.glide_state.current_values[thresh_id]) * progress
        current_values[decimate_id] = self.glide_state.current_values[decimate_id] +
            (self.glide_state.target_values[decimate_id] - self.glide_state.current_values[decimate_id]) * progress
    end

    -- Use current interpolated values as new starting point
    self.glide_state.start_pos.x = current_x or self.glide_state.start_pos.x
    self.glide_state.start_pos.y = current_y or self.glide_state.start_pos.y
    self.glide_state.current_values = current_values

    -- Validate start_pos
    if not self.glide_state.start_pos.x or self.glide_state.start_pos.x ~= self.glide_state.start_pos.x then
        self.glide_state.start_pos.x = self.grid_ui_state.current_matrix_pos.x
    end
    if not self.glide_state.start_pos.y or self.glide_state.start_pos.y ~= self.glide_state.start_pos.y then
        self.glide_state.start_pos.y = self.grid_ui_state.current_matrix_pos.y
    end

    -- Update last LED position for smooth visual transition
    self.glide_state.last_led_pos.x = math.floor(current_x + 0.5)
    self.glide_state.last_led_pos.y = math.floor(current_y + 0.5)
end

-- Initialize new glide state from current parameter values
function Blend:initialize_glide_state(old_x, old_y)
    self.glide_state.start_pos.x = old_x or self.grid_ui_state.current_matrix_pos.x
    self.glide_state.start_pos.y = old_y or self.grid_ui_state.current_matrix_pos.y

    -- Store current parameter values as starting point
    self.glide_state.current_values = {}
    self.glide_state.current_values.q = self.params:get("q")
    self.glide_state.current_values.audio_in_level = self.params:get("audio_in_level")
    self.glide_state.current_values.noise_level = self.params:get("noise_level")
    self.glide_state.current_values.dust_level = self.params:get("dust_level")
    self.glide_state.current_values.noise_lfo_rate = self.params:get("noise_lfo_rate")
    self.glide_state.current_values.noise_lfo_depth = self.params:get("noise_lfo_depth")
    self.glide_state.current_values.noise_lfo_rate_jitter_rate = self.params:get("noise_lfo_rate_jitter_rate")
    self.glide_state.current_values.noise_lfo_rate_jitter_depth = self.params:get("noise_lfo_rate_jitter_depth")
    self.glide_state.current_values.dust_density = self.params:get("dust_density")
    self.glide_state.current_values.osc_level = self.params:get("osc_level")
    self.glide_state.current_values.osc_freq = self.params:get("osc_freq")
    self.glide_state.current_values.osc_timbre = self.params:get("osc_timbre")
    self.glide_state.current_values.osc_warp = self.params:get("osc_warp")
    self.glide_state.current_values.osc_mod_rate = self.params:get("osc_mod_rate")
    self.glide_state.current_values.osc_mod_depth = self.params:get("osc_mod_depth")
    self.glide_state.current_values.file_level = self.params:get("file_level")
    self.glide_state.current_values.file_speed = self.params:get("file_speed")
    self.glide_state.current_values.file_gate = self.params:get("file_gate")
    self.glide_state.current_values.delay_time = self.params:get("delay_time")
    self.glide_state.current_values.delay_feedback = self.params:get("delay_feedback")
    self.glide_state.current_values.delay_mix = self.params:get("delay_mix")
    self.glide_state.current_values.delay_width = self.params:get("delay_width")
    self.glide_state.current_values.eq_low_cut = self.params:get("eq_low_cut")
    self.glide_state.current_values.eq_high_cut = self.params:get("eq_high_cut")
    self.glide_state.current_values.eq_low_gain = self.params:get("eq_low_gain")
    self.glide_state.current_values.eq_mid_gain = self.params:get("eq_mid_gain")
    self.glide_state.current_values.eq_high_gain = self.params:get("eq_high_gain")

    for i = 1, #self.freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)
        local decimate_id = string.format("band_%02d_decimate", i)

        self.glide_state.current_values[level_id] = self.params:get(level_id)
        self.glide_state.current_values[pan_id] = self.params:get(pan_id)
        self.glide_state.current_values[thresh_id] = self.params:get(thresh_id)
        self.glide_state.current_values[decimate_id] = self.params:get(decimate_id)
    end

    -- Initialize last LED position to start position
    self.glide_state.last_led_pos.x = self.glide_state.start_pos.x
    self.glide_state.last_led_pos.y = self.glide_state.start_pos.y
end

-- Apply values immediately without glide
function Blend:apply_values_immediately(target_values, x, y, old_x, old_y)
    self.params:set("q", target_values.q)
    self.params:set("audio_in_level", target_values.audio_in_level)
    self.params:set("noise_level", target_values.noise_level)
    self.params:set("dust_level", target_values.dust_level)
    self.params:set("noise_lfo_rate", target_values.noise_lfo_rate)
    self.params:set("noise_lfo_depth", target_values.noise_lfo_depth)
    self.params:set("noise_lfo_rate_jitter_rate", target_values.noise_lfo_rate_jitter_rate)
    self.params:set("noise_lfo_rate_jitter_depth", target_values.noise_lfo_rate_jitter_depth)
    self.params:set("dust_density", target_values.dust_density)
    self.params:set("osc_level", target_values.osc_level)
    self.params:set("osc_freq", target_values.osc_freq)
    self.params:set("osc_timbre", target_values.osc_timbre)
    self.params:set("osc_warp", target_values.osc_warp)
    self.params:set("osc_mod_rate", target_values.osc_mod_rate)
    self.params:set("osc_mod_depth", target_values.osc_mod_depth)
    self.params:set("file_level", target_values.file_level)
    self.params:set("file_speed", target_values.file_speed)
    self.params:set("file_gate", target_values.file_gate)

    -- Apply file parameters directly to engine for immediate effect
    if self.engine and self.engine.file_level then self.engine.file_level(target_values.file_level) end
    if self.engine and self.engine.file_speed then self.engine.file_speed(target_values.file_speed) end
    if self.engine and self.engine.file_gate then self.engine.file_gate(target_values.file_gate) end
    self.params:set("delay_time", target_values.delay_time)
    self.params:set("delay_feedback", target_values.delay_feedback)
    self.params:set("delay_mix", target_values.delay_mix)
    self.params:set("delay_width", target_values.delay_width)
    self.params:set("eq_low_cut", target_values.eq_low_cut)
    self.params:set("eq_high_cut", target_values.eq_high_cut)
    self.params:set("eq_low_gain", target_values.eq_low_gain)
    self.params:set("eq_mid_gain", target_values.eq_mid_gain)
    self.params:set("eq_high_gain", target_values.eq_high_gain)

    for i = 1, #self.freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)
        local decimate_id = string.format("band_%02d_decimate", i)

        self.params:set(level_id, target_values[level_id])
        self.params:set(pan_id, target_values[pan_id])
        self.params:set(thresh_id, target_values[thresh_id])
        self.params:set(decimate_id, target_values[decimate_id])
    end

    -- Only auto-save when at a snapshot corner (100% on one snapshot)
    local was_at_corner = self.is_at_snapshot_corner(old_x, old_y)
    local now_at_corner = self.is_at_snapshot_corner(x, y)

    if now_at_corner then
        local current_snapshot = self.get_current_snapshot_from_position()
        if not was_at_corner then
            if self.params:get("info_banner") == 2 then
                self.info_banner_mod.show("EDITING: " .. current_snapshot)
            end
        end
        self.store_snapshot(current_snapshot)
    elseif was_at_corner and not now_at_corner then
        if self.params:get("info_banner") == 2 then
            self.info_banner_mod.show("BLEND MODE (NO SAVE)")
        end
    end
end

return Blend

