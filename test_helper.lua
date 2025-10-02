-- Test for lib/helper.lua - ACTUALLY imports the real code
-- This test properly imports and tests the actual helper module

local test_count = 0
local pass_count = 0

-- Test framework
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

-- Mock the util module that helper.lua requires
local util = {
    round = function(x) return math.floor(x + 0.5) end,
    clamp = function(x, min, max) return math.max(min, math.min(max, x)) end
}

-- Mock params for testing
local mock_params = {}
_G.params = {
    set = function(id, value) 
        print(string.format("MOCK params:set('%s', %s)", tostring(id), tostring(value)))
        mock_params[id] = value 
    end
}

-- Mock the util module in package.preload so helper.lua can find it
package.preload['util'] = function() return util end

-- ACTUALLY IMPORT THE REAL HELPER MODULE
package.path = package.path .. ";./lib/?.lua"
local Helper = require('helper')

print("=== TESTING REAL HELPER.LUA MODULE ===")
print("This test ACTUALLY imports lib/helper.lua using require()")

test("Import real helper module", function()
    assert_true(Helper ~= nil, "Should successfully import helper module")
    assert_true(type(Helper) == "table", "Helper should be a table/module")
    
    -- Check that expected functions exist
    assert_true(type(Helper.row_to_level_db) == "function", "Should have row_to_level_db function")
    assert_true(type(Helper.row_to_pan) == "function", "Should have row_to_pan function")
    assert_true(type(Helper.row_to_threshold) == "function", "Should have row_to_threshold function")
    assert_true(type(Helper.level_db_to_row) == "function", "Should have level_db_to_row function")
    assert_true(type(Helper.pan_to_row) == "function", "Should have pan_to_row function")
    assert_true(type(Helper.threshold_to_row) == "function", "Should have threshold_to_row function")
    
    print("✓ Successfully imported REAL helper module with all expected functions")
end)

test("Test real row_to_level_db function", function()
    -- Test the REAL function from helper.lua
    -- row 1 = +6dB, row 15 = -60dB
    
    local level1 = Helper.row_to_level_db(1)
    assert_near(level1, 6.0, 0.001, "Row 1 should be +6dB")
    
    local level15 = Helper.row_to_level_db(15)
    assert_near(level15, -60.0, 0.001, "Row 15 should be -60dB")
    
    local level8 = Helper.row_to_level_db(8)
    local expected8 = 6 - ((8 - 1) * 66 / 14)  -- Should be ~-27dB
    assert_near(level8, expected8, 0.001, "Row 8 should be calculated correctly")
    
    print("✓ Real row_to_level_db function works correctly")
end)

test("Test real row_to_pan function", function()
    -- Test the REAL function from helper.lua
    -- row 1 = -1 (left), row 8 = 0 (center), row 15 = +1 (right)
    
    local pan1 = Helper.row_to_pan(1)
    assert_near(pan1, -1.0, 0.001, "Row 1 should be -1 (full left)")
    
    local pan8 = Helper.row_to_pan(8)
    assert_near(pan8, 0.0, 0.001, "Row 8 should be 0 (center)")
    
    local pan15 = Helper.row_to_pan(15)
    assert_near(pan15, 1.0, 0.001, "Row 15 should be +1 (full right)")
    
    print("✓ Real row_to_pan function works correctly")
end)

test("Test real row_to_threshold function", function()
    -- Test the REAL function from helper.lua
    -- row 1 = 1.0, row 15 = 0.0
    
    local thresh1 = Helper.row_to_threshold(1)
    assert_near(thresh1, 1.0, 0.001, "Row 1 should be 1.0 (max threshold)")
    
    local thresh15 = Helper.row_to_threshold(15)
    assert_near(thresh15, 0.0, 0.001, "Row 15 should be 0.0 (min threshold)")
    
    local thresh8 = Helper.row_to_threshold(8)
    local expected8 = 1 - ((8 - 1) / 14)  -- Should be 0.5
    assert_near(thresh8, expected8, 0.001, "Row 8 should be calculated correctly")
    
    print("✓ Real row_to_threshold function works correctly")
end)

test("Test real inverse functions (round trip)", function()
    -- Test that the REAL inverse functions work correctly
    
    -- Test level conversion round trip
    local original_level = -12.5
    local row = Helper.level_db_to_row(original_level)
    local converted_level = Helper.row_to_level_db(row)
    assert_near(converted_level, original_level, 5.0, "Level round trip should be close")
    
    -- Test pan conversion round trip
    local original_pan = 0.3
    local pan_row = Helper.pan_to_row(original_pan)
    local converted_pan = Helper.row_to_pan(pan_row)
    assert_near(converted_pan, original_pan, 0.2, "Pan round trip should be close")
    
    -- Test threshold conversion round trip
    local original_thresh = 0.7
    local thresh_row = Helper.threshold_to_row(original_thresh)
    local converted_thresh = Helper.row_to_threshold(thresh_row)
    assert_near(converted_thresh, original_thresh, 0.1, "Threshold round trip should be close")
    
    print("✓ Real inverse functions work correctly")
end)

test("Test real set_band_param function", function()
    -- Test the REAL function from helper.lua
    mock_params = {}  -- Reset
    
    local freqs = {80, 150, 250, 350}  -- Test with 4 bands
    
    -- Test single band setting
    Helper.set_band_param(2, "level", -6.0, false, freqs, "%.1f dB")
    
    -- Debug: check what's in mock_params
    print("DEBUG: mock_params contents:")
    for k, v in pairs(mock_params) do
        print(string.format("  %s = %s", k, v))
    end
    
    assert_equal(mock_params["band_02_level"], -6.0, "Should set single band parameter")
    
    -- Test all bands setting
    Helper.set_band_param(1, "pan", 0.5, true, freqs, "%.2f")
    for i = 1, #freqs do
        local param_id = string.format("band_%02d_pan", i)
        assert_equal(mock_params[param_id], 0.5, "Should set all band parameters when shift held")
    end
    
    print("✓ Real set_band_param function works correctly")
end)

test("Test real mode handler functions", function()
    -- Test the REAL mode handler functions from helper.lua
    mock_params = {}  -- Reset
    
    local freqs = {80, 150, 250}  -- Test with 3 bands
    
    -- Test level mode handler
    Helper.handle_level_mode(1, 5, false, freqs)
    local expected_level = Helper.row_to_level_db(5)
    assert_equal(mock_params["band_01_level"], expected_level, "Level mode should set correct level")
    
    -- Test pan mode handler
    Helper.handle_pan_mode(2, 10, false, freqs)
    local expected_pan = Helper.row_to_pan(10)
    assert_equal(mock_params["band_02_pan"], expected_pan, "Pan mode should set correct pan")
    
    -- Test threshold mode handler
    Helper.handle_threshold_mode(3, 7, false, freqs)
    local expected_thresh = Helper.row_to_threshold(7)
    assert_equal(mock_params["band_03_thresh"], expected_thresh, "Threshold mode should set correct threshold")
    
    print("✓ Real mode handler functions work correctly")
end)

test("Test real handle_band_control function", function()
    -- Test the REAL handle_band_control function from helper.lua
    mock_params = {}  -- Reset
    
    local freqs = {80, 150}  -- Test with 2 bands
    local redraw_called = false
    local function mock_redraw() redraw_called = true end
    
    -- Test level mode (grid_mode = 1)
    Helper.handle_band_control(1, 3, false, 1, freqs, mock_redraw)
    local expected_level = Helper.row_to_level_db(3)
    assert_equal(mock_params["band_01_level"], expected_level, "Should handle level mode correctly")
    assert_true(redraw_called, "Should call redraw callback")
    
    -- Test pan mode (grid_mode = 2)
    redraw_called = false
    Helper.handle_band_control(2, 12, false, 2, freqs, mock_redraw)
    local expected_pan = Helper.row_to_pan(12)
    assert_equal(mock_params["band_02_pan"], expected_pan, "Should handle pan mode correctly")
    assert_true(redraw_called, "Should call redraw callback")
    
    print("✓ Real handle_band_control function works correctly")
end)

-- Run summary
print(string.format("\n=== HELPER MODULE TEST SUMMARY ==="))
print(string.format("Tests run: %d", test_count))
print(string.format("Passed: %d", pass_count))
print(string.format("Failed: %d", test_count - pass_count))

if pass_count == test_count then
    print("✓ ALL HELPER TESTS PASSED!")
    print("The REAL lib/helper.lua module is working correctly!")
    print("This test ACTUALLY imported and tested the real helper code using require()")
else
    print("✗ SOME HELPER TESTS FAILED!")
    print("There are issues with the real lib/helper.lua module")
end

os.exit(pass_count == test_count and 0 or 1)
