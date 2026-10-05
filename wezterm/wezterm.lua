local wezterm = require 'wezterm'
local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Two ways to use wezterm:
--
--   `wezterm`          plain local windows. Every launch is its own shell and
--                      its own /dev/pts/N (use tmux/byobu here for persistence).
--
--   `wezterm-session`  the persistent workspace: attaches to the `mux` domain
--                      below, served by wezterm-mux-server.service. Panes live
--                      in that daemon, so closing the window - or the GUI
--                      crashing - loses nothing; run it again to reattach.
--                      Make new tabs/windows with Ctrl+Shift+T / Ctrl+Shift+N
--                      INSIDE it; they land in the daemon on their own ttys.
--
-- Why not make plain `wezterm` attach to the daemon too: every external
-- launch of a daemon-attached GUI just mirrors the existing pane into another
-- window (same /dev/pts/N, tested), and the only way to get a *new* pane from
-- outside is `wezterm cli spawn`, which has crashed the daemon.
--
-- no_serve_automatically: never let a GUI start its own stray daemon.
config.unix_domains = {
  { name = 'mux', no_serve_automatically = true },
}

config.scrollback_lines = 100000
config.enable_wayland = false

return config
