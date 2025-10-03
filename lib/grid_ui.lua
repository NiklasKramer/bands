-- Grid UI for bands script - Complete modular system
local util = require 'util'

local GridUI = {}

-- Initialize grid UI with all features
function GridUI.init(grid_device, freqs, mode_names)
    local state = {
        grid_device = grid_device,
        freqs = freqs,
        mode_names = mode_names,
        grid_mode = 1, -- 1=levels, 2=pans, 3=thresholds, 4=matrix
        shift_held = false,
        band_meters = {},
        current_matrix_pos = { x = 7, y = 7 }
    }

    return state
end

-- Handle matrix control
function GridUI.handle_matrix_control(ui_state, x, y, snapshot_functions)
    if x == 16 and y == 1 then
        -- Path mode toggle at position (16,1)
        snapshot_functions.toggle_path_mode()
        print("Path mode toggled")
    elseif x == 1 and y == 1 then
        -- Path recording start/stop at position (1,1)
        snapshot_functions.toggle_path_recording()
        print("Path recording toggled")
    elseif x >= 2 and x <= 15 and y >= 2 and y <= 15 then
        -- Store the old position before updating
        local old_x = ui_state.current_matrix_pos.x
        local old_y = ui_state.current_matrix_pos.y

        -- Update to new position
        ui_state.current_matrix_pos = { x = x - 1, y = y - 1 }

        -- Handle path mode: add points or clear all points
        if snapshot_functions.get_path_mode and snapshot_functions.get_path_mode() then
            if ui_state.shift_held then
                -- Shift + press: clear all path points
                snapshot_functions.clear_path()
            else
                -- Normal press: add point to path
                snapshot_functions.add_path_point(ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y)
            end
        else
            -- Normal matrix movement
            snapshot_functions.apply_blend(ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y, old_x, old_y)
        end
        print(string.format("matrix pos: %d,%d", ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y))
    end
end

-- Handle grid key presses
function GridUI.key(ui_state, x, y, z, redraw_screen_callback, snapshot_functions)
    if y == 16 and x == 16 then
        ui_state.shift_held = (z == 1)

        -- Shift + (16,16): Clear path
        if z == 1 and ui_state.shift_held and snapshot_functions.clear_path then
            snapshot_functions.clear_path()
            print("Path cleared")
        end

        GridUI.redraw(ui_state)
        return
    end

    if z == 1 then
        if y == 16 then
            if x >= 1 and x <= 3 then
                ui_state.grid_mode = x
                print(string.format("mode: %s", snapshot_functions.get_mode_names()[ui_state.grid_mode]))
                if redraw_screen_callback then redraw_screen_callback() end
            elseif x == 7 then
                snapshot_functions.switch_to_snapshot("A")
            elseif x == 8 then
                snapshot_functions.switch_to_snapshot("B")
            elseif x == 9 then
                snapshot_functions.switch_to_snapshot("C")
            elseif x == 10 then
                snapshot_functions.switch_to_snapshot("D")
            elseif x == 14 then
                ui_state.grid_mode = 4
                print("mode: matrix")
                if redraw_screen_callback then redraw_screen_callback() end
            end
        elseif y >= 1 and y <= 15 then
            if ui_state.grid_mode == 4 then
                GridUI.handle_matrix_control(ui_state, x, y, snapshot_functions)
            else
                local helper = include 'lib/helper'
                if ui_state.grid_mode == 1 then
                    helper.handle_level_mode(x, y, ui_state.shift_held, snapshot_functions.get_freqs())
                elseif ui_state.grid_mode == 2 then
                    helper.handle_pan_mode(x, y, ui_state.shift_held, snapshot_functions.get_freqs())
                elseif ui_state.grid_mode == 3 then
                    helper.handle_threshold_mode(x, y, ui_state.shift_held, snapshot_functions.get_freqs())
                end
            end
        end
    end
end

return GridUI
