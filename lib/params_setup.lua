-- Parameter setup for bands script
local controlspec = require 'controlspec'

local ParamsSetup = {}

function ParamsSetup.add_params(freqs)
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

    -- per-band controls
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

return ParamsSetup
