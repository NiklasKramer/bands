-- Meter polling for bands script

local Meters = {}

function Meters.init(freqs, band_meters_table)
    local band_meter_polls = {}

    for i = 1, #freqs do
        local poll_name = "meter_" .. (i - 1)
        local p = poll.set(poll_name, function(v)
            v = v or 0
            band_meters_table[i] = v
        end)
        p.time = 1 / 60
        p:start()
        band_meter_polls[#band_meter_polls + 1] = p
    end

    return band_meter_polls
end

function Meters.cleanup(band_meter_polls)
    for i = 1, #band_meter_polls do
        local p = band_meter_polls[i]
        if p then p:stop() end
        band_meter_polls[i] = nil
    end
end

return Meters
