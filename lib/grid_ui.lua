-- Grid UI for bands script - Complete modular system
local util = require 'util'

local GridUI = {}

-- Initialize grid UI with all features
function GridUI.init(grid_device, freqs, mode_names)
    local state = {
        grid_device = grid_device,
        freqs = freqs,
        mode_names = mode_names,
        grid_mode = 0, -- 0=inputs, 1=levels, 2=pans, 3=thresholds, 4=decimate, 5=matrix
        shift_held = false,
        band_meters = {},
        current_matrix_pos = { x = 1, y = 1 } -- Start at snapshot A (top-left)
    }

    return state
end

-- Handle matrix control
function GridUI.handle_matrix_control(ui_state, x, y, snapshot_functions)
    if x == 16 and y == 1 then
        -- Path mode toggle at position (16,1)
        -- Shift + (16,1): Clear path
        if ui_state.shift_held then
            snapshot_functions.clear_path()
            if snapshot_functions.show_banner then
                snapshot_functions.show_banner("Path Cleared")
            end
        else
            snapshot_functions.toggle_path_mode()
        end
    elseif x == 1 and y == 1 then
        -- Path recording start/stop at position (1,1)
        snapshot_functions.toggle_path_recording()
    elseif x >= 2 and x <= 15 and y >= 2 and y <= 15 then
        -- Handle path mode: add or remove points
        if snapshot_functions.get_path_mode and snapshot_functions.get_path_mode() then
            local matrix_x = x - 1
            local matrix_y = y - 1

            if ui_state.shift_held then
                -- Shift + press: remove point from path if it exists
                snapshot_functions.remove_path_point(matrix_x, matrix_y)
                if snapshot_functions.show_banner then
                    snapshot_functions.show_banner("Point Removed")
                end
            else
                -- Normal press: add point to path
                snapshot_functions.add_path_point(matrix_x, matrix_y)
                if snapshot_functions.show_banner then
                    snapshot_functions.show_banner("Point Added")
                end
            end
        else
            -- Normal matrix movement (not in path mode)
            -- Store the old position before updating
            local old_x = ui_state.current_matrix_pos.x
            local old_y = ui_state.current_matrix_pos.y

            -- Update to new position
            ui_state.current_matrix_pos = { x = x - 1, y = y - 1 }

            -- Apply blend for new matrix position
            snapshot_functions.apply_blend(ui_state.current_matrix_pos.x, ui_state.current_matrix_pos.y, old_x, old_y)
        end
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
            if x >= 1 and x <= 5 then
                ui_state.grid_mode = x - 1 -- Convert to 0-indexed (mode 0-4)
                if redraw_screen_callback then redraw_screen_callback() end
                if snapshot_functions.redraw_grid then snapshot_functions.redraw_grid() end
                -- Show info banner for mode change
                if snapshot_functions.show_banner then
                    snapshot_functions.show_banner(ui_state.mode_names[x])
                end
            elseif x == 7 then
                if ui_state.shift_held then
                    snapshot_functions.save_snapshot("A")
                else
                    snapshot_functions.switch_to_snapshot("A")
                end
            elseif x == 8 then
                if ui_state.shift_held then
                    snapshot_functions.save_snapshot("B")
                else
                    snapshot_functions.switch_to_snapshot("B")
                end
            elseif x == 9 then
                if ui_state.shift_held then
                    snapshot_functions.save_snapshot("C")
                else
                    snapshot_functions.switch_to_snapshot("C")
                end
            elseif x == 10 then
                if ui_state.shift_held then
                    snapshot_functions.save_snapshot("D")
                else
                    snapshot_functions.switch_to_snapshot("D")
                end
            elseif x == 14 then
                ui_state.grid_mode = 5 -- Matrix is now mode 5
                if redraw_screen_callback then redraw_screen_callback() end
                if snapshot_functions.redraw_grid then snapshot_functions.redraw_grid() end
                -- Show info banner for matrix mode
                if snapshot_functions.show_banner then
                    snapshot_functions.show_banner("matrix")
                end
            end
        elseif y >= 1 and y <= 15 then
            if ui_state.grid_mode == 5 then
                GridUI.handle_matrix_control(ui_state, x, y, snapshot_functions)
            else
                local helper = include 'lib/helper'
                if ui_state.grid_mode == 0 then
                    helper.handle_input_mode(x, y, ui_state.shift_held,
                        snapshot_functions.save_snapshot, snapshot_functions.get_current_snapshot(),
                        snapshot_functions.show_banner, snapshot_functions.get_input_mode_state())
                elseif ui_state.grid_mode == 1 then
                    helper.handle_level_mode(x, y, ui_state.shift_held, snapshot_functions.get_freqs(),
                        snapshot_functions.save_snapshot, snapshot_functions.get_current_snapshot(),
                        snapshot_functions.set_selected_band)
                elseif ui_state.grid_mode == 2 then
                    helper.handle_pan_mode(x, y, ui_state.shift_held, snapshot_functions.get_freqs(),
                        snapshot_functions.save_snapshot, snapshot_functions.get_current_snapshot())
                elseif ui_state.grid_mode == 3 then
                    helper.handle_threshold_mode(x, y, ui_state.shift_held, snapshot_functions.get_freqs(),
                        snapshot_functions.save_snapshot, snapshot_functions.get_current_snapshot())
                elseif ui_state.grid_mode == 4 then
                    helper.handle_decimate_mode(x, y, ui_state.shift_held, snapshot_functions.get_freqs(),
                        snapshot_functions.save_snapshot, snapshot_functions.get_current_snapshot())
                end
            end
        end
    end
end

return GridUI
