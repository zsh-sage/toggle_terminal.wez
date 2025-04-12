local wezterm = require("wezterm")

local function findPluginPackagePath(myProject)
	local separator = package.config:sub(1, 1) == "\\" and "\\" or "/"
	for _, v in ipairs(wezterm.plugin.list()) do
		if v.url == myProject then
			return v.plugin_dir .. separator .. "plugin" .. separator .. "?.lua"
		end
	end

	return nil
end

local plugin_path_pattern = findPluginPackagePath("https://github.com/zsh-sage/toggle_terminal.wez")

if not plugin_path_pattern then
	-- Throw an error if the plugin path couldn't be determined
	error(
		"Could not find plugin path for 'https://github.com/zsh-sage/toggle_terminal.wez'. "
			.. "Please ensure the plugin is correctly registered in your wezterm config with this exact URL."
	)
end

package.path = package.path .. ";" .. plugin_path_pattern

local toggle_terminal = require("lua.toggle_terminal")

local M = {}

-- Helper function for deep merging tables (user opts over defaults)
local function deep_merge_tables(defaults, overrides)
	local merged = {}

	for k, v in pairs(defaults) do
		merged[k] = v
	end

	if overrides then
		for k, v_override in pairs(overrides) do
			local v_default = merged[k]
			if type(v_override) == "table" and type(v_default) == "table" then
				merged[k] = deep_merge_tables(v_default, v_override)
			else
				merged[k] = v_override
			end
		end
	end
	return merged
end

---@param user_opts table|nil Optional table of user overrides for the toggle terminal options.
function M.apply_to_config(config, user_opts)
	local final_opts = deep_merge_tables(toggle_terminal.opts, user_opts)

	-- Store the final merged options back into the toggle_terminal module
	toggle_terminal.opts = final_opts

	table.insert(config.keys, {
		key = final_opts.key,
		mods = final_opts.mods,
		action = wezterm.action_callback(function(window, pane)
			toggle_terminal.toggle_terminal(window, pane)
		end),
	})
end

return M
