-- Screen drawing helpers for Norns display
-- Handles all screen rendering for different modes

local util = require 'util'
local ScreenDraw = {}
ScreenDraw.__index = ScreenDraw

function ScreenDraw.new(params_ref, freqs_ref, grid_ui_state_ref, input_mode_state_ref, effects_mode_state_ref,
                        selected_band_ref, band_meters_ref, path_state_ref, glide_state_ref, util_ref,
                        selected_matrix_pos_ref, get_current_snapshot_from_position_fn, path_audio_ref)
    local self = setmetatable({}, ScreenDraw)

    self.params = params_ref
    self.freqs = freqs_ref
    self.grid_ui_state = grid_ui_state_ref
    self.input_mode_state = input_mode_state_ref
    self.effects_mode_state = effects_mode_state_ref
    self.selected_band = selected_band_ref
    self.band_meters = band_meters_ref
    self.path_state = path_state_ref
    self.glide_state = glide_state_ref
    self.util = util_ref
    self.selected_matrix_pos = selected_matrix_pos_ref
    self.get_current_snapshot_from_position = get_current_snapshot_from_position_fn
    self.path_audio = path_audio_ref

    return self
end

-- Draw snapshot letters with blend weights
function ScreenDraw:draw_snapshot_letters()
    local MARGIN_RIGHT = 8
    local letter_x = 128 - MARGIN_RIGHT
    local letters = { "A", "B", "C", "D" }
    local letter_spacing = 12
    local start_y = 20

    screen.font_face(1)
    screen.font_size(8)

    if self.grid_ui_state.current_state_mode then
        -- Current state mode: show all letters at full brightness
        for i = 1, 4 do
            screen.level(15)
            screen.move(letter_x, start_y + (i - 1) * letter_spacing)
            screen.text(letters[i])
        end
    else
        -- Normal mode: show selected snapshot highlighted
        local selected = self.get_current_snapshot_from_position()
        for i = 1, 4 do
            local brightness = (letters[i] == selected) and 15 or 4
            screen.level(brightness)
            screen.move(letter_x, start_y + (i - 1) * letter_spacing)
            screen.text(letters[i])
        end
    end
end

-- Draw parameter indicator dots
function ScreenDraw:draw_parameter_dots(num_dots, selected_index, y_pos)
    local dot_spacing = 6
    local dots_width = num_dots * dot_spacing - dot_spacing
    local dot_start_x = (128 - dots_width) / 2
    for i = 1, num_dots do
        local brightness = (i == selected_index) and 15 or 4
        screen.level(brightness)
        screen.circle(dot_start_x + (i - 1) * dot_spacing, y_pos, 1.5)
        screen.fill()
    end
end

-- Draw parameter display (name, value, dots)
function ScreenDraw:draw_parameter_display(param_name, param_value, num_dots, selected_index, content_x, name_y, value_y,
                                           dot_y)
    -- Parameter name
    screen.font_face(1)
    screen.font_size(8)
    screen.level(8)
    screen.move(content_x, name_y)
    screen.text_center(param_name)

    -- Parameter value
    screen.font_face(1)
    screen.font_size(16)
    screen.level(15)
    screen.move(content_x, value_y)
    screen.text_center(param_value)

    -- Parameter dots
    self:draw_parameter_dots(num_dots, selected_index, dot_y)
end

-- Draw inputs mode screen
function ScreenDraw:draw_inputs_mode()
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
        local brightness = (self.input_mode_state.selected_input == i) and 15 or 4
        screen.level(brightness)
        screen.move(x_pos, 8)
        screen.text_center(input_symbols[i])
    end

    -- Draw parameter values based on selected input
    if self.input_mode_state.selected_input == 1 then
        -- Input audio
        local audio_level = self.params:get("audio_in_level")
        self:draw_parameter_display("LEVEL", string.format("%.2f", audio_level), 1, 1, content_x, 28, 45, 54)
    elseif self.input_mode_state.selected_input == 2 then
        -- Oscillator
        local osc_level = self.params:get("osc_level")
        local osc_freq = self.params:get("osc_freq")
        local osc_timbre = self.params:get("osc_timbre")
        local osc_warp = self.params:get("osc_warp")
        local osc_mod_rate = self.params:get("osc_mod_rate")
        local osc_mod_depth = self.params:get("osc_mod_depth")

        local param_names = { "LEVEL", "FREQ", "TIMBRE", "MORPH", "MOD RATE", "MOD DEPTH" }
        local param_values = {
            string.format("%.2f", osc_level),
            string.format("%.1f Hz", osc_freq),
            string.format("%.2f", osc_timbre),
            string.format("%.2f", osc_warp),
            string.format("%.1f Hz", osc_mod_rate),
            string.format("%.2f", osc_mod_depth)
        }

        self:draw_parameter_display(
            param_names[self.input_mode_state.selected_param],
            param_values[self.input_mode_state.selected_param],
            6,
            self.input_mode_state.selected_param,
            content_x, 28, 45, 54
        )
    elseif self.input_mode_state.selected_input == 3 then
        -- Dust
        local dust_level = self.params:get("dust_level")
        local dust_density = self.params:get("dust_density")

        local param_names = { "LEVEL", "DENSITY" }
        local param_values = {
            string.format("%.2f", dust_level),
            string.format("%d Hz", dust_density)
        }

        self:draw_parameter_display(
            param_names[self.input_mode_state.selected_param],
            param_values[self.input_mode_state.selected_param],
            2,
            self.input_mode_state.selected_param,
            content_x, 28, 45, 54
        )
    elseif self.input_mode_state.selected_input == 4 then
        -- Noise
        local noise_level = self.params:get("noise_level")
        local noise_lfo_rate = self.params:get("noise_lfo_rate")
        local noise_lfo_depth = self.params:get("noise_lfo_depth")
        local noise_lfo_rate_jitter_rate = self.params:get("noise_lfo_rate_jitter_rate")
        local noise_lfo_rate_jitter_depth = self.params:get("noise_lfo_rate_jitter_depth")

        local param_names = { "LEVEL", "LFO RATE", "LFO DEPTH", "RATE JITTER", "JITTER DEPTH" }
        local param_values = {
            string.format("%.2f", noise_level),
            string.format("%.2f Hz", noise_lfo_rate),
            string.format("%.0f%%", noise_lfo_depth * 100),
            string.format("%.2f Hz", noise_lfo_rate_jitter_rate),
            string.format("%.0f%%", noise_lfo_rate_jitter_depth * 100)
        }

        self:draw_parameter_display(
            param_names[self.input_mode_state.selected_param],
            param_values[self.input_mode_state.selected_param],
            5,
            self.input_mode_state.selected_param,
            content_x, 28, 45, 54
        )
    elseif self.input_mode_state.selected_input == 5 then
        -- File playback
        local file_level = self.params:get("file_level")
        local file_speed = self.params:get("file_speed")
        local file_gate = self.params:get("file_gate")

        local file_path = self.params:get("file_path")
        local file_name = "..."
        if file_path and file_path ~= "" and file_path ~= self.path_audio then
            -- Extract just the filename from the full path
            file_name = string.match(file_path, "([^/]+)$") or file_path
            -- Truncate if too long
            if #file_name > 12 then
                file_name = string.sub(file_name, 1, 9) .. "..."
            end
        end

        local param_names = { "LEVEL", "SPEED", "PLAY", "SELECT" }
        local param_values = {
            string.format("%.2f", file_level),
            string.format("%.2f", file_speed),
            file_gate == 1 and "ON" or "OFF",
            file_name
        }

        -- Show semitone pitch info when shift is held
        if self.grid_ui_state.shift_held then
            local current_semitones = math.floor(math.log(file_speed) / math.log(2) * 12 + 0.5)
            param_names = { "LEVEL", "SPEED", "PLAY", "PITCH" }
            param_values = {
                string.format("%.2f", file_level),
                string.format("%.2f", file_speed),
                file_gate == 1 and "ON" or "OFF",
                string.format("%+d", current_semitones)
            }
        end

        self:draw_parameter_display(
            param_names[self.input_mode_state.selected_param],
            param_values[self.input_mode_state.selected_param],
            4,
            self.input_mode_state.selected_param,
            content_x, 28, 45, 54
        )
    end

    -- Draw snapshot letters
    self:draw_snapshot_letters()
end

-- Draw levels screen
function ScreenDraw:draw_levels_screen()
    local num_bands = math.min(16, #self.freqs)
    local meter_width = 3
    local meter_spacing = 5
    local total_width = num_bands * meter_spacing - (meter_spacing - meter_width)
    local start_x = (128 - total_width) / 2
    local meter_height = 48
    local meter_y = (64 - meter_height) / 2

    for i = 1, num_bands do
        local x = start_x + (i - 1) * meter_spacing
        local meter_v = self.band_meters[i] or 0
        local snapshot_name = string.lower(self.get_current_snapshot_from_position())
        local level_db = self.params:get(string.format("snapshot_%s_%02d_level", snapshot_name, i))

        -- Convert level to meter height
        local level_height = util.clamp((level_db + 60) * meter_height / 72, 0, meter_height) -- -60dB to +12dB range

        -- Convert audio meter value to dB, then to height
        local meter_db = 0
        if meter_v > 0 then
            meter_db = 20 * math.log10(meter_v) -- Convert linear to dB
        else
            meter_db = -60                      -- Silent
        end
        local peak_height = util.clamp((meter_db + 60) * meter_height / 72, 0, meter_height)

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
    if self.selected_band >= 1 and self.selected_band <= num_bands then
        local cursor_x = start_x + (self.selected_band - 1) * meter_spacing
        screen.level(15)
        screen.rect(cursor_x, meter_y + meter_height + 3, meter_width, 2)
        screen.fill()
    end

    -- Draw snapshot letters
    self:draw_snapshot_letters()
end

-- Draw pans screen
function ScreenDraw:draw_pans_screen()
    local num_bands = math.min(16, #self.freqs)
    local indicator_width = 3
    local indicator_spacing = 5
    local total_width = num_bands * indicator_spacing - (indicator_spacing - indicator_width)
    local start_x = (128 - total_width) / 2
    local indicator_height = 48
    local indicator_y = (64 - indicator_height) / 2

    for i = 1, num_bands do
        local x = start_x + (i - 1) * indicator_spacing
        local snapshot_name = string.lower(self.get_current_snapshot_from_position())
        local pan = self.params:get(string.format("snapshot_%s_%02d_pan", snapshot_name, i))

        -- Convert pan (-1 to 1) to position (0 to indicator_height)
        -- Invert so left pan (-1) is at top, right pan (+1) is at bottom
        local pan_position = (1 - pan) * indicator_height / 2
        pan_position = util.clamp(pan_position, 0, indicator_height)

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
    if self.selected_band >= 1 and self.selected_band <= num_bands then
        local cursor_x = start_x + (self.selected_band - 1) * indicator_spacing
        screen.level(15)
        screen.rect(cursor_x, indicator_y + indicator_height + 3, indicator_width, 2)
        screen.fill()
    end

    -- Draw snapshot letters
    self:draw_snapshot_letters()
end

-- Draw thresholds screen
function ScreenDraw:draw_thresholds_screen()
    local num_bands = math.min(16, #self.freqs)
    local indicator_width = 3
    local indicator_spacing = 5
    local total_width = num_bands * indicator_spacing - (indicator_spacing - indicator_width)
    local start_x = (128 - total_width) / 2
    local indicator_height = 48
    local indicator_y = (64 - indicator_height) / 2

    for i = 1, num_bands do
        local x = start_x + (i - 1) * indicator_spacing
        local snapshot_name = string.lower(self.get_current_snapshot_from_position())
        local thresh = self.params:get(string.format("snapshot_%s_%02d_thresh", snapshot_name, i))

        -- Convert threshold (0.0 to 0.2) to position (0 to indicator_height)
        -- Higher thresholds appear higher on screen
        local thresh_position = (thresh / 0.2) * indicator_height
        thresh_position = util.clamp(thresh_position, 0, indicator_height)

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
    if self.selected_band >= 1 and self.selected_band <= num_bands then
        local cursor_x = start_x + (self.selected_band - 1) * indicator_spacing
        screen.level(15)
        screen.rect(cursor_x, indicator_y + indicator_height + 3, indicator_width, 2)
        screen.fill()
    end

    -- Draw snapshot letters
    self:draw_snapshot_letters()
end

-- Draw decimate screen
function ScreenDraw:draw_decimate_screen()
    local num_bands = math.min(16, #self.freqs)
    local indicator_width = 3
    local indicator_spacing = 5
    local total_width = num_bands * indicator_spacing - (indicator_spacing - indicator_width)
    local start_x = (128 - total_width) / 2
    local indicator_height = 48
    local indicator_y = (64 - indicator_height) / 2

    for i = 1, num_bands do
        local x = start_x + (i - 1) * indicator_spacing
        local snapshot_name = string.lower(self.get_current_snapshot_from_position())
        local rate = self.params:get(string.format("snapshot_%s_%02d_decimate", snapshot_name, i))

        -- Convert rate (100 to 48000 Hz) to position using exponential scale
        -- Lower rates (more decimation) appear lower on screen
        local normalized = -math.log(rate / 48000) / 6.2 -- 0 (48k) to 1 (100)
        local decimate_position = normalized * indicator_height
        decimate_position = util.clamp(decimate_position, 0, indicator_height)

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
    if self.selected_band >= 1 and self.selected_band <= num_bands then
        local cursor_x = start_x + (self.selected_band - 1) * indicator_spacing
        screen.level(15)
        screen.rect(cursor_x, indicator_y + indicator_height + 3, indicator_width, 2)
        screen.fill()
    end

    -- Draw snapshot letters
    self:draw_snapshot_letters()
end

-- Draw matrix screen
function ScreenDraw:draw_matrix_screen()
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
            if x == self.grid_ui_state.current_matrix_pos.x and y == self.grid_ui_state.current_matrix_pos.y then
                screen.level(15) -- Bright white for current position
            else
                screen.level(2)  -- Dark for other positions
            end

            screen.rect(cell_x, cell_y, cell_size - 1, cell_size - 1)
            screen.fill()
        end
    end

    -- Draw path points if in path mode
    if self.path_state.mode and #self.path_state.points > 0 then
        screen.level(8) -- Medium brightness for path points
        for i, point in ipairs(self.path_state.points) do
            local cell_x = start_x + (point.x - 1) * cell_size
            local cell_y = start_y + (point.y - 1) * cell_size
            screen.rect(cell_x, cell_y, cell_size - 1, cell_size - 1)
            screen.fill()
        end
    end

    -- Draw glide animation if active
    if self.glide_state.is_gliding then
        -- Calculate current glide position with sub-pixel interpolation
        local current_time = self.util.time()
        local elapsed = current_time - self.glide_state.glide_time
        local glide_time = self.params:get("glide")
        local progress = math.min(1, elapsed / glide_time)

        -- Interpolate between start and target positions
        local current_x = self.glide_state.start_pos.x +
        (self.glide_state.target_pos.x - self.glide_state.start_pos.x) * progress
        local current_y = self.glide_state.start_pos.y +
        (self.glide_state.target_pos.y - self.glide_state.start_pos.y) * progress

        -- Draw current glide position
        local glide_x = start_x + (current_x - 1) * cell_size
        local glide_y = start_y + (current_y - 1) * cell_size

        -- Bright pulsing effect for glide position
        local pulse = math.sin(self.util.time() * 10) * 0.5 + 0.5 -- 0 to 1 pulse
        screen.level(8 + math.floor(pulse * 7))                   -- 8 to 15 brightness
        screen.rect(glide_x, glide_y, cell_size - 1, cell_size - 1)
        screen.fill()

        -- Draw target position
        if self.glide_state.target_pos then
            local target_x = start_x + (self.glide_state.target_pos.x - 1) * cell_size
            local target_y = start_y + (self.glide_state.target_pos.y - 1) * cell_size
            screen.level(12) -- Medium brightness for target
            screen.rect(target_x, target_y, cell_size - 1, cell_size - 1)
            screen.fill()
        end
    end

    -- Draw selected position indicator (if different from current)
    if self.selected_matrix_pos.x ~= self.grid_ui_state.current_matrix_pos.x or
        self.selected_matrix_pos.y ~= self.grid_ui_state.current_matrix_pos.y then
        local sel_x = start_x + (self.selected_matrix_pos.x - 1) * cell_size
        local sel_y = start_y + (self.selected_matrix_pos.y - 1) * cell_size
        screen.level(8) -- Medium brightness for selected position
        -- Draw a frame around the selected position
        screen.rect(sel_x, sel_y, cell_size - 1, cell_size - 1)
        screen.stroke()
    end

    -- Draw snapshot letters
    self:draw_snapshot_letters()
end

-- Draw effects screen
function ScreenDraw:draw_effects_screen()
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
        local brightness = (self.effects_mode_state.selected_effect == i) and 15 or 4
        screen.level(brightness)
        screen.move(positions[i], 8)
        screen.text_center(effect_symbols[i])
    end

    -- Draw parameter values based on selected effect
    if self.effects_mode_state.selected_effect == 1 then
        -- Delay parameters
        local delay_time = self.params:get("delay_time")
        local delay_feedback = self.params:get("delay_feedback")
        local delay_mix = self.params:get("delay_mix")
        local delay_width = self.params:get("delay_width")

        local param_names = { "TIME", "FEEDBACK", "MIX", "WIDTH" }
        local param_values = {
            string.format("%.2fs", delay_time),
            string.format("%.2f", delay_feedback),
            string.format("%.2f", delay_mix),
            string.format("%.2f", delay_width)
        }

        self:draw_parameter_display(
            param_names[self.effects_mode_state.selected_param],
            param_values[self.effects_mode_state.selected_param],
            4,
            self.effects_mode_state.selected_param,
            content_x, 30, 46, 56
        )
    elseif self.effects_mode_state.selected_effect == 2 then
        -- EQ parameters
        local eq_low_cut = self.params:get("eq_low_cut")
        local eq_high_cut = self.params:get("eq_high_cut")
        local eq_low_gain = self.params:get("eq_low_gain")
        local eq_mid_gain = self.params:get("eq_mid_gain")
        local eq_high_gain = self.params:get("eq_high_gain")

        local param_names = { "LOW CUT", "HIGH CUT", "LOW", "MID", "HIGH" }
        local param_values = {
            string.format("%.0f Hz", eq_low_cut),
            string.format("%.0f Hz", eq_high_cut),
            string.format("%.1f dB", eq_low_gain),
            string.format("%.1f dB", eq_mid_gain),
            string.format("%.1f dB", eq_high_gain)
        }

        self:draw_parameter_display(
            param_names[self.effects_mode_state.selected_param],
            param_values[self.effects_mode_state.selected_param],
            5,
            self.effects_mode_state.selected_param,
            content_x, 30, 46, 56
        )
    end

    -- Draw snapshot letters
    self:draw_snapshot_letters()
end

return ScreenDraw
