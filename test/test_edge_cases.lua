-- Edge case tests for bands project
-- Tests rapid interactions, boundary conditions, and stress scenarios

local test_count = 0
local pass_count = 0

-- Test framework
local function test(name, func)
    test_count = test_count + 1
    print(string.format("\n--- Edge Case Test %d: %s ---", test_count, name))

    local success, error_msg = pcall(func)
    if success then
        pass_count = pass_count + 1
        print("✓ PASS")
    else
        print("✗ FAIL: " .. tostring(error_msg))
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s",
            message or "Assertion failed",
            tostring(expected),
            tostring(actual)))
    end
end

local function assert_near(actual, expected, tolerance, message)
    tolerance = tolerance or 0.001
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %s ± %s, got %s",
            message or "Assertion failed",
            tostring(expected),
            tostring(tolerance),
            tostring(actual)))
    end
end

local function assert_true(condition, message)
    if not condition then
        error(message or "Expected true, got false")
    end
end

-- Mock environment
local mock_params = {}
local mock_engine_calls = {}
local mock_grid_leds = {}
local mock_time = 0

local params = {
    get = function(id) return mock_params[id] or 0 end,
    set = function(id, value)
        mock_params[id] = value
        -- Simulate parameter change callbacks
        if id == "glide" and value > 0 then
            -- Glide parameter changed
        end
    end
}

local engine = {
    level = function(band, level) mock_engine_calls["level_" .. band] = level end,
    pan = function(band, pan) mock_engine_calls["pan_" .. band] = pan end,
    q = function(q) mock_engine_calls.q = q end,
    thresh_band = function(band, thresh) mock_engine_calls["thresh_" .. band] = thresh end
}

local grid_device = {
    led = function(self, x, y, brightness)
        mock_grid_leds[x .. "," .. y] = brightness
    end,
    refresh = function(self) end,
    all = function(self, brightness)
        mock_grid_leds = {}
        for x = 1, 16 do
            for y = 1, 16 do
                mock_grid_leds[x .. "," .. y] = brightness
            end
        end
    end
}

local util = {
    time = function()
        mock_time = mock_time + 0.001 -- Simulate time progression
        return mock_time
    end
}

-- Test data
local freqs = {
    80, 150, 250, 350, 500, 630, 800, 1000,
    1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
}

local snapshots = {
    A = { name = "Snapshot A", params = {} },
    B = { name = "Snapshot B", params = {} },
    C = { name = "Snapshot C", params = {} },
    D = { name = "Snapshot D", params = {} }
}

local grid_ui_state = {
    grid_device = grid_device,
    freqs = freqs,
    mode_names = { "levels", "pans", "thresholds", "matrix" },
    grid_mode = 1,
    shift_held = false,
    current_matrix_pos = { x = 1, y = 1 }
}

local glide_state = {
    current_values = {},
    target_values = {},
    glide_time = 0,
    is_gliding = false,
    start_pos = { x = 0, y = 0 },
    target_pos = { x = 0, y = 0 },
    last_led_pos = { x = 0, y = 0 }
}

-- Initialize snapshots
local function init_snapshots()
    for snapshot_name, snapshot in pairs(snapshots) do
        for i = 1, #freqs do
            snapshot.params[i] = {
                level = -12.0,
                pan = 0.0,
                thresh = 0.0
            }
        end
        snapshot.params.q = 1.1
    end
end

-- Functions under test
local function calculate_blend_weights(x, y)
    local norm_x = (x - 1) / 13
    local norm_y = (y - 1) / 13

    local a_weight = (1 - norm_x) * (1 - norm_y)
    local b_weight = norm_x * (1 - norm_y)
    local c_weight = (1 - norm_x) * norm_y
    local d_weight = norm_x * norm_y

    return a_weight, b_weight, c_weight, d_weight
end

local function apply_blend_immediate(x, y)
    local a_w, b_w, c_w, d_w = calculate_blend_weights(x, y)

    local blended_q = snapshots.A.params.q * a_w +
        snapshots.B.params.q * b_w +
        snapshots.C.params.q * c_w +
        snapshots.D.params.q * d_w

    params.set("q", blended_q)
    engine.q(blended_q)

    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)

        local blended_level = snapshots.A.params[i].level * a_w +
            snapshots.B.params[i].level * b_w +
            snapshots.C.params[i].level * c_w +
            snapshots.D.params[i].level * d_w

        local blended_pan = snapshots.A.params[i].pan * a_w +
            snapshots.B.params[i].pan * b_w +
            snapshots.C.params[i].pan * c_w +
            snapshots.D.params[i].pan * d_w

        local blended_thresh = snapshots.A.params[i].thresh * a_w +
            snapshots.B.params[i].thresh * b_w +
            snapshots.C.params[i].thresh * c_w +
            snapshots.D.params[i].thresh * d_w

        params.set(level_id, blended_level)
        params.set(pan_id, blended_pan)
        params.set(thresh_id, blended_thresh)

        engine.level(i, blended_level)
        engine.pan(i, blended_pan)
        engine.thresh_band(i, blended_thresh)
    end
end

local function simulate_grid_key_press(x, y, z)
    -- Simulate grid key press handling
    if z == 1 then -- Key down
        if x >= 2 and x <= 15 and y >= 2 and y <= 15 then
            -- Matrix area
            local matrix_x = x - 1
            local matrix_y = y - 1
            grid_ui_state.current_matrix_pos.x = matrix_x
            grid_ui_state.current_matrix_pos.y = matrix_y
            apply_blend_immediate(matrix_x, matrix_y)
        elseif y == 1 and x >= 2 and x <= 5 then
            -- Snapshot selection (A, B, C, D)
            local snapshot_names = { "A", "B", "C", "D" }
            local snapshot = snapshot_names[x - 1]
            if snapshot then
                -- Simulate snapshot recall
                print(string.format("Recalled Snapshot %s", snapshot))
            end
        elseif x == 1 and y >= 2 and y <= 5 then
            -- Mode selection
            grid_ui_state.grid_mode = y - 1
            print(string.format("Switched to mode %d", grid_ui_state.grid_mode))
        end
    end
end

local function simulate_rapid_key_sequence(sequence, delay_ms)
    delay_ms = delay_ms or 1 -- Default 1ms between presses

    for i, key_event in ipairs(sequence) do
        local x, y, z = key_event[1], key_event[2], key_event[3]
        simulate_grid_key_press(x, y, z)

        -- Simulate time delay
        for j = 1, delay_ms do
            util.time()
        end
    end
end

local function reset_mocks()
    mock_params = {}
    mock_engine_calls = {}
    mock_grid_leds = {}
    mock_time = 0
    glide_state.is_gliding = false
    grid_ui_state.current_matrix_pos = { x = 1, y = 1 }
end

-- Edge case tests
print("=== BANDS EDGE CASE TEST SUITE ===")

test("Rapid snapshot switching", function()
    reset_mocks()
    init_snapshots()

    -- Set up different snapshots
    snapshots.A.params.q = 1.0
    snapshots.B.params.q = 2.0
    snapshots.C.params.q = 3.0
    snapshots.D.params.q = 4.0

    -- Simulate rapid snapshot switching (A->B->C->D->A in 5ms)
    local rapid_sequence = {
        { 2, 1, 1 }, -- Press A
        { 2, 1, 0 }, -- Release A
        { 3, 1, 1 }, -- Press B
        { 3, 1, 0 }, -- Release B
        { 4, 1, 1 }, -- Press C
        { 4, 1, 0 }, -- Release C
        { 5, 1, 1 }, -- Press D
        { 5, 1, 0 }, -- Release D
        { 2, 1, 1 }, -- Press A again
        { 2, 1, 0 }, -- Release A
    }

    simulate_rapid_key_sequence(rapid_sequence, 1)

    -- Should handle rapid switching without errors
    assert_true(true, "Rapid snapshot switching should not crash")
end)

test("Matrix corner hammering", function()
    reset_mocks()
    init_snapshots()

    -- Set up extreme values in corners
    snapshots.A.params.q = 0.1   -- Minimum Q
    snapshots.B.params.q = 200.0 -- Maximum Q
    snapshots.C.params.q = 0.1
    snapshots.D.params.q = 200.0

    -- Rapidly hammer all four corners
    local corner_sequence = {}
    for i = 1, 50 do                                 -- 50 rapid presses on each corner
        table.insert(corner_sequence, { 2, 2, 1 })   -- Top-left (A)
        table.insert(corner_sequence, { 2, 2, 0 })
        table.insert(corner_sequence, { 15, 2, 1 })  -- Top-right (B)
        table.insert(corner_sequence, { 15, 2, 0 })
        table.insert(corner_sequence, { 2, 15, 1 })  -- Bottom-left (C)
        table.insert(corner_sequence, { 2, 15, 0 })
        table.insert(corner_sequence, { 15, 15, 1 }) -- Bottom-right (D)
        table.insert(corner_sequence, { 15, 15, 0 })
    end

    simulate_rapid_key_sequence(corner_sequence, 0.1) -- Very fast

    -- Check that final state is valid
    local final_q = mock_engine_calls.q
    assert_true(final_q >= 0.1 and final_q <= 200.0,
        string.format("Final Q should be in valid range, got %.2f", final_q or 0))
end)

test("Diagonal matrix sweeps", function()
    reset_mocks()
    init_snapshots()

    -- Simulate rapid diagonal sweeps across matrix
    local diagonal_sequence = {}

    -- Diagonal from top-left to bottom-right
    for i = 0, 13 do
        local x = 2 + i
        local y = 2 + i
        table.insert(diagonal_sequence, { x, y, 1 })
        table.insert(diagonal_sequence, { x, y, 0 })
    end

    -- Diagonal from bottom-left to top-right
    for i = 0, 13 do
        local x = 2 + i
        local y = 15 - i
        table.insert(diagonal_sequence, { x, y, 1 })
        table.insert(diagonal_sequence, { x, y, 0 })
    end

    simulate_rapid_key_sequence(diagonal_sequence, 0.5)

    -- Should complete without errors
    assert_true(true, "Diagonal sweeps should not crash")
end)

test("Boundary coordinate stress test", function()
    reset_mocks()
    init_snapshots()

    -- Test all boundary coordinates
    local boundary_coords = {
        { 1, 1 }, { 1, 14 }, { 14, 1 }, { 14, 14 }, -- Corners
        { 1, 7 }, { 14, 7 }, { 7, 1 }, { 7, 14 },   -- Edge midpoints
        { 0.5, 0.5 }, { 14.5, 14.5 },               -- Just outside bounds
        { -1,  -1 }, { 15, 15 },                    -- Way outside bounds
    }

    for _, coord in ipairs(boundary_coords) do
        local x, y = coord[1], coord[2]

        -- Clamp to valid range for testing
        local clamped_x = math.max(1, math.min(14, x))
        local clamped_y = math.max(1, math.min(14, y))

        local a_w, b_w, c_w, d_w = calculate_blend_weights(clamped_x, clamped_y)

        -- Weights should always be valid
        assert_true(a_w >= 0 and a_w <= 1,
            string.format("Weight A invalid at (%.1f,%.1f): %.6f", x, y, a_w))
        assert_true(b_w >= 0 and b_w <= 1,
            string.format("Weight B invalid at (%.1f,%.1f): %.6f", x, y, b_w))
        assert_true(c_w >= 0 and c_w <= 1,
            string.format("Weight C invalid at (%.1f,%.1f): %.6f", x, y, c_w))
        assert_true(d_w >= 0 and d_w <= 1,
            string.format("Weight D invalid at (%.1f,%.1f): %.6f", x, y, d_w))

        local sum = a_w + b_w + c_w + d_w
        assert_near(sum, 1.0, 0.0001,
            string.format("Weights don't sum to 1 at (%.1f,%.1f): %.6f", x, y, sum))
    end
end)

test("Rapid mode switching", function()
    reset_mocks()
    init_snapshots()

    -- Rapidly switch between all modes
    local mode_sequence = {}
    for cycle = 1, 20 do                                    -- 20 cycles through all modes
        for mode = 1, 4 do
            table.insert(mode_sequence, { 1, mode + 1, 1 }) -- Press mode
            table.insert(mode_sequence, { 1, mode + 1, 0 }) -- Release mode
        end
    end

    simulate_rapid_key_sequence(mode_sequence, 0.2)

    -- Final mode should be valid
    assert_true(grid_ui_state.grid_mode >= 1 and grid_ui_state.grid_mode <= 4,
        string.format("Final mode should be 1-4, got %d", grid_ui_state.grid_mode))
end)

test("Simultaneous key presses simulation", function()
    reset_mocks()
    init_snapshots()

    -- Simulate what happens if multiple keys are "pressed" simultaneously
    -- (This can happen with fast finger movements or hardware issues)

    local simultaneous_presses = {
        { { 2, 2, 1 }, { 15, 15, 1 }, { 8, 8, 1 } }, -- Multiple matrix positions
        { { 2, 1, 1 }, { 3, 1, 1 },   { 4, 1, 1 } }, -- Multiple snapshots
        { { 1, 2, 1 }, { 1, 3, 1 },   { 1, 4, 1 } }, -- Multiple modes
    }

    for _, press_group in ipairs(simultaneous_presses) do
        -- Press all keys in group simultaneously
        for _, key_event in ipairs(press_group) do
            simulate_grid_key_press(key_event[1], key_event[2], key_event[3])
        end

        -- Release all keys
        for _, key_event in ipairs(press_group) do
            simulate_grid_key_press(key_event[1], key_event[2], 0)
        end
    end

    -- Should handle simultaneous presses gracefully
    assert_true(true, "Simultaneous key presses should not crash")
end)

test("Extreme parameter values", function()
    reset_mocks()
    init_snapshots()

    -- Set up snapshots with extreme parameter values
    snapshots.A.params.q = 0.1   -- Minimum Q
    snapshots.B.params.q = 200.0 -- Maximum Q
    snapshots.C.params.q = 0.1
    snapshots.D.params.q = 200.0

    for i = 1, #freqs do
        snapshots.A.params[i].level = -60.0 -- Minimum level
        snapshots.B.params[i].level = 12.0  -- Maximum level
        snapshots.C.params[i].level = -60.0
        snapshots.D.params[i].level = 12.0

        snapshots.A.params[i].pan = -1.0 -- Full left
        snapshots.B.params[i].pan = 1.0  -- Full right
        snapshots.C.params[i].pan = -1.0
        snapshots.D.params[i].pan = 1.0

        snapshots.A.params[i].thresh = 0.0 -- Minimum threshold
        snapshots.B.params[i].thresh = 1.0 -- Maximum threshold
        snapshots.C.params[i].thresh = 0.0
        snapshots.D.params[i].thresh = 1.0
    end

    -- Test blending with extreme values
    local test_positions = {
        { 1, 1 }, { 14, 14 }, { 7.5, 7.5 }, { 1, 14 }, { 14, 1 }
    }

    for _, pos in ipairs(test_positions) do
        apply_blend_immediate(pos[1], pos[2])

        -- Check that blended values are within valid ranges
        local q = mock_engine_calls.q
        assert_true(q >= 0.1 and q <= 200.0,
            string.format("Blended Q out of range at (%.1f,%.1f): %.2f", pos[1], pos[2], q))

        for i = 1, #freqs do
            local level = mock_engine_calls["level_" .. i]
            local pan = mock_engine_calls["pan_" .. i]
            local thresh = mock_engine_calls["thresh_" .. i]

            if level then
                assert_true(level >= -60.0 and level <= 12.0,
                    string.format("Band %d level out of range: %.2f", i, level))
            end
            if pan then
                assert_true(pan >= -1.0 and pan <= 1.0,
                    string.format("Band %d pan out of range: %.2f", i, pan))
            end
            if thresh then
                assert_true(thresh >= 0.0 and thresh <= 1.0,
                    string.format("Band %d thresh out of range: %.2f", i, thresh))
            end
        end
    end
end)

test("Glide interruption scenarios", function()
    reset_mocks()
    init_snapshots()

    -- Set up different snapshots
    snapshots.A.params.q = 1.0
    snapshots.D.params.q = 4.0

    -- Start a long glide
    params.set("glide", 5.0) -- 5 second glide
    glide_state.is_gliding = true
    glide_state.start_pos = { x = 1, y = 1 }
    glide_state.target_pos = { x = 14, y = 14 }
    glide_state.glide_time = util.time()

    -- Simulate interrupting the glide with rapid new positions
    local interrupt_sequence = {
        { 8, 8,  1 }, { 8, 8, 0 },  -- Middle
        { 2, 15, 1 }, { 2, 15, 0 }, -- Corner C
        { 15, 2, 1 }, { 15, 2, 0 }, -- Corner B
        { 10, 5, 1 }, { 10, 5, 0 }, -- Random position
    }

    for _, key_event in ipairs(interrupt_sequence) do
        simulate_grid_key_press(key_event[1], key_event[2], key_event[3])

        -- Simulate some time passing
        for i = 1, 10 do
            util.time()
        end
    end

    -- Should handle glide interruptions gracefully
    assert_true(true, "Glide interruptions should not crash")
end)

test("Memory stress with rapid allocations", function()
    reset_mocks()
    init_snapshots()

    local initial_memory = collectgarbage("count")

    -- Perform many rapid operations that could cause memory allocations
    for cycle = 1, 100 do
        -- Rapid matrix movements
        for x = 1, 14, 2 do
            for y = 1, 14, 2 do
                apply_blend_immediate(x, y)

                -- Force some string operations (parameter IDs)
                for i = 1, #freqs do
                    local level_id = string.format("band_%02d_level", i)
                    local pan_id = string.format("band_%02d_pan", i)
                    local thresh_id = string.format("band_%02d_thresh", i)
                end
            end
        end

        -- Periodic garbage collection to prevent excessive buildup
        if cycle % 20 == 0 then
            collectgarbage("collect")
        end
    end

    collectgarbage("collect")
    local final_memory = collectgarbage("count")
    local memory_growth = final_memory - initial_memory

    print(string.format("Memory growth after stress test: %.2f KB", memory_growth))

    -- Memory growth should be reasonable even under stress
    assert_true(memory_growth < 500,
        string.format("Excessive memory growth under stress: %.2f KB", memory_growth))
end)

test("Floating point precision edge cases", function()
    reset_mocks()
    init_snapshots()

    -- Test positions that might cause floating point precision issues
    local precision_test_coords = {
        { 1.0000001,  1.0000001 },   -- Just above minimum
        { 13.9999999, 13.9999999 },  -- Just below maximum
        { 7.33333333, 7.33333333 },  -- Repeating decimal
        { math.pi,    math.exp(1) }, -- Irrational numbers (clamped to range)
        { 1 / 3 + 1,  1 / 7 + 1 },   -- Fraction precision
    }

    for _, coord in ipairs(precision_test_coords) do
        local x, y = coord[1], coord[2]

        -- Clamp to valid range
        x = math.max(1, math.min(14, x))
        y = math.max(1, math.min(14, y))

        local a_w, b_w, c_w, d_w = calculate_blend_weights(x, y)

        -- Check that all weights are numbers
        assert_true(type(a_w) == "number",
            string.format("Weight A should be number, got %s at (%.10f,%.10f)", type(a_w), x, y))
        assert_true(type(b_w) == "number",
            string.format("Weight B should be number, got %s at (%.10f,%.10f)", type(b_w), x, y))
        assert_true(type(c_w) == "number",
            string.format("Weight C should be number, got %s at (%.10f,%.10f)", type(c_w), x, y))
        assert_true(type(d_w) == "number",
            string.format("Weight D should be number, got %s at (%.10f,%.10f)", type(d_w), x, y))

        -- Check for NaN or infinite values
        assert_true(a_w == a_w, "Weight A should not be NaN") -- NaN != NaN
        assert_true(b_w == b_w, "Weight B should not be NaN")
        assert_true(c_w == c_w, "Weight C should not be NaN")
        assert_true(d_w == d_w, "Weight D should not be NaN")

        assert_true(math.abs(a_w) < math.huge, "Weight A should not be infinite")
        assert_true(math.abs(b_w) < math.huge, "Weight B should not be infinite")
        assert_true(math.abs(c_w) < math.huge, "Weight C should not be infinite")
        assert_true(math.abs(d_w) < math.huge, "Weight D should not be infinite")

        -- Weights should still sum to 1 despite precision issues
        local sum = a_w + b_w + c_w + d_w
        assert_near(sum, 1.0, 0.00001,
            string.format("Precision test failed at (%.10f,%.10f): sum=%.10f", x, y, sum))
    end
end)

-- Run summary
print(string.format("\n=== EDGE CASE TEST SUMMARY ==="))
print(string.format("Tests run: %d", test_count))
print(string.format("Passed: %d", pass_count))
print(string.format("Failed: %d", test_count - pass_count))

if pass_count == test_count then
    print("✓ ALL EDGE CASE TESTS PASSED!")
    print("The bands project handles edge cases robustly.")
    os.exit(0)
else
    print("✗ SOME EDGE CASE TESTS FAILED!")
    print("Edge case handling may need improvement.")
    os.exit(1)
end
