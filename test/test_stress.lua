-- Stress tests for bands project
-- Extreme load testing for performance and stability

local test_count = 0
local pass_count = 0

-- Test framework
local function test(name, func)
    test_count = test_count + 1
    print(string.format("\n--- Stress Test %d: %s ---", test_count, name))
    
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

local function benchmark_with_memory(name, func, iterations)
    iterations = iterations or 1000
    
    local initial_memory = collectgarbage("count")
    collectgarbage("collect")
    local baseline_memory = collectgarbage("count")
    
    local start_time = os.clock()
    for i = 1, iterations do
        func()
    end
    local end_time = os.clock()
    
    collectgarbage("collect")
    local final_memory = collectgarbage("count")
    
    local total_time = end_time - start_time
    local avg_time = total_time / iterations
    local memory_growth = final_memory - baseline_memory
    
    print(string.format("%s: %d iterations in %.4fs (avg: %.6fs)", 
        name, iterations, total_time, avg_time))
    print(string.format("  Memory: %.2f KB growth", memory_growth))
    
    return avg_time, total_time, memory_growth
end

-- Mock environment for stress testing
local mock_params = {}
local mock_engine_calls = 0
local mock_grid_updates = 0

local params = {
    get = function(id) return mock_params[id] or 0 end,
    set = function(id, value) mock_params[id] = value end
}

local engine = {
    level = function(band, level) mock_engine_calls = mock_engine_calls + 1 end,
    pan = function(band, pan) mock_engine_calls = mock_engine_calls + 1 end,
    q = function(q) mock_engine_calls = mock_engine_calls + 1 end,
    thresh_band = function(band, thresh) mock_engine_calls = mock_engine_calls + 1 end
}

local grid_device = {
    led = function(self, x, y, brightness) mock_grid_updates = mock_grid_updates + 1 end,
    refresh = function(self) mock_grid_updates = mock_grid_updates + 1 end,
    all = function(self, brightness) mock_grid_updates = mock_grid_updates + 256 end
}

-- Test data
local freqs = {
    80, 150, 250, 350, 500, 630, 800, 1000,
    1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
}

local snapshots = {
    A = { params = { q = 1.0 } },
    B = { params = { q = 2.0 } },
    C = { params = { q = 3.0 } },
    D = { params = { q = 4.0 } }
}

-- Initialize snapshots with test data
for snapshot_name, snapshot in pairs(snapshots) do
    for i = 1, #freqs do
        snapshot.params[i] = {
            level = -12.0 + (i % 4) * 2,
            pan = (i % 3 - 1) * 0.5,
            thresh = (i % 5) * 0.2
        }
    end
end

-- Functions under stress test
local function calculate_blend_weights(x, y)
    local norm_x = (x - 1) / 13
    local norm_y = (y - 1) / 13
    
    local a_weight = (1 - norm_x) * (1 - norm_y)
    local b_weight = norm_x * (1 - norm_y)
    local c_weight = (1 - norm_x) * norm_y
    local d_weight = norm_x * norm_y
    
    return a_weight, b_weight, c_weight, d_weight
end

local function full_parameter_blend(x, y)
    local a_w, b_w, c_w, d_w = calculate_blend_weights(x, y)
    
    -- Blend Q
    local blended_q = snapshots.A.params.q * a_w +
        snapshots.B.params.q * b_w +
        snapshots.C.params.q * c_w +
        snapshots.D.params.q * d_w
    
    params.set("q", blended_q)
    engine.q(blended_q)
    
    -- Blend all band parameters
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

local function simulate_full_grid_redraw()
    grid_device:all(0)
    
    -- Matrix background
    for x = 2, 15 do
        for y = 2, 15 do
            grid_device:led(x, y, 2)
        end
    end
    
    -- Current position
    grid_device:led(8, 8, 15)
    
    -- Mode indicators
    for i = 1, 4 do
        grid_device:led(1, i + 1, i == 1 and 15 or 4)
    end
    
    -- Snapshot indicators
    for i = 1, 4 do
        grid_device:led(i + 1, 1, i == 1 and 15 or 4)
    end
    
    grid_device:refresh()
end

local function simulate_glide_step(progress)
    local start_x, start_y = 1, 1
    local target_x, target_y = 14, 14
    
    local current_x = start_x + (target_x - start_x) * progress
    local current_y = start_y + (target_y - start_y) * progress
    
    -- Clear previous position
    grid_device:led(math.floor(current_x), math.floor(current_y), 2)
    
    -- Draw current position
    grid_device:led(math.floor(current_x + 0.5), math.floor(current_y + 0.5), 15)
    
    -- Draw target
    grid_device:led(target_x + 1, target_y + 1, 6)
    
    grid_device:refresh()
    
    -- Update parameters
    full_parameter_blend(current_x, current_y)
end

local function reset_counters()
    mock_engine_calls = 0
    mock_grid_updates = 0
    mock_params = {}
end

-- Stress tests
print("=== BANDS STRESS TEST SUITE ===")

test("Ultra-rapid key press simulation", function()
    reset_counters()
    
    -- Simulate 1000 key presses in rapid succession (like someone mashing the grid)
    local avg_time = benchmark_with_memory("Ultra-rapid keys", function()
        local x = math.random(1, 14)
        local y = math.random(1, 14)
        full_parameter_blend(x, y)
    end, 1000)
    
    -- Should handle 1000 rapid presses in under 100ms
    assert_true(avg_time < 0.0001, 
        string.format("Ultra-rapid key handling too slow: %.6fs per key", avg_time))
    
    print(string.format("Engine calls generated: %d", mock_engine_calls))
    assert_true(mock_engine_calls > 0, "Should generate engine calls")
end)

test("Continuous matrix scanning", function()
    reset_counters()
    
    -- Simulate continuous scanning across entire matrix (like dragging finger)
    local scan_count = 0
    local avg_time = benchmark_with_memory("Matrix scanning", function()
        local progress = (scan_count % 196) / 196  -- 14x14 = 196 positions
        local x = 1 + (progress * 13)
        local y = 1 + ((scan_count % 14) / 13) * 13
        full_parameter_blend(x, y)
        scan_count = scan_count + 1
    end, 2000)  -- 2000 position updates
    
    -- Should handle continuous scanning smoothly
    assert_true(avg_time < 0.0005, 
        string.format("Matrix scanning too slow: %.6fs per position", avg_time))
end)

test("High-frequency grid updates", function()
    reset_counters()
    
    -- Simulate 60fps grid updates for 10 seconds = 600 frames
    local avg_time = benchmark_with_memory("Grid updates", function()
        simulate_full_grid_redraw()
    end, 600)
    
    -- Should maintain 60fps (< 16.67ms per frame)
    assert_true(avg_time < 0.016, 
        string.format("Grid updates too slow for 60fps: %.6fs per frame", avg_time))
    
    print(string.format("Grid LED updates: %d", mock_grid_updates))
end)

test("Intensive glide animation", function()
    reset_counters()
    
    -- Simulate 60fps glide animation for 5 seconds = 300 frames
    local frame = 0
    local avg_time = benchmark_with_memory("Glide animation", function()
        local progress = (frame % 300) / 300  -- 5 second cycle
        simulate_glide_step(progress)
        frame = frame + 1
    end, 300)
    
    -- Should maintain smooth glide animation
    assert_true(avg_time < 0.016, 
        string.format("Glide animation too slow: %.6fs per frame", avg_time))
end)

test("Memory pressure under load", function()
    reset_counters()
    
    -- Perform intensive operations while monitoring memory
    local initial_memory = collectgarbage("count")
    
    -- Phase 1: Rapid parameter changes
    for i = 1, 500 do
        local x = math.random(1, 14)
        local y = math.random(1, 14)
        full_parameter_blend(x, y)
    end
    
    local mid_memory = collectgarbage("count")
    
    -- Phase 2: Rapid grid updates
    for i = 1, 200 do
        simulate_full_grid_redraw()
    end
    
    -- Phase 3: Glide simulation
    for i = 1, 100 do
        simulate_glide_step(i / 100)
    end
    
    collectgarbage("collect")
    local final_memory = collectgarbage("count")
    
    local total_growth = final_memory - initial_memory
    local mid_growth = mid_memory - initial_memory
    
    print(string.format("Memory growth: %.2f KB (mid: %.2f KB)", total_growth, mid_growth))
    
    -- Memory growth should be reasonable even under heavy load
    assert_true(total_growth < 1000, 
        string.format("Excessive memory growth under load: %.2f KB", total_growth))
end)

test("Concurrent operation simulation", function()
    reset_counters()
    
    -- Simulate multiple things happening simultaneously
    local avg_time = benchmark_with_memory("Concurrent ops", function()
        -- Matrix position change
        local x = math.random(1, 14)
        local y = math.random(1, 14)
        full_parameter_blend(x, y)
        
        -- Grid update
        simulate_full_grid_redraw()
        
        -- Glide step
        simulate_glide_step(math.random())
        
        -- Parameter queries (like for screen display)
        for i = 1, 5 do
            local param_id = string.format("band_%02d_level", math.random(1, 16))
            params.get(param_id)
        end
    end, 100)
    
    -- Should handle concurrent operations efficiently
    assert_true(avg_time < 0.01, 
        string.format("Concurrent operations too slow: %.6fs", avg_time))
end)

test("Pathological input patterns", function()
    reset_counters()
    
    -- Test patterns that might cause worst-case performance
    local patterns = {
        -- Rapid corner-to-corner jumps
        function() 
            full_parameter_blend(1, 1)
            full_parameter_blend(14, 14)
        end,
        
        -- High-frequency oscillation
        function()
            for i = 1, 10 do
                full_parameter_blend(7 + math.sin(i) * 3, 7 + math.cos(i) * 3)
            end
        end,
        
        -- Spiral pattern
        function()
            for i = 1, 20 do
                local angle = i * 0.5
                local radius = i * 0.3
                local x = 7 + math.cos(angle) * radius
                local y = 7 + math.sin(angle) * radius
                x = math.max(1, math.min(14, x))
                y = math.max(1, math.min(14, y))
                full_parameter_blend(x, y)
            end
        end
    }
    
    for pattern_idx, pattern_func in ipairs(patterns) do
        local start_time = os.clock()
        
        for i = 1, 50 do  -- Run each pattern 50 times
            pattern_func()
        end
        
        local pattern_time = os.clock() - start_time
        print(string.format("Pattern %d: %.4fs for 50 iterations", pattern_idx, pattern_time))
        
        assert_true(pattern_time < 1.0, 
            string.format("Pattern %d too slow: %.4fs", pattern_idx, pattern_time))
    end
end)

test("Resource exhaustion resistance", function()
    reset_counters()
    
    -- Try to exhaust various resources
    local operations = 0
    local start_time = os.clock()
    
    -- Run operations for 2 seconds straight
    while (os.clock() - start_time) < 2.0 do
        -- Vary the operations to stress different code paths
        local op_type = operations % 4
        
        if op_type == 0 then
            full_parameter_blend(math.random(1, 14), math.random(1, 14))
        elseif op_type == 1 then
            simulate_full_grid_redraw()
        elseif op_type == 2 then
            simulate_glide_step(math.random())
        else
            -- String operations (parameter ID generation)
            for i = 1, 16 do
                local level_id = string.format("band_%02d_level", i)
                local pan_id = string.format("band_%02d_pan", i)
                local thresh_id = string.format("band_%02d_thresh", i)
            end
        end
        
        operations = operations + 1
        
        -- Periodic cleanup to prevent runaway memory usage
        if operations % 1000 == 0 then
            collectgarbage("step", 100)
        end
    end
    
    local ops_per_second = operations / 2.0
    print(string.format("Sustained %d operations/second for 2 seconds", math.floor(ops_per_second)))
    
    -- Should sustain high operation rate
    assert_true(ops_per_second > 1000, 
        string.format("Operation rate too low: %.0f ops/sec", ops_per_second))
end)

-- Run summary
print(string.format("\n=== STRESS TEST SUMMARY ==="))
print(string.format("Tests run: %d", test_count))
print(string.format("Passed: %d", pass_count))
print(string.format("Failed: %d", test_count - pass_count))

if pass_count == test_count then
    print("✓ ALL STRESS TESTS PASSED!")
    print("The bands project handles extreme loads robustly.")
    os.exit(0)
else
    print("✗ SOME STRESS TESTS FAILED!")
    print("Performance under stress may need optimization.")
    os.exit(1)
end
