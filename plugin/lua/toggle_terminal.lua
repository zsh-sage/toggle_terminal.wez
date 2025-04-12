--[[
  Manages a toggleable terminal pane per tab.
  Provides keybindings to create/show/hide the pane.
--]]

-- Define the module table that will be returned
local M = {}

local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

-- Configuration for the toggleable pane
M.opts = {
	key = ";", -- Key for the toggle action
	mods = "CTRL", -- Modifier keys for the toggle action
	direction = "Up", -- Direction to split the pane
	size = { Percent = 20 }, -- Size of the split pane
	change_invoker_id_everytime = false, -- Change invoker pane on every toggle
	zoom = {
		auto_zoom_toggle_terminal = false, -- Automatically zoom toggle terminal pane
		auto_zoom_invoker_pane = true, -- Automatically zoom invoker pane
		remember_zoomed = false, -- If toggle terminal pane was zoomed before switching to invoker pane,
		-- it will then zoom it automatically
	},
}

-- State for toggleable panes, keyed by tab_id.
-- Note: State for closed tabs is not automatically cleaned up.
-- pcall prevents errors from stale pane IDs.
local tab_states = {} -- { [tab_id] = { pane_id = -1, invoker_id = -1, zoomed = false  }, ... }

-- Get or initialize state for a tab_id
local function get_tab_state(tab_id)
	if not tab_states[tab_id] then
		wezterm.log_info("Initializing state for tab_id: " .. tab_id)
		tab_states[tab_id] = {
			pane_id = -1,
			invoker_id = -1,
			zoomed = false,
		}
	end
	return tab_states[tab_id]
end

local function get_toggle_state_file_path(tab_id)
	local tmp_dir = wezterm.config_dir .. "/tmp"

	return string.format("%s/wezterm_toggle_pane_tab_%s.json", tmp_dir, tab_id)
end

-- Write state to JSON file or delete the file if inactive/invalid.
local function update_toggle_state_file(tab_id, pane_id)
	local file_path = get_toggle_state_file_path(tab_id)

	-- Extract directory path
	local dir_path = file_path:match("(.*/)")
	if dir_path then
		dir_path = dir_path:sub(1, -2) -- Remove trailing '/'
	else
		wezterm.log_error("Could not determine directory path from: " .. file_path)
		return
	end

	local test_command = string.format("test -d %q", dir_path)
	local dir_exists = os.execute(test_command)

	if not dir_exists then
		wezterm.log_info("Directory does not exist, creating: " .. dir_path)
		-- Use 'mkdir -p' to create parent dirs and ignore existing dir errors.
		local mkdir_command = string.format("mkdir -p %q", dir_path)
		local ok, code, msg = os.execute(mkdir_command)

		if not ok or (type(code) == "number" and code ~= 0) then
			wezterm.log_error(
				"Failed to create directory: "
					.. dir_path
					.. " - Command: "
					.. mkdir_command
					.. " - OK: "
					.. tostring(ok)
					.. " - Code: "
					.. tostring(code)
					.. " - Msg: "
					.. tostring(msg)
			)
			return
		else
			wezterm.log_info("Successfully created directory: " .. dir_path)
		end
	else
		-- wezterm.log_info("Directory already exists: " .. dir_path)
	end

	local state_data = nil

	if pane_id and pane_id ~= -1 then
		-- Check if pane exists before writing state
		local success, pane = pcall(mux.get_pane, pane_id)
		if success and pane then
			-- Prepare data for JSON
			state_data = {
				pane_id = pane_id,
				tab_id = tab_id, -- Include tab_id for verification
				active = true,
				timestamp = os.time(), -- Optional timestamp
			}
		else
			wezterm.log_warn(
				"Attempted to write state for invalid pane ID " .. pane_id .. ". Clearing file: " .. file_path
			)
			-- Fall through to delete the file if pane doesn't exist
		end
	end

	if state_data then
		-- Encode state to JSON
		local success_encode, json_string = pcall(wezterm.json_encode, state_data)
		if success_encode and json_string then
			wezterm.log_info("Writing toggle pane state to file: " .. file_path)
			local file, err = io.open(file_path, "w")
			if file then
				local success, write_err = file:write(json_string)
				if not success then
					wezterm.log_error("Failed to write to file: " .. file_path .. " Error: " .. tostring(write_err))
				end
				file:close()
			else
				wezterm.log_error("Failed to open file for writing: " .. file_path .. " Error: " .. tostring(err))
			end
		else
			wezterm.log_error("Failed to encode JSON state for tab " .. tab_id .. ". Error: " .. tostring(json_string))
			-- Delete file if encoding failed to avoid stale data
			local ok, err_msg = os.remove(file_path)
			if not ok then
				wezterm.log_error("Failed to delete file: " .. file_path .. " - Error: " .. tostring(err_msg))
			end
		end
	else
		-- Delete state file if inactive or pane ID was invalid
		wezterm.log_info("Clearing toggle pane state file: " .. file_path)
		local ok, err_msg = os.remove(file_path)
		if not ok then
			wezterm.log_error("Failed to delete file: " .. file_path .. " - Error: " .. tostring(err_msg))
		end
	end
end

---@alias TabState { pane_id: integer, invoker_id: integer, zoomed: boolean }

--- Resets the pane_id in the tab state.
---@param tab_state TabState The state for the tab.
local function reset_tab_state(tab_state)
	tab_state.pane_id = -1
end

--[[
  Core logic for toggling the terminal pane within the current tab.
  - Gets/initializes state for the current tab.
  - Creates the pane if it doesn't exist for this tab.
  - If the pane exists:
    - If active, activates the invoker pane for this tab.
    - If inactive, activates the toggle pane.
  Uses pcall to safely check pane existence.
]]
function M.toggle_terminal(window, pane)
	local current_pane_id = pane:pane_id()
	local current_tab_obj = pane:tab()
	local current_tab_id = current_tab_obj:tab_id()

	wezterm.log_info("Toggle terminal action triggered in tab_id: " .. current_tab_id)

	-- Get state for this tab
	local current_tab_state = get_tab_state(current_tab_id)

	-- Track the invoking pane ID for this tab
	if
		current_tab_state.invoker_id == -1
		or (M.opts.change_invoker_id_everytime and current_tab_state.pane_id ~= current_pane_id)
	then
		current_tab_state.invoker_id = current_pane_id
		wezterm.log_info("Setting invoker pane ID for tab " .. current_tab_id .. ": " .. current_tab_state.invoker_id)
	end

	local terminal_pane_obj = nil
	local terminal_pane_exists = false

	-- Safely check if the tracked pane ID for this tab exists
	if current_tab_state.pane_id ~= -1 then
		local success, result = pcall(mux.get_pane, current_tab_state.pane_id)
		if success and result then
			-- Check if the found pane is in the current tab
			if result:tab():tab_id() == current_tab_id then
				terminal_pane_exists = true
				terminal_pane_obj = result
				wezterm.log_info(
					"Found existing terminal pane for tab "
						.. current_tab_id
						.. " via ID: "
						.. current_tab_state.pane_id
				)
			else
				-- Pane exists but is in the wrong tab. Reset state for this tab.
				wezterm.log_warn(
					"Pane ID "
						.. current_tab_state.pane_id
						.. " found, but belongs to a different tab ("
						.. result:tab():tab_id()
						.. "). Resetting state for tab "
						.. current_tab_id
				)
				reset_tab_state(current_tab_state)

				update_toggle_state_file(current_tab_id, nil)
			end
		else
			-- Pane closed or pcall failed
			wezterm.log_info(
				"Pane ID "
					.. tostring(current_tab_state.pane_id)
					.. " for tab "
					.. current_tab_id
					.. " no longer exists or is invalid. Resetting state."
			)
			reset_tab_state(current_tab_state)

			update_toggle_state_file(current_tab_id, nil)
		end
	end

	-- Decide action based on pane existence and focus
	if terminal_pane_exists then
		if current_pane_id == current_tab_state.pane_id then
			-- Terminal pane is focused: Activate the invoker pane for this tab
			wezterm.log_info(
				"Currently in terminal pane for tab "
					.. current_tab_id
					.. ". Attempting to activate invoker: "
					.. current_tab_state.invoker_id
			)
			local success_activate, invoker_pane = pcall(mux.get_pane, current_tab_state.invoker_id)
			-- Ensure invoker pane exists and is in the current tab
			if success_activate and invoker_pane and invoker_pane:tab():tab_id() == current_tab_id then
				if M.opts.zoom.remember_zoomed then
					if not terminal_pane_obj then
						return -- Should not happen if terminal_pane_exists is true
					end

					for _, pane_with_info in ipairs(current_tab_obj:panes_with_info()) do
						if pane_with_info.pane:pane_id() == terminal_pane_obj:pane_id() then
							current_tab_state.zoomed = pane_with_info.is_zoomed
							break
						end
					end
				end
				current_tab_obj:set_zoomed(false)
				invoker_pane:activate()
				if M.opts.zoom.auto_zoom_invoker_pane then
					current_tab_obj:set_zoomed(true)
				end
				-- update_toggle_state_file(current_tab_id, nil) -- Keep state file active?
			else
				wezterm.log_warn(
					"Could not find or activate invoker pane ID "
						.. current_tab_state.invoker_id
						.. " (or it's in a different tab). Staying in terminal for tab "
						.. current_tab_id
				)
				-- Invoker pane is gone or moved, reset state and retry toggle
				reset_tab_state(current_tab_state)
				update_toggle_state_file(current_tab_id, nil)
				M.toggle_terminal(window, pane) -- Retry might create a new pane if needed
			end
		else
			-- Terminal exists but isn't focused: Activate it
			if terminal_pane_obj then
				current_tab_obj:set_zoomed(false)
				wezterm.log_info(
					"Activating existing terminal pane for tab " .. current_tab_id .. ": " .. current_tab_state.pane_id
				)
				terminal_pane_obj:activate()
				if
					(current_tab_state.zoomed and M.opts.zoom.remember_zoomed) or M.opts.zoom.auto_zoom_toggle_terminal
				then
					current_tab_obj:set_zoomed(true)
				end
				update_toggle_state_file(current_tab_id, current_tab_state.pane_id)
			end
		end
	else
		-- Terminal pane doesn't exist for this tab: Create it
		wezterm.log_info("Terminal pane not found for tab " .. current_tab_id .. ". Creating a new one.")
		-- Split relative to the current pane
		window:perform_action(act.SplitPane({ direction = M.opts.direction, size = M.opts.size }), pane)
		-- wezterm.sleep_ms(50) -- Add delay only if SplitPane activation is unreliable
		local new_pane = window:active_pane()
		-- Verify the new pane is in the correct tab
		if new_pane and new_pane:tab():tab_id() == current_tab_id then
			current_tab_state.pane_id = new_pane:pane_id()
			-- Ensure invoker is set (should be done earlier, but double-check)
			if current_tab_state.invoker_id == -1 then
				current_tab_state.invoker_id = current_pane_id
			end
			wezterm.log_info(
				"Created new terminal pane for tab "
					.. current_tab_id
					.. ". ID: "
					.. current_tab_state.pane_id
					.. ", Invoker ID: "
					.. current_tab_state.invoker_id
			)
			update_toggle_state_file(current_tab_id, current_tab_state.pane_id)
			if M.opts.zoom.auto_zoom_toggle_terminal then
				current_tab_obj:set_zoomed(true)
			end
		else
			wezterm.log_error("Failed to create or identify new pane correctly in tab " .. current_tab_id)
			-- Reset state if creation failed
			reset_tab_state(current_tab_state)
			update_toggle_state_file(current_tab_id, nil)
		end
	end
end

return M
