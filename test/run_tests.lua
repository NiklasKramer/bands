#!/usr/bin/env lua

-- Test runner for bands project
-- Usage: lua test/run_tests.lua [test_name]

local function run_test_file(filename)
    print(string.format("\n" .. string.rep("=", 60)))
    print(string.format("RUNNING: %s", filename))
    print(string.rep("=", 60))
    
    local success, exit_code = pcall(function()
        dofile(filename)
    end)
    
    if not success then
        print(string.format("ERROR running %s: %s", filename, tostring(exit_code)))
        return false
    end
    
    return true
end

local function main(args)
    local test_dir = "test/"
    local all_passed = true
    
    -- If specific test provided, run only that
    if args[1] then
        local test_file = test_dir .. args[1]
        if not test_file:match("%.lua$") then
            test_file = test_file .. ".lua"
        end
        
        local file = io.open(test_file, "r")
        if not file then
            print(string.format("ERROR: Test file '%s' not found", test_file))
            os.exit(1)
        end
        file:close()
        
        local success = run_test_file(test_file)
        os.exit(success and 0 or 1)
    end
    
    -- Otherwise run all tests
    local test_files = {
        "test_bands.lua",
        "test_integration.lua",
        "test_performance.lua",
        "test_edge_cases.lua",
        "test_stress.lua"
    }
    
    print("BANDS PROJECT - COMPREHENSIVE TEST SUITE")
    print("Running all tests...")
    
    for _, test_file in ipairs(test_files) do
        local full_path = test_dir .. test_file
        local file = io.open(full_path, "r")
        
        if file then
            file:close()
            local success = run_test_file(full_path)
            if not success then
                all_passed = false
            end
        else
            print(string.format("WARNING: Test file '%s' not found, skipping", full_path))
        end
    end
    
    print(string.format("\n" .. string.rep("=", 60)))
    print("FINAL RESULTS")
    print(string.rep("=", 60))
    
    if all_passed then
        print("✓ ALL TEST SUITES PASSED!")
        print("The bands project is ready for use.")
        os.exit(0)
    else
        print("✗ SOME TEST SUITES FAILED!")
        print("Please review the failures above.")
        os.exit(1)
    end
end

-- Run with command line arguments
main(arg or {})
