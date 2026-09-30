# desktop-session-persistence

Save/restore for a Linux Mint Cinnamon (X11, LightDM) desktop: tmux/byobu
session layout + real terminal scrollback, and open-window positions —
across logout, crash, or reboot.

Built because Cinnamon's built-in XSMP "auto-save-session" looks like it
works (the checkbox is on) but doesn't: most modern apps stopped
implementing that protocol, so nothing actually gets saved through it.

## What's here

```
tmux/
  tmux.conf                 -> ~/.tmux.conf
  byobu-include.tmux.conf    -> ~/.config/byobu/.tmux.conf
  scripts/replay-logs.sh    -> ~/.tmux/scripts/replay-logs.sh
window-session/
  window-session-save.sh    -> ~/.local/bin/window-session-save.sh
  window-session-restore.sh -> ~/.local/bin/window-session-restore.sh
  gterm-tabs-save.sh        -> ~/.local/bin/gterm-tabs-save.sh
  session-browser.sh        -> ~/.local/bin/session-browser.sh
wezterm/
  wezterm.lua                  -> ~/.config/wezterm/wezterm.lua
  wezterm-tabs-save.sh         -> ~/.local/bin/wezterm-tabs-save.sh
  wezterm-tabs-restore.sh      -> ~/.local/bin/wezterm-tabs-restore.sh
tilix/
  tilix-tabs-save.sh           -> ~/.local/bin/tilix-tabs-save.sh
systemd/user/*               -> ~/.config/systemd/user/
autostart/*.desktop          -> ~/.config/autostart/
install.sh                   symlinks everything above into place
```

## Tmux / byobu: layout + real scrollback persistence

- `tmux-resurrect` + `tmux-continuum` (installed separately via
  [TPM](https://github.com/tmux-plugins/tpm)) save pane layout, working
  directories, and running commands, and auto-restore them the first time a
  tmux server starts after a reboot.
- Periodic autosave runs via a systemd user timer
  (`tmux-resurrect-save.timer`, every 15 min) rather than continuum's own
  status-bar polling trick — that trick silently disables itself whenever
  it detects more than one tmux-related process running (true in any setup
  that mixes byobu with a second plain `tmux` client, e.g. a second
  terminal multiplexer or an editor/agent that also drives tmux).
- **Real scrollback persistence**: tmux's live scrollback buffer is
  memory-only and can't survive a reboot, full stop. What actually
  survives: `tmux.conf`'s hooks pipe every pane's raw output continuously
  to `~/.tmux/logs/<session>_<window>-<pane>.log` for as long as the pane
  lives. After a resurrect restore, `replay-logs.sh` tails the last 51000
  lines of each pane's log back into the newly-relaunched (otherwise
  empty) pane, so recent history is visually there again. The full
  transcript is always on disk in `~/.tmux/logs/` regardless, searchable
  with `grep`/`less` (contains raw ANSI escapes from the original output).

## Window position save/restore

- `window-session-save.sh` snapshots open app windows (class, geometry,
  workspace, and a relaunch command read from `/proc/<pid>/cmdline`) to
  `~/.local/share/window-session/windows.json`, skipping desktop chrome
  (panels, cairo-dock, nemo-desktop, ...). Runs every 10 min via
  `window-session-save.timer`, plus once more on logout/shutdown via
  `window-session-sentinel.service`'s `ExecStop` (a `PartOf=
  graphical-session.target` sentinel unit — the standard systemd pattern
  for "run something when the graphical session ends").
- `window-session-restore.sh` runs at login (`autostart/*.desktop`, after
  an 8s settle delay). For each saved window class with fewer windows
  currently open than were saved, it relaunches the recorded command,
  polls for the new window, then repositions/moves it to its saved
  workspace with `wmctrl`.

### gnome-terminal tabs (best-effort, separate from tmux)

gnome-terminal has no session-save of its own (same dead-XSMP story as
Cinnamon), and its tabs are invisible to `wmctrl` — they're widgets
inside one shared `gnome-terminal-server` process, not separate X11
windows. `gterm-tabs-save.sh` (run as part of `window-session-save.sh`,
so on the same 10-min timer + logout hook) works around this by walking
`/proc` for every live shell directly attached to that process and
recording its tty + current working directory to
`~/.local/share/window-session/gterm-tabs.json`. On restore,
`window-session-restore.sh` uses that file to reopen the same number of
tabs at their last directories (`gnome-terminal --working-directory=X
--tab --working-directory=Y ...`), instead of a single blank tab.

Real limits of this, unlike the tmux track:
- Only **cwd** is recovered — no scrollback, no whatever command/foreground
  program was actually running in the tab.
- If you had **multiple gnome-terminal windows**, which tabs belonged to
  which window can't be recovered (they're all children of the same
  server process with no distinguishing window info) — every recovered
  tab lands consolidated into one new window.
- If you want real content/scrollback continuity, that's what the tmux
  track is for: keep the work inside a byobu/tmux pane instead of a bare
  gnome-terminal tab and you get both position *and* content back.
- `wmctrl -e` positions relative to the window-manager frame, not the
  outer decorated frame, so restored windows land close to but not
  pixel-identical to their saved spot.
- This does not implement real hibernate-to-disk (freezing exact RAM
  state). That needs a real on-disk swapfile sized to RAM, a `resume=`
  kernel parameter, and a GRUB/initramfs update — out of scope here.

## WezTerm (default terminal) + Tilix

Installed from WezTerm's official APT repo (`apt.fury.io/wez`) and
Ubuntu's `tilix` package. **WezTerm is now the system default terminal**
(`x-terminal-emulator` alternative and
`org.cinnamon.desktop.default-applications.terminal` both point at it).

### WezTerm: a real persistent mux daemon

`wezterm-mux-server.service` (systemd user unit) runs WezTerm's
multiplexer daemon continuously, independent of any GUI window —
`~/.config/wezterm/wezterm.lua` defines a unix domain named `mux` with
`connect_automatically = true` and sets it as the default GUI startup
target, so a plain `wezterm` always attaches to this same persistent
daemon rather than a throwaway local session. **This part is solid**:
closing the GUI window, or the GUI crashing, does not touch the panes or
their shells - they keep running in the daemon, scrollback (100k lines)
and all, until you reattach. An autostart entry opens a `wezterm` window
at login.

`wezterm-tabs-save.sh` snapshots every live pane (tty, cwd, original
window/tab grouping) via WezTerm's own `wezterm cli list --format json` -
no `/proc` scraping needed here, unlike gnome-terminal/Tilix, since
WezTerm exposes this natively. Runs on the same save cadence as
everything else.

**Automatic restore-on-reboot is intentionally NOT wired up.** After
extensive testing - headless, with a GUI attached first, with generous
delays between calls, on both the ~2.5-year-old "stable" apt package and
the actively-updated `wezterm-nightly` (switched to nightly specifically
to chase this down) - `wezterm cli spawn --new-window` reliably breaks
the second time it's called in a domain with no GUI actively rendering
it: later calls return stale/duplicate pane ids, and
`wezterm-mux-server`'s own log shows a genuine internal panic
(`wezterm-client/src/domain.rs:624`, survived by the server process but
leaving the request half-finished). With a GUI already attached it's
worse - one run sprayed out a dozen empty phantom windows in seconds.
This is a real upstream bug, not a scripting problem, and automating
something that can spray windows during an unattended login is worse
than doing nothing.

What's shipped instead: `wezterm-tabs-restore.sh` only ever issues **one**
spawn call (the most-recently-active saved pane, at its cwd), and is not
run automatically - it's there to invoke manually
(`wezterm-tabs-restore.sh`) if you want to try recovering your last
directory after a reboot and are fine with it occasionally failing
harmlessly (a `[FAIL]` line, no window sprayed) rather than trying it in
an unattended context. Everyday persistence (surviving a GUI close
without a reboot) needs none of this - the daemon already has it covered.

### Tilix: cwd only, same approach as gnome-terminal

Tilix is also a single shared process across every window with no
introspection API, so `tilix-tabs-save.sh` uses the identical `/proc`-walk
as `gterm-tabs-save.sh`. Unlike gnome-terminal, Tilix's CLI has no way to
chain multiple tabs into one `--working-directory` invocation, so
`window-session-restore.sh` gives each restored Tilix window at most one
saved tab's cwd (matched in order) instead of consolidating them - more
separate windows, but each with a real directory instead of a blank one.

### The tty-number question

Whether a reopened terminal lands back on the exact same `/dev/pts/N` is
inherently probabilistic, never guaranteed: devpts allocates the lowest
currently-free number, so if nothing else opens a pty in between, the
same order of reopening tends to reclaim the same numbers (verified
directly: closing a pane on pts/14 and immediately opening a new one
did reclaim pts/14, repeatedly, across multiple tests) - but *anything*
else that opens a pty first (another terminal, an SSH session, a
different app) shifts the numbering, and there's no way to reserve a
specific number in advance. Every save script here sorts its recorded
tabs/panes by ascending original tty number for exactly this reason - so
that wherever restore *is* used, replaying in that same order gives it
the best available chance.

## Viewing and managing what's saved

`session-browser.sh` is a small fzf-based TUI over everything above —
list, restore, delete, or save-now, all from one place:

```bash
session-browser.sh          # menu: pick a category
session-browser.sh tmux     # tmux/byobu layout snapshots
session-browser.sh windows  # window-position snapshots
session-browser.sh logs     # scrollback logs
```

Every list shows a clear, human-readable absolute timestamp (e.g.
`2026-09-29 08:35:25`), and a live preview of that snapshot's contents
(sessions/windows/panes + cwd/cmd for tmux; class/geometry/workspace/title
for windows; tail of the file for logs).

There are no keyboard shortcuts to remember — just plain list navigation:

| key                | does                                              |
|--------------------|---------------------------------------------------|
| `↑`/`↓` or `tab`/`shift-tab` | move through the list                     |
| `enter`            | choose the highlighted row                        |
| `esc`              | back out one level (quits from the top menu)      |

A pinned **★ save a new snapshot now** row sits at the top of the
tmux/window lists — tab down to it and hit enter. Picking any real
snapshot opens a small follow-up menu (`Restore this snapshot` / `Delete
this snapshot` / `Back`, or `View in less` / `Delete this log` / `Back`
for logs) — again just move and enter, nothing to hold down.

Earlier versions tried dedicated shortcut keys (`ctrl-s`/`ctrl-x`, then
`alt-s`, then `F5`) and all of them turned out to be intercepted before
fzf ever saw them: `ctrl-s`/`ctrl-q` are terminal flow control (XOFF/
XON), consumed by the tty driver itself; `alt-<letter>` is grabbed by
gnome-terminal (and most GTK apps) for menu mnemonics; and `F5` was
claimed by something else in this environment too (terminal, WM, or the
app itself vary by setup). Menu-driven `tab`/`enter` navigation has none
of those failure modes — it's what any terminal app already treats as
plain input.

"Restore" is non-destructive by construction: it only creates sessions/
windows/app instances that *aren't already running*; anything already
open is left alone (this mirrors tmux-resurrect's own restore semantics,
and `window-session-restore.sh` was written the same way from the start).
Restoring an older tmux snapshot also repoints resurrect's `last` pointer
(marked with `*` in the list) to that snapshot.

Needs `fzf` (`sudo apt install fzf`). `window-session-save.sh` now also
keeps a rotating history of its last 20 snapshots in
`~/.local/share/window-session/history/` so there's something to browse
(the "latest" `windows.json` used by `window-session-restore.sh` is
unaffected).

## Install on a fresh machine

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
./install.sh
~/.tmux/plugins/tpm/bin/install_plugins
systemctl --user daemon-reload
systemctl --user enable --now tmux-resurrect-save.timer
systemctl --user enable --now window-session-save.timer
systemctl --user enable --now window-session-sentinel.service
```

`install.sh` only symlinks; it doesn't enable the systemd units or install
TPM's plugins for you, since those are one-time/idempotent steps you may
want to review first.
