local wezterm = require 'wezterm'
local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Persistent mux server (systemd user service: wezterm-mux-server.service).
-- Panes/tabs live in that daemon, not in the GUI window, so closing the
-- window (or the window crashing) doesn't kill anything running inside it -
-- only a real reboot does, which is what the save/restore scripts are for.
config.unix_domains = {
  {
    name = 'mux',
    connect_automatically = true,
  },
}
config.default_gui_startup_args = { 'connect', 'mux' }

config.scrollback_lines = 100000
config.enable_wayland = false

return config
