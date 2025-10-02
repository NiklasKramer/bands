-- Test suite for bands project
-- Run with: lua test/test_bands.lua

local test_count = 0
local pass_count = 0

-- Simple test framework
local function test(name, func)
    test_count = test_count + 1
    print(string.format("\n--- Test %d: %s ---", test_count, name))
    
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

-- Mock Norns environment for testing
local mock_params = {}
local mock_engine = {}

local params = {
    get = function(id) return mock_params[id] or 0 end,
    set = function(id, value) mock_params[id] = value end
}

local engine = {
    level = function(band, level) mock_engine["level_" .. band] = level end,
    pan = function(band, pan) mock_engine["pan_" .. band] = pan end,
    q = function(q) mock_engine.q = q end,
    thresh_band = function(band, thresh) mock_engine["thresh_" .. band] = thresh end
}

-- Load the functions we want to test
-- We'll extract key functions from bands.lua for testing

-- Test data
local freqs = {
    80, 150, 250, 350, 500, 630, 800, 1000,
    1300, 1600, 2000, 2600, 3500, 5000, 8000, 12000
}

-- Snapshot system (extracted from bands.lua)
local snapshots = {
    A = { name = "Snapshot A", params = {} },
    B = { name = "Snapshot B", params = {} },
    C = { name = "Snapshot C", params = {} },
    D = { name = "Snapshot D", params = {} }
}

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

local function calculate_blend_weights(x, y)
    -- Normalize coordinates to 0-1 range (grid is 1-14, so subtract 1 and divide by 13)
    local norm_x = (x - 1) / 13
    local norm_y = (y - 1) / 13
    
    -- Bilinear interpolation weights
    local a_weight = (1 - norm_x) * (1 - norm_y)  -- Top-left (A)
    local b_weight = norm_x * (1 - norm_y)         -- Top-right (B)
    local c_weight = (1 - norm_x) * norm_y         -- Bottom-left (C)
    local d_weight = norm_x * norm_y               -- Bottom-right (D)
    
    return a_weight, b_weight, c_weight, d_weight
end

-- Grid coordinate validation
local function is_valid_grid_coord(x, y)
    return x >= 1 and x <= 14 and y >= 1 and y <= 14
end

-- Parameter validation
local function is_valid_level(level)
    return level >= -60 and level <= 12
end

local function is_valid_pan(pan)
    return pan >= -1 and pan <= 1
end

local function is_valid_q(q)
    return q >= 0.1 and q <= 200
end

local function is_valid_thresh(thresh)
    return thresh >= 0 and thresh <= 1
end

-- Tests start here
print("=== BANDS PROJECT TEST SUITE ===")

test("Snapshot initialization", function()
    init_snapshots()
    
    -- Check all snapshots exist
    assert_true(snapshots.A ~= nil, "Snapshot A should exist")
    assert_true(snapshots.B ~= nil, "Snapshot B should exist")
    assert_true(snapshots.C ~= nil, "Snapshot C should exist")
    assert_true(snapshots.D ~= nil, "Snapshot D should exist")
    
    -- Check default values
    assert_equal(snapshots.A.params.q, 1.1, "Snapshot A Q should be 1.1")
    assert_equal(snapshots.A.params[1].level, -12.0, "Snapshot A band 1 level should be -12.0")
    assert_equal(snapshots.A.params[1].pan, 0.0, "Snapshot A band 1 pan should be 0.0")
    assert_equal(snapshots.A.params[1].thresh, 0.0, "Snapshot A band 1 thresh should be 0.0")
    
    -- Check all snapshots have identical default values
    for i = 1, #freqs do
        assert_equal(snapshots.A.params[i].level, snapshots.B.params[i].level, 
            "All snapshots should have identical default levels")
        assert_equal(snapshots.A.params[i].pan, snapshots.B.params[i].pan, 
            "All snapshots should have identical default pans")
        assert_equal(snapshots.A.params[i].thresh, snapshots.B.params[i].thresh, 
            "All snapshots should have identical default thresholds")
    end
end)

test("Blend weight calculation - corners", function()
    -- Test corner positions (extreme cases)
    local a_w, b_w, c_w, d_w
    
    -- Top-left corner (1,1) should be 100% A
    a_w, b_w, c_w, d_w = calculate_blend_weights(1, 1)
    assert_near(a_w, 1.0, 0.001, "Top-left should be 100% A")
    assert_near(b_w, 0.0, 0.001, "Top-left should be 0% B")
    assert_near(c_w, 0.0, 0.001, "Top-left should be 0% C")
    assert_near(d_w, 0.0, 0.001, "Top-left should be 0% D")
    
    -- Top-right corner (14,1) should be 100% B
    a_w, b_w, c_w, d_w = calculate_blend_weights(14, 1)
    assert_near(a_w, 0.0, 0.001, "Top-right should be 0% A")
    assert_near(b_w, 1.0, 0.001, "Top-right should be 100% B")
    assert_near(c_w, 0.0, 0.001, "Top-right should be 0% C")
    assert_near(d_w, 0.0, 0.001, "Top-right should be 0% D")
    
    -- Bottom-left corner (1,14) should be 100% C
    a_w, b_w, c_w, d_w = calculate_blend_weights(1, 14)
    assert_near(a_w, 0.0, 0.001, "Bottom-left should be 0% A")
    assert_near(b_w, 0.0, 0.001, "Bottom-left should be 0% B")
    assert_near(c_w, 1.0, 0.001, "Bottom-left should be 100% C")
    assert_near(d_w, 0.0, 0.001, "Bottom-left should be 0% D")
    
    -- Bottom-right corner (14,14) should be 100% D
    a_w, b_w, c_w, d_w = calculate_blend_weights(14, 14)
    assert_near(a_w, 0.0, 0.001, "Bottom-right should be 0% A")
    assert_near(b_w, 0.0, 0.001, "Bottom-right should be 0% B")
    assert_near(c_w, 0.0, 0.001, "Bottom-right should be 0% C")
    assert_near(d_w, 1.0, 0.001, "Bottom-right should be 100% D")
end)

test("Blend weight calculation - center", function()
    -- Test center position (7.5, 7.5) should be 25% each
    local a_w, b_w, c_w, d_w = calculate_blend_weights(7.5, 7.5)
    assert_near(a_w, 0.25, 0.001, "Center should be 25% A")
    assert_near(b_w, 0.25, 0.001, "Center should be 25% B")
    assert_near(c_w, 0.25, 0.001, "Center should be 25% C")
    assert_near(d_w, 0.25, 0.001, "Center should be 25% D")
    
    -- Weights should sum to 1
    assert_near(a_w + b_w + c_w + d_w, 1.0, 0.001, "Weights should sum to 1")
end)

test("Blend weight calculation - edges", function()
    -- Test edge positions
    local a_w, b_w, c_w, d_w
    
    -- Top edge (7.5, 1) should be 50% A, 50% B
    a_w, b_w, c_w, d_w = calculate_blend_weights(7.5, 1)
    assert_near(a_w, 0.5, 0.001, "Top edge should be 50% A")
    assert_near(b_w, 0.5, 0.001, "Top edge should be 50% B")
    assert_near(c_w, 0.0, 0.001, "Top edge should be 0% C")
    assert_near(d_w, 0.0, 0.001, "Top edge should be 0% D")
    
    -- Left edge (1, 7.5) should be 50% A, 50% C
    a_w, b_w, c_w, d_w = calculate_blend_weights(1, 7.5)
    assert_near(a_w, 0.5, 0.001, "Left edge should be 50% A")
    assert_near(b_w, 0.0, 0.001, "Left edge should be 0% B")
    assert_near(c_w, 0.5, 0.001, "Left edge should be 50% C")
    assert_near(d_w, 0.0, 0.001, "Left edge should be 0% D")
end)

test("Grid coordinate validation", function()
    -- Valid coordinates
    assert_true(is_valid_grid_coord(1, 1), "1,1 should be valid")
    assert_true(is_valid_grid_coord(14, 14), "14,14 should be valid")
    assert_true(is_valid_grid_coord(7, 8), "7,8 should be valid")
    
    -- Invalid coordinates
    assert_true(not is_valid_grid_coord(0, 1), "0,1 should be invalid")
    assert_true(not is_valid_grid_coord(15, 1), "15,1 should be invalid")
    assert_true(not is_valid_grid_coord(1, 0), "1,0 should be invalid")
    assert_true(not is_valid_grid_coord(1, 15), "1,15 should be invalid")
end)

test("Parameter validation", function()
    -- Level validation
    assert_true(is_valid_level(-12.0), "-12dB should be valid level")
    assert_true(is_valid_level(0.0), "0dB should be valid level")
    assert_true(is_valid_level(12.0), "12dB should be valid level")
    assert_true(not is_valid_level(-61.0), "-61dB should be invalid level")
    assert_true(not is_valid_level(13.0), "13dB should be invalid level")
    
    -- Pan validation
    assert_true(is_valid_pan(0.0), "0.0 should be valid pan")
    assert_true(is_valid_pan(-1.0), "-1.0 should be valid pan")
    assert_true(is_valid_pan(1.0), "1.0 should be valid pan")
    assert_true(not is_valid_pan(-1.1), "-1.1 should be invalid pan")
    assert_true(not is_valid_pan(1.1), "1.1 should be invalid pan")
    
    -- Q validation
    assert_true(is_valid_q(1.1), "1.1 should be valid Q")
    assert_true(is_valid_q(0.1), "0.1 should be valid Q")
    assert_true(is_valid_q(200.0), "200.0 should be valid Q")
    assert_true(not is_valid_q(0.05), "0.05 should be invalid Q")
    assert_true(not is_valid_q(201.0), "201.0 should be invalid Q")
    
    -- Threshold validation
    assert_true(is_valid_thresh(0.0), "0.0 should be valid threshold")
    assert_true(is_valid_thresh(0.5), "0.5 should be valid threshold")
    assert_true(is_valid_thresh(1.0), "1.0 should be valid threshold")
    assert_true(not is_valid_thresh(-0.1), "-0.1 should be invalid threshold")
    assert_true(not is_valid_thresh(1.1), "1.1 should be invalid threshold")
end)

test("Frequency array integrity", function()
    assert_equal(#freqs, 16, "Should have 16 frequency bands")
    assert_equal(freqs[1], 80, "First frequency should be 80Hz")
    assert_equal(freqs[16], 12000, "Last frequency should be 12000Hz")
    
    -- Check frequencies are in ascending order
    for i = 2, #freqs do
        assert_true(freqs[i] > freqs[i-1], 
            string.format("Frequency %d (%dHz) should be greater than frequency %d (%dHz)", 
                i, freqs[i], i-1, freqs[i-1]))
    end
end)

test("Snapshot data structure integrity", function()
    init_snapshots()
    
    for snapshot_name, snapshot in pairs(snapshots) do
        -- Check snapshot has required fields
        assert_true(snapshot.name ~= nil, snapshot_name .. " should have a name")
        assert_true(snapshot.params ~= nil, snapshot_name .. " should have params")
        assert_true(snapshot.params.q ~= nil, snapshot_name .. " should have Q parameter")
        
        -- Check all frequency bands have parameters
        for i = 1, #freqs do
            assert_true(snapshot.params[i] ~= nil, 
                snapshot_name .. " should have params for band " .. i)
            assert_true(snapshot.params[i].level ~= nil, 
                snapshot_name .. " band " .. i .. " should have level")
            assert_true(snapshot.params[i].pan ~= nil, 
                snapshot_name .. " band " .. i .. " should have pan")
            assert_true(snapshot.params[i].thresh ~= nil, 
                snapshot_name .. " band " .. i .. " should have thresh")
        end
    end
end)

test("Bilinear interpolation mathematical properties", function()
    -- Test that weights always sum to 1 for any valid position
    for x = 1, 14, 2 do
        for y = 1, 14, 2 do
            local a_w, b_w, c_w, d_w = calculate_blend_weights(x, y)
            local sum = a_w + b_w + c_w + d_w
            assert_near(sum, 1.0, 0.001, 
                string.format("Weights should sum to 1 at position (%d,%d)", x, y))
        end
    end
    
    -- Test that all weights are non-negative
    for x = 1, 14, 3 do
        for y = 1, 14, 3 do
            local a_w, b_w, c_w, d_w = calculate_blend_weights(x, y)
            assert_true(a_w >= 0, "Weight A should be non-negative")
            assert_true(b_w >= 0, "Weight B should be non-negative")
            assert_true(c_w >= 0, "Weight C should be non-negative")
            assert_true(d_w >= 0, "Weight D should be non-negative")
        end
    end
end)

test("Parameter blending calculation", function()
    init_snapshots()
    
    -- Set up different values in each snapshot for testing
    snapshots.A.params.q = 1.0
    snapshots.B.params.q = 2.0
    snapshots.C.params.q = 3.0
    snapshots.D.params.q = 4.0
    
    snapshots.A.params[1].level = -20.0
    snapshots.B.params[1].level = -10.0
    snapshots.C.params[1].level = -15.0
    snapshots.D.params[1].level = -5.0
    
    -- Test center position (should be average of all four)
    local a_w, b_w, c_w, d_w = calculate_blend_weights(7.5, 7.5)
    local blended_q = snapshots.A.params.q * a_w + 
                      snapshots.B.params.q * b_w + 
                      snapshots.C.params.q * c_w + 
                      snapshots.D.params.q * d_w
    
    local expected_q = (1.0 + 2.0 + 3.0 + 4.0) / 4  -- 2.5
    assert_near(blended_q, expected_q, 0.001, "Blended Q at center should be average")
    
    local blended_level = snapshots.A.params[1].level * a_w + 
                          snapshots.B.params[1].level * b_w + 
                          snapshots.C.params[1].level * c_w + 
                          snapshots.D.params[1].level * d_w
    
    local expected_level = (-20.0 + -10.0 + -15.0 + -5.0) / 4  -- -12.5
    assert_near(blended_level, expected_level, 0.001, "Blended level at center should be average")
end)

-- Run summary
print(string.format("\n=== TEST SUMMARY ==="))
print(string.format("Tests run: %d", test_count))
print(string.format("Passed: %d", pass_count))
print(string.format("Failed: %d", test_count - pass_count))

if pass_count == test_count then
    print("✓ ALL TESTS PASSED!")
    os.exit(0)
else
    print("✗ SOME TESTS FAILED!")
    os.exit(1)
end
