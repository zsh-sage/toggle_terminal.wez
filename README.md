# toggle_terminal.wez

An easy-to-use toggleable terminal for WezTerm

## Installation

```lua
local toggle_terminal = wezterm.plugin.require("https://github.com/zsh-sage/toggle_terminal.wez")
toggle_terminal.apply_to_config(config)
```

## Usage and configuration

Press <kbd>Ctrl</kbd>+<kbd>;</kbd> (or configure your own key) to toggle the terminal pane for the current tab.

Here are the default options available for configuration:

```lua
toggle_terminal.apply_to_config(config, {
	key = ";", -- Key for the toggle action
	mods = "CTRL", -- Modifier keys for the toggle action
	direction = "Up", -- Direction to split the pane
	size = { Percent = 20 }, -- Size of the split pane
	change_invoker_id_everytime = false, -- Change invoker pane on every toggle
	zoom = {
		auto_zoom_toggle_terminal = false, -- Automatically zoom toggle terminal pane
		auto_zoom_invoker_pane = true, -- Automatically zoom invoker pane
		remember_zoomed = true, -- Automatically re-zoom the toggle pane if it was zoomed before switching away
	}
})
```

You can use [this Neovim plugin](https://github.com/zsh-sage/wezterm-send.nvim) to send commands from Neovim to this pane

- For example, run `WeztermExecJson echo "hello world"` from Neovim

## Todo

- [ ] Add ressurect.wezterm integration
- [ ] Multiple toggleable panes for different keymaps
