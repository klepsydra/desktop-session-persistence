local wezterm = require 'wezterm'
local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Plain, local wezterm: every window gets its own shell and its own tty,
-- like any other terminal. Persistence is tmux's job here.
--
-- This used to attach every window to a shared mux daemon
-- (wezterm-mux-server). That mirrored ONE pane into every window, so all of
-- them showed the same /dev/pts/N - which collides with per-tty tmux session
-- names - and wezterm auto-started stray extra daemons on the same socket.
-- If you want the daemon back: define a unix domain here, set
-- no_serve_automatically = true, enable wezterm-mux-server.service, and use
-- `wezterm connect <name>` to reattach.

config.scrollback_lines = 100000
config.enable_wayland = false

return config
