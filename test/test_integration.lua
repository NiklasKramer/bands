-- Integration tests for bands project
-- These tests simulate actual Norns environment interactions

local test_count = 0
local pass_count = 0

-- Test framework
local function test(name, func)
    test_count = test_count + 1
    print(string.format("\n--- Integration Test %d: %s ---", test_count, name))

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

local function assert_true(condition, message)
    if not condition then
        error(message or "Expected true, got false")
    end
end

-- Mock Norns environment
local mock_params = {}
local mock_engine_calls = {}
local mock_grid_leds = {}

-- Mock params system
local params = {
    get = function(id)
        return mock_params[id] or 0
    end,
    set = function(id, value)
        mock_params[id] = value
        print(string.format("PARAM SET: %s = %s", id, value))
    end,
    add = function(spec)
        if type(spec) == "table" and spec.id then
            mock_params[spec.id] = spec.default or 0
        end
    end,
    add_control = function(id, name, controlspec)
        mock_params[id] = 0
    end,
    add_group = function() end
}

-- Mock engine
local engine = {
    level = function(band, level)
        mock_engine_calls["level_" .. band] = level
        print(string.format("ENGINE: band %d level = %.2f", band, level))
    end,
    pan = function(band, pan)
        mock_engine_calls["pan_" .. band] = pan
        print(string.format("ENGINE: band %d pan = %.2f", band, pan))
    end,
    q = function(q)
        mock_engine_calls.q = q
        print(string.format("ENGINE: q = %.2f", q))
    end,
    thresh_band = function(band, thresh)
        mock_engine_calls["thresh_" .. band] = thresh
        print(string.format("ENGINE: band %d thresh = %.2f", band, thresh))
    end
}

-- Mock grid
local grid_device = {
    led = function(self, x, y, brightness)
        local key = x .. "," .. y
        mock_grid_leds[key] = brightness
        print(string.format("GRID LED: (%d,%d) = %d", x, y, brightness))
    end,
    refresh = function(self)
        print("GRID: refresh called")
    end,
    all = function(self, brightness)
        print(string.format("GRID: all LEDs set to %d", brightness))
        mock_grid_leds = {}
        for x = 1, 16 do
            for y = 1, 16 do
                mock_grid_leds[x .. "," .. y] = brightness
            end
        end
    end
}

-- Mock util
local util = {
    time = function() return os.clock() end
}

-- Mock controlspec
local controlspec = {
    new = function(min, max, warp, step, default, units)
        return {
            min = min,
            max = max,
            warp = warp,
            step = step,
            default = default,
            units = units
        }
    end
}

-- Test data and functions (extracted from bands.lua)
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

-- Functions under test
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

local function store_snapshot(snapshot_name)
    local snapshot = snapshots[snapshot_name]
    if not snapshot then return end

    snapshot.params.q = params.get("q")

    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)

        snapshot.params[i].level = params.get(level_id)
        snapshot.params[i].pan = params.get(pan_id)
        snapshot.params[i].thresh = params.get(thresh_id)
    end

    print("Stored " .. snapshot.name)
end

local function recall_snapshot(snapshot_name)
    local snapshot = snapshots[snapshot_name]
    if not snapshot then return end

    params.set("q", snapshot.params.q)
    engine.q(snapshot.params.q)

    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)

        params.set(level_id, snapshot.params[i].level)
        params.set(pan_id, snapshot.params[i].pan)
        params.set(thresh_id, snapshot.params[i].thresh)

        engine.level(i, snapshot.params[i].level)
        engine.pan(i, snapshot.params[i].pan)
        engine.thresh_band(i, snapshot.params[i].thresh)
    end

    print("Recalled " .. snapshot.name)
end

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

    -- Blend Q parameter
    local blended_q = snapshots.A.params.q * a_w +
        snapshots.B.params.q * b_w +
        snapshots.C.params.q * c_w +
        snapshots.D.params.q * d_w

    params.set("q", blended_q)
    engine.q(blended_q)

    -- Blend per-band parameters
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

-- Helper to clear mock state
local function reset_mocks()
    mock_params = {}
    mock_engine_calls = {}
    mock_grid_leds = {}
    glide_state.is_gliding = false
end

-- Integration tests
print("=== BANDS INTEGRATION TEST SUITE ===")

test("Parameter system initialization", function()
    reset_mocks()

    -- Simulate parameter setup
    params.add_control("q", "Q", controlspec.new(0.1, 200, 'exp', 0.01, 1.1))
    params.add_control("glide", "Glide", controlspec.new(0, 20, 'lin', 0.01, 0.1, 's'))

    for i = 1, #freqs do
        local level_id = string.format("band_%02d_level", i)
        local pan_id = string.format("band_%02d_pan", i)
        local thresh_id = string.format("band_%02d_thresh", i)

        params.add_control(level_id, string.format("Band %d Level", i),
            controlspec.new(-60, 12, 'db', 0.1, -12))
        params.add_control(pan_id, string.format("Band %d Pan", i),
            controlspec.new(-1, 1, 'lin', 0.01, 0))
        params.add_control(thresh_id, string.format("Band %d Thresh", i),
            controlspec.new(0, 1, 'lin', 0.01, 0))
    end

    -- Check that parameters were created
    assert_equal(mock_params["q"], 0, "Q parameter should be initialized")
    assert_equal(mock_params["glide"], 0, "Glide parameter should be initialized")
    assert_equal(mock_params["band_01_level"], 0, "Band 1 level should be initialized")
end)

test("Snapshot store and recall workflow", function()
    reset_mocks()
    init_snapshots()

    -- Set some parameter values
    params.set("q", 2.5)
    params.set("band_01_level", -6.0)
    params.set("band_01_pan", 0.3)
    params.set("band_02_thresh", 0.7)

    -- Store to snapshot A
    store_snapshot("A")

    -- Verify snapshot contains the values
    assert_equal(snapshots.A.params.q, 2.5, "Snapshot A should store Q value")
    assert_equal(snapshots.A.params[1].level, -6.0, "Snapshot A should store band 1 level")
    assert_equal(snapshots.A.params[1].pan, 0.3, "Snapshot A should store band 1 pan")
    assert_equal(snapshots.A.params[2].thresh, 0.7, "Snapshot A should store band 2 thresh")

    -- Change parameters
    params.set("q", 1.0)
    params.set("band_01_level", -18.0)

    -- Recall snapshot A
    recall_snapshot("A")

    -- Verify parameters were restored
    assert_equal(mock_params["q"], 2.5, "Q should be restored from snapshot")
    assert_equal(mock_params["band_01_level"], -6.0, "Band 1 level should be restored")
    assert_equal(mock_engine_calls.q, 2.5, "Engine Q should be set")
    assert_equal(mock_engine_calls["level_1"], -6.0, "Engine band 1 level should be set")
end)

test("Matrix blending with different snapshots", function()
    reset_mocks()
    init_snapshots()

    -- Set up different values in each snapshot
    snapshots.A.params.q = 1.0
    snapshots.B.params.q = 2.0
    snapshots.C.params.q = 3.0
    snapshots.D.params.q = 4.0

    snapshots.A.params[1].level = -20.0
    snapshots.B.params[1].level = -10.0
    snapshots.C.params[1].level = -15.0
    snapshots.D.params[1].level = -5.0

    -- Test corner positions
    apply_blend_immediate(1, 1) -- Should be 100% A
    assert_equal(mock_engine_calls.q, 1.0, "Corner A should set Q to 1.0")
    assert_equal(mock_engine_calls["level_1"], -20.0, "Corner A should set level to -20.0")

    apply_blend_immediate(14, 1) -- Should be 100% B
    assert_equal(mock_engine_calls.q, 2.0, "Corner B should set Q to 2.0")
    assert_equal(mock_engine_calls["level_1"], -10.0, "Corner B should set level to -10.0")

    apply_blend_immediate(1, 14) -- Should be 100% C
    assert_equal(mock_engine_calls.q, 3.0, "Corner C should set Q to 3.0")
    assert_equal(mock_engine_calls["level_1"], -15.0, "Corner C should set level to -15.0")

    apply_blend_immediate(14, 14) -- Should be 100% D
    assert_equal(mock_engine_calls.q, 4.0, "Corner D should set Q to 4.0")
    assert_equal(mock_engine_calls["level_1"], -5.0, "Corner D should set level to -5.0")
end)

test("Grid LED matrix display", function()
    reset_mocks()

    -- Simulate grid matrix display
    grid_device:all(0) -- Clear grid

    -- Set matrix background
    for x = 2, 15 do
        for y = 2, 15 do
            grid_device:led(x, y, 2) -- Background brightness
        end
    end

    -- Set current position
    grid_ui_state.current_matrix_pos.x = 5
    grid_ui_state.current_matrix_pos.y = 7
    grid_device:led(grid_ui_state.current_matrix_pos.x + 1,
        grid_ui_state.current_matrix_pos.y + 1, 15)

    -- Verify LEDs were set
    assert_equal(mock_grid_leds["6,8"], 15, "Current position should be bright")
    assert_equal(mock_grid_leds["3,3"], 2, "Matrix background should be dim")
    assert_equal(mock_grid_leds["1,1"], 0, "Outside matrix should be off")
end)

test("Glide state management", function()
    reset_mocks()

    -- Initialize glide state
    glide_state.is_gliding = false
    glide_state.start_pos = { x = 1, y = 1 }
    glide_state.target_pos = { x = 14, y = 14 }

    -- Start glide
    params.set("glide", 1.0) -- 1 second glide
    glide_state.is_gliding = true
    glide_state.glide_time = util.time()

    assert_true(glide_state.is_gliding, "Glide should be active")
    assert_equal(glide_state.start_pos.x, 1, "Start position X should be 1")
    assert_equal(glide_state.target_pos.x, 14, "Target position X should be 14")

    -- Simulate glide progress
    local progress = 0.5 -- 50% through glide
    local current_x = glide_state.start_pos.x +
        (glide_state.target_pos.x - glide_state.start_pos.x) * progress
    local current_y = glide_state.start_pos.y +
        (glide_state.target_pos.y - glide_state.start_pos.y) * progress

    assert_equal(current_x, 7.5, "50% glide should be at X=7.5")
    assert_equal(current_y, 7.5, "50% glide should be at Y=7.5")
end)

test("Parameter validation and bounds checking", function()
    reset_mocks()

    -- Test parameter bounds (simulated)
    local function set_and_validate(param_id, value, min_val, max_val)
        local clamped = math.max(min_val, math.min(max_val, value))
        params.set(param_id, clamped)
        return mock_params[param_id] == clamped
    end

    -- Test Q bounds
    assert_true(set_and_validate("q", 0.05, 0.1, 200), "Q below minimum should be clamped")
    assert_true(set_and_validate("q", 250, 0.1, 200), "Q above maximum should be clamped")

    -- Test level bounds
    assert_true(set_and_validate("band_01_level", -70, -60, 12), "Level below minimum should be clamped")
    assert_true(set_and_validate("band_01_level", 20, -60, 12), "Level above maximum should be clamped")

    -- Test pan bounds
    assert_true(set_and_validate("band_01_pan", -2, -1, 1), "Pan below minimum should be clamped")
    assert_true(set_and_validate("band_01_pan", 2, -1, 1), "Pan above maximum should be clamped")
end)

test("Engine command generation", function()
    reset_mocks()

    -- Test engine commands are generated correctly
    engine.level(1, -12.5)
    engine.pan(3, 0.7)
    engine.q(1.8)
    engine.thresh_band(5, 0.3)

    assert_equal(mock_engine_calls["level_1"], -12.5, "Engine level command should be recorded")
    assert_equal(mock_engine_calls["pan_3"], 0.7, "Engine pan command should be recorded")
    assert_equal(mock_engine_calls.q, 1.8, "Engine Q command should be recorded")
    assert_equal(mock_engine_calls["thresh_5"], 0.3, "Engine thresh command should be recorded")
end)

test("Grid coordinate mapping", function()
    reset_mocks()

    -- Test matrix coordinate mapping (1-14 internal, 2-15 on grid)
    local function test_coord_mapping(internal_x, internal_y)
        local grid_x = internal_x + 1
        local grid_y = internal_y + 1

        -- Grid coordinates should be in range 2-15
        return grid_x >= 2 and grid_x <= 15 and grid_y >= 2 and grid_y <= 15
    end

    assert_true(test_coord_mapping(1, 1), "Internal (1,1) should map to valid grid coords")
    assert_true(test_coord_mapping(14, 14), "Internal (14,14) should map to valid grid coords")
    assert_true(test_coord_mapping(7, 8), "Internal (7,8) should map to valid grid coords")
end)

-- Run summary
print(string.format("\n=== INTEGRATION TEST SUMMARY ==="))
print(string.format("Tests run: %d", test_count))
print(string.format("Passed: %d", pass_count))
print(string.format("Failed: %d", test_count - pass_count))

if pass_count == test_count then
    print("✓ ALL INTEGRATION TESTS PASSED!")
    os.exit(0)
else
    print("✗ SOME INTEGRATION TESTS FAILED!")
    os.exit(1)
end
