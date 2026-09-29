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
  session-browser.sh        -> ~/.local/bin/session-browser.sh
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

### Known limits (not bugs)

- A restored **gnome-terminal** window lands in the right spot but comes
  back *empty* — the shell/cwd/tab state inside a terminal window isn't
  something `wmctrl`/relaunch can recover. That's what the tmux track
  above is for: keep real terminal work inside tmux/byobu panes and you
  get both position *and* content back.
- `wmctrl -e` positions relative to the window-manager frame, not the
  outer decorated frame, so restored windows land close to but not
  pixel-identical to their saved spot.
- This does not implement real hibernate-to-disk (freezing exact RAM
  state). That needs a real on-disk swapfile sized to RAM, a `resume=`
  kernel parameter, and a GRUB/initramfs update — out of scope here.

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
