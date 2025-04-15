local wezterm = require("wezterm")
local dev = wezterm.plugin.require("https://github.com/chrisgve/dev.wezterm")

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
	local opts = { keywords = { "Development", "toggle_terminal" }, auto = true }
	-- local opts = { keywords = { "https", "zsh-sage", "toggle_terminal" }, auto = true }

	dev.setup(opts)

	local toggle_terminal = require("lua.toggle_terminal")

	local final_opts = deep_merge_tables(toggle_terminal.opts, user_opts)

	-- Store the final merged options back into the toggle_terminal module
	toggle_terminal.opts = final_opts

	if not config.keys then
		config.keys = {}
	end

	table.insert(config.keys, {
		key = final_opts.key,
		mods = final_opts.mods,
		action = wezterm.action_callback(function(window, pane)
			toggle_terminal.toggle_terminal(window, pane)
		end),
	})
end

return M
