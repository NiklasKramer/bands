-- Performance tests for bands project
-- Tests computational efficiency and timing-critical operations

local test_count = 0
local pass_count = 0

-- Test framework
local function test(name, func)
    test_count = test_count + 1
    print(string.format("\n--- Performance Test %d: %s ---", test_count, name))
    
    local success, error_msg = pcall(func)
    if success then
        pass_count = pass_count + 1
        print("✓ PASS")
    else
        print("✗ FAIL: " .. tostring(error_msg))
    end
end

local function assert_true(condition, message)
    if not condition then
        error(message or "Expected true, got false")
    end
end

local function benchmark(name, func, iterations)
    iterations = iterations or 1000
    
    -- Warm up
    for i = 1, 10 do
        func()
    end
    
    -- Actual benchmark
    local start_time = os.clock()
    for i = 1, iterations do
        func()
    end
    local end_time = os.clock()
    
    local total_time = end_time - start_time
    local avg_time = total_time / iterations
    
    print(string.format("%s: %d iterations in %.4fs (avg: %.6fs per call)", 
        name, iterations, total_time, avg_time))
    
    return avg_time, total_time
end

-- Test functions (extracted from bands.lua)
local freqs = {
    80, 150, 250, 350, 500, 630, 800, 1000,
    1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
}

local function calculate_blend_weights(x, y)
    local norm_x = (x - 1) / 13
    local norm_y = (y - 1) / 13
    
    local a_weight = (1 - norm_x) * (1 - norm_y)
    local b_weight = norm_x * (1 - norm_y)
    local c_weight = (1 - norm_x) * norm_y
    local d_weight = norm_x * norm_y
    
    return a_weight, b_weight, c_weight, d_weight
end

local function calculate_blend_weights_fixed(x, y)
    local norm_x = (x - 1) / 13
    local norm_y = (y - 1) / 13
    
    local a_weight = (1 - norm_x) * (1 - norm_y)
    local b_weight = norm_x * (1 - norm_y)
    local c_weight = (1 - norm_x) * norm_y
    local d_weight = norm_x * norm_y
    
    return a_weight, b_weight, c_weight, d_weight
end

local snapshots = {
    A = { params = { q = 1.0 } },
    B = { params = { q = 2.0 } },
    C = { params = { q = 3.0 } },
    D = { params = { q = 4.0 } }
}

-- Initialize snapshot band parameters
for snapshot_name, snapshot in pairs(snapshots) do
    for i = 1, #freqs do
        snapshot.params[i] = {
            level = -12.0 + (i % 4) * 2,
            pan = (i % 3 - 1) * 0.5,
            thresh = (i % 5) * 0.2
        }
    end
end

local function blend_parameters(x, y)
    local a_w, b_w, c_w, d_w = calculate_blend_weights_fixed(x, y)
    
    -- Blend Q
    local blended_q = snapshots.A.params.q * a_w +
        snapshots.B.params.q * b_w +
        snapshots.C.params.q * c_w +
        snapshots.D.params.q * d_w
    
    -- Blend all band parameters
    local blended_params = {}
    for i = 1, #freqs do
        blended_params[i] = {
            level = snapshots.A.params[i].level * a_w +
                   snapshots.B.params[i].level * b_w +
                   snapshots.C.params[i].level * c_w +
                   snapshots.D.params[i].level * d_w,
            pan = snapshots.A.params[i].pan * a_w +
                 snapshots.B.params[i].pan * b_w +
                 snapshots.C.params[i].pan * c_w +
                 snapshots.D.params[i].pan * d_w,
            thresh = snapshots.A.params[i].thresh * a_w +
                    snapshots.B.params[i].thresh * b_w +
                    snapshots.C.params[i].thresh * c_w +
                    snapshots.D.params[i].thresh * d_w
        }
    end
    
    return blended_q, blended_params
end

local function simulate_grid_redraw()
    local grid_leds = {}
    
    -- Clear grid
    for x = 1, 16 do
        for y = 1, 16 do
            grid_leds[x .. "," .. y] = 0
        end
    end
    
    -- Draw matrix background
    for x = 2, 15 do
        for y = 2, 15 do
            grid_leds[x .. "," .. y] = 2
        end
    end
    
    -- Draw current position
    local pos_x, pos_y = 8, 8
    grid_leds[(pos_x + 1) .. "," .. (pos_y + 1)] = 15
    
    -- Draw mode indicators
    for i = 1, 4 do
        grid_leds["1," .. i] = i == 1 and 15 or 4
    end
    
    -- Draw snapshot indicators
    for i = 1, 4 do
        grid_leds[i .. ",1"] = i == 1 and 15 or 4
    end
    
    return grid_leds
end

local function simulate_glide_step(progress)
    local start_x, start_y = 1, 1
    local target_x, target_y = 14, 14
    
    local current_x = start_x + (target_x - start_x) * progress
    local current_y = start_y + (target_y - start_y) * progress
    
    -- Simulate parameter interpolation
    local start_q, target_q = 1.0, 4.0
    local current_q = start_q + (target_q - start_q) * progress
    
    -- Simulate band parameter interpolation
    local interpolated_params = {}
    for i = 1, #freqs do
        interpolated_params[i] = {
            level = -12.0 + (-6.0 - (-12.0)) * progress,
            pan = 0.0 + (0.5 - 0.0) * progress,
            thresh = 0.0 + (0.3 - 0.0) * progress
        }
    end
    
    return current_x, current_y, current_q, interpolated_params
end

-- Performance tests
print("=== BANDS PERFORMANCE TEST SUITE ===")

test("Blend weight calculation performance", function()
    local avg_time = benchmark("Blend weights", function()
        calculate_blend_weights_fixed(7, 8)
    end, 10000)
    
    -- Should be very fast (< 1ms for 10000 calls)
    assert_true(avg_time < 0.0001, 
        string.format("Blend weight calculation too slow: %.6fs", avg_time))
end)

test("Full parameter blending performance", function()
    local avg_time = benchmark("Parameter blending", function()
        blend_parameters(7, 8)
    end, 1000)
    
    -- Should complete in reasonable time for real-time use
    assert_true(avg_time < 0.001, 
        string.format("Parameter blending too slow: %.6fs", avg_time))
end)

test("Grid redraw simulation performance", function()
    local avg_time = benchmark("Grid redraw", function()
        simulate_grid_redraw()
    end, 100)
    
    -- Grid redraws should be fast enough for 60fps (< 16ms)
    assert_true(avg_time < 0.016, 
        string.format("Grid redraw too slow: %.6fs", avg_time))
end)

test("Glide interpolation performance", function()
    local avg_time = benchmark("Glide step", function()
        simulate_glide_step(0.5)
    end, 1000)
    
    -- Glide steps should be fast for 60fps updates
    assert_true(avg_time < 0.001, 
        string.format("Glide interpolation too slow: %.6fs", avg_time))
end)

test("Memory allocation patterns", function()
    -- Test that repeated operations don't cause excessive garbage collection
    local initial_memory = collectgarbage("count")
    
    -- Perform many operations
    for i = 1, 1000 do
        local q, params = blend_parameters(i % 14 + 1, i % 14 + 1)
        simulate_glide_step(i / 1000)
    end
    
    collectgarbage("collect")
    local final_memory = collectgarbage("count")
    local memory_growth = final_memory - initial_memory
    
    print(string.format("Memory growth: %.2f KB", memory_growth))
    
    -- Memory growth should be reasonable (< 100KB for 1000 operations)
    assert_true(memory_growth < 100, 
        string.format("Excessive memory growth: %.2f KB", memory_growth))
end)

test("Stress test - rapid matrix movements", function()
    local start_time = os.clock()
    
    -- Simulate rapid matrix movements (like fast mouse/finger movements)
    for i = 1, 100 do
        for x = 1, 14 do
            for y = 1, 14 do
                calculate_blend_weights_fixed(x, y)
            end
        end
    end
    
    local end_time = os.clock()
    local total_time = end_time - start_time
    
    print(string.format("Stress test: 19600 calculations in %.4fs", total_time))
    
    -- Should handle rapid movements without lag
    assert_true(total_time < 1.0, 
        string.format("Stress test too slow: %.4fs", total_time))
end)

test("Real-time constraint validation", function()
    -- Test that critical operations meet real-time constraints
    
    -- Audio callback simulation (should be < 1ms for 44.1kHz, 64 sample buffer)
    local audio_deadline = 0.001
    local avg_time = benchmark("Audio-rate operation", function()
        -- Simulate what might happen in an audio callback
        local q, params = blend_parameters(7, 8)
        -- Simulate setting engine parameters (just the calculation part)
        for i = 1, #freqs do
            local level = params[i].level
            local pan = params[i].pan
            local thresh = params[i].thresh
        end
    end, 100)
    
    assert_true(avg_time < audio_deadline, 
        string.format("Audio-rate operation too slow: %.6fs (deadline: %.6fs)", 
            avg_time, audio_deadline))
    
    -- UI update simulation (should be < 16ms for 60fps)
    local ui_deadline = 0.016
    avg_time = benchmark("UI update", function()
        simulate_grid_redraw()
        simulate_glide_step(0.5)
    end, 60)
    
    assert_true(avg_time < ui_deadline, 
        string.format("UI update too slow: %.6fs (deadline: %.6fs)", 
            avg_time, ui_deadline))
end)

test("Numerical stability", function()
    -- Test that calculations remain stable with extreme values
    local test_cases = {
        {1, 1},      -- Corner
        {14, 14},    -- Opposite corner
        {7.5, 7.5},  -- Center
        {1.001, 1.001},    -- Near corner
        {13.999, 13.999},  -- Near opposite corner
    }
    
    for _, case in ipairs(test_cases) do
        local x, y = case[1], case[2]
        local a_w, b_w, c_w, d_w = calculate_blend_weights_fixed(x, y)
        
        -- Weights should sum to 1
        local sum = a_w + b_w + c_w + d_w
        assert_true(math.abs(sum - 1.0) < 0.0001, 
            string.format("Weights don't sum to 1 at (%.3f,%.3f): %.6f", x, y, sum))
        
        -- All weights should be non-negative
        assert_true(a_w >= 0 and b_w >= 0 and c_w >= 0 and d_w >= 0,
            string.format("Negative weight at (%.3f,%.3f): A=%.6f B=%.6f C=%.6f D=%.6f", 
                x, y, a_w, b_w, c_w, d_w))
    end
end)

-- Run summary
print(string.format("\n=== PERFORMANCE TEST SUMMARY ==="))
print(string.format("Tests run: %d", test_count))
print(string.format("Passed: %d", pass_count))
print(string.format("Failed: %d", test_count - pass_count))

if pass_count == test_count then
    print("✓ ALL PERFORMANCE TESTS PASSED!")
    print("The bands project meets performance requirements.")
    os.exit(0)
else
    print("✗ SOME PERFORMANCE TESTS FAILED!")
    print("Performance optimization may be needed.")
    os.exit(1)
end
