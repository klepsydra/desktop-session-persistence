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

-- Visible window border. Cinnamon's Mint-Y window theme draws no side/bottom
-- border for ANY app (frame extents 0,0,28,0), which makes a dark terminal
-- vanish into a dark desktop. So wezterm draws its own and, with it, its own
-- tab bar + min/max/close buttons instead of Cinnamon's title bar. To go back
-- to the Cinnamon title bar, delete this block (or set
-- window_decorations = "TITLE | RESIZE").
config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'
local border = '#5b8cff'
config.window_frame = {
  border_left_width = '2px', border_right_width = '2px',
  border_top_height = '2px', border_bottom_height = '2px',
  border_left_color = border, border_right_color = border,
  border_top_color = border, border_bottom_color = border,
}

return config
