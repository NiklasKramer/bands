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
    if x >= 2 and x <= 15 and y >= 2 and y <= 15 then
        -- Store the old position before updating
        local old_x = ui_state.current_matrix_pos.x
        local old_y = ui_state.current_matrix_pos.y

        -- Update to new position
        ui_state.current_matrix_pos = { x = x - 1, y = y - 1 }

        -- Call apply_blend with the new position, but pass old position as start
        snapshot_functions.apply_blend(ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y, old_x, old_y)
        print(string.format("matrix pos: %d,%d", ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y))
    end
end

-- Handle grid key presses
function GridUI.key(ui_state, x, y, z, redraw_screen_callback, snapshot_functions)
    if y == 16 and x == 16 then
        ui_state.shift_held = (z == 1)
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
                snapshot_functions.redraw_grid()
            elseif x == 8 then
                snapshot_functions.switch_to_snapshot("B")
                snapshot_functions.redraw_grid()
            elseif x == 9 then
                snapshot_functions.switch_to_snapshot("C")
                snapshot_functions.redraw_grid()
            elseif x == 10 then
                snapshot_functions.switch_to_snapshot("D")
                snapshot_functions.redraw_grid()
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
                snapshot_functions.redraw_grid()
            end
        end
    end
end

return GridUI
