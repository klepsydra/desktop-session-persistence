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
  lives. Optionally (**off by default**), after a resurrect restore
  `replay-logs.sh` tails the last 51000 lines of each pane's log back
  into the newly-relaunched pane. It does this by typing a `clear; tail
  ...` command into the pane, which lands in shell history, so it's a
  toggle: `session-browser.sh` -> settings -> "replay scrollback into
  restored tmux panes" (a flag file at
  `~/.config/desktop-session-persistence/replay-scrollback.enabled`). The full
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
  an 8s settle delay) and **only relaunches terminals** (gnome-terminal,
  tilix): for each with fewer windows open than were saved, it relaunches
  and repositions with `wmctrl`. It deliberately skips everything else.
  Firefox, Geany, etc. restore their own windows at login and wezterm has
  its own autostart entry; relaunching them here raced with that (startup
  is slower than the 8s wait), made duplicate windows, and - because those
  got saved - grew every login (Geany 1->2->4, Firefox 4->7, wezterm
  1->3->5->6 in the logged history). `--all-apps` lifts the restriction;
  `session-browser.sh`'s explicit "Restore" uses it.

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

### WezTerm: plain windows, plus a persistent workspace

Two modes, on purpose:

- **`wezterm`** - plain local windows. Every launch is its own shell on its
  own `/dev/pts/N` (what "open terminal here" and the autostart want). Use
  tmux/byobu here for persistence, like the other terminals.
- **`wezterm-session`** (also in the app menu as *WezTerm (persistent
  session)*) - attaches to the `mux` domain served by
  `wezterm-mux-server.service`. Panes live in the daemon, so closing the
  window, or the GUI crashing, loses nothing: run it again and every
  window/tab that's still in the daemon comes back. If it's already open it
  just raises the window. Make new tabs/windows *inside* it with
  Ctrl+Shift+T / Ctrl+Shift+N; they land in the daemon on their own ttys.
  No tmux needed in there. (Your shell never auto-starts tmux; you run
  `byobu`/`tmux` yourself, so there is nothing to disable.)

Why the persistent mode isn't simply what plain `wezterm` does - tested on
a private daemon:

- Every *external* launch of a daemon-attached GUI (`wezterm start`,
  `connect mux`, with or without `--new-tab`, a `gui-startup` hook) opens
  another window mirroring the **same pane**: three launches, one
  `/dev/pts/9`. That collides with per-tty tmux session names, and it's
  what made every wezterm window show the same tty before.
- Making a *new* pane from outside means `wezterm cli spawn`, which has
  crashed the daemon (below).
- Creating tabs/windows inside the GUI works: Ctrl+Shift+T gave a new tty,
  Ctrl+Shift+N another, and after closing every window `wezterm-session`
  brought them all back with their tab counts.

`no_serve_automatically = true` on the domain stops a GUI from starting its
own stray daemon on the same socket (an orphan from Oct 2 did exactly that).
The daemon only lives for the login session - it doesn't survive a logout or
reboot - so this protects against closed windows and GUI crashes, not those.
The service has no `Restart=`, deliberately (see below).

`wezterm-tabs-save.sh` snapshots every live pane (tty, cwd, original
window/tab grouping) via WezTerm's own `wezterm cli list --format json` -
no `/proc` scraping needed here, unlike gnome-terminal/Tilix, since
WezTerm exposes this natively. Runs on the same save cadence as
everything else.

**Restore is not wired up anywhere, automatic or manual, because it has
actually crashed a live session - this isn't a hypothetical risk.**
Initial testing (headless, with a GUI attached first, with generous
delays between calls, on both the ~2.5-year-old "stable" apt package and
`wezterm-nightly`) found `wezterm cli spawn --new-window` corrupting
`wezterm-mux-server`'s internal state on repeated calls, so the shipped
script was scaled back to a single spawn attempt, believed safe.

It wasn't. On 2026-09-30, running that single-spawn restore from
`session-browser.sh` - by hand, with a real GUI attached showing a real
session - crashed `wezterm-mux-server` outright: a genuine panic
(`wezterm-client/src/domain.rs:624`, `"no such window!?"`, exit code
101), confirmed in the service's journal. `Restart=on-failure` then did
exactly what it's supposed to and silently brought the daemon back up -
empty, with the prior panes gone. The restore feature was meant to
*add* a recovered window in the worst case, or fail quietly in the
better case; instead it took down the thing it was supposed to be
restoring. The warning text that used to sit in front of this action
described the earlier (also real, just less severe) corruption failure
mode and said to expect a quiet `[FAIL]`, not this - so the response
wasn't "warn more," it was remove the capability:
`session-browser.sh`'s wezterm category no longer offers restore at all
(view/save/delete only), and the systemd service's `Restart=` was
dropped so a future crash stays visibly down instead of silently
resurrecting an amnesiac daemon. `wezterm-tabs-restore.sh` is still on
disk with this incident documented at the top, for anyone who wants to
run it by hand with eyes fully open - `session-browser.sh` won't run it
for you.

Everyday persistence (surviving a GUI close without a reboot) needs
none of this and remains solid - only *restoring after the daemon
itself is gone* (a reboot, or now a crash) is the part that isn't safe.

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
session-browser.sh wezterm  # wezterm pane snapshots
session-browser.sh tilix    # tilix tab snapshots
session-browser.sh logs     # scrollback logs
```

Every list shows a clear, human-readable absolute timestamp (e.g.
`2026-09-29 08:35:25`), and a live preview of that snapshot's contents
(sessions/windows/panes + cwd/cmd for tmux; class/geometry/workspace/title
for windows; tty/cwd per window for wezterm; tty/cwd per tab for tilix;
tail of the file for logs).

The wezterm category's restore action is clearly labeled
*(single pane, experimental)* and explains why inline before it runs -
see [WezTerm (default terminal) + Tilix](#wezterm-default-terminal--tilix)
above for the real bug behind that restriction.

Plain list navigation, plus one direct key for the one action common to
every category and worth a shortcut - deleting:

| key                | does                                              |
|--------------------|---------------------------------------------------|
| `↑`/`↓` or `tab`/`shift-tab` | move through the list                     |
| `enter`            | choose the highlighted row                        |
| `del`              | delete the highlighted snapshot/log directly (with a y/N prompt) |
| `esc`              | back out one level (quits from the top menu)      |

Every one of the five categories - tmux, window-position, wezterm,
tilix, and scrollback logs - has **both** a save-now and a delete path:
a pinned **★ save a new snapshot now** row at the top of the list (tab
down to it, hit enter), and `del` on any real entry to delete it on the
spot. Picking a real snapshot with `enter` instead opens a small
follow-up menu (`Restore this snapshot` / `Delete this snapshot` /
`Back`, or `View in less` / `Delete this log` / `Back` for logs) - `del`
and the menu's delete option do the same thing, `del` is just faster.
For logs specifically, "save now" means something slightly different
from the other four: logs are already being written continuously (that's
the whole point), so it forces a checkpoint of the *entire* current
scrollback buffer into the log right now, rather than only what's
already been piped to disk.

`del` was chosen deliberately, after three earlier attempts at dedicated
shortcuts all turned out to be intercepted before fzf ever saw them:
`ctrl-s`/`ctrl-x` (terminal flow control, XOFF/XON, consumed by the tty
driver itself), `alt-s` (grabbed by gnome-terminal's menu mnemonics -
Search, specifically), then `F5` (claimed by something else in this
environment too). The dedicated Delete key isn't a modifier combo and
isn't claimed by any of those layers, so it's the one shortcut that's
actually reliable here; everything else stays plain `tab`/`enter`
navigation.

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

### Settings: switching each category on or off

`session-browser.sh` -> **settings** (or `session-browser.sh settings`) has
one row per category; Enter flips it in place. Everything is **on** by
default except scrollback replay, which is off.

| row | what "off" stops |
|---|---|
| tmux/byobu layout snapshots | the 15-min resurrect saves, and restore-on-tmux-start (read when tmux launches, so that half applies from the next server start) |
| window-position snapshots | window saves (timer + logout), the login-time restore, and gnome-terminal tab capture |
| wezterm panes | wezterm pane snapshots |
| tilix tabs | tilix tab snapshots |
| scrollback logs | per-pane logging - closes the pipe on every existing pane immediately, new panes don't start one; turning it back on restarts logging everywhere |
| replay scrollback | (off by default) typing `clear; tail ...` into restored panes |

Mechanism: a marker file at
`~/.config/desktop-session-persistence/disabled/<name>` means "off"
(`tmux`, `windows`, `wezterm`, `tilix`, `logs`); `dsp-enabled <name>` is
the one-line check each script runs first. Turning a category off stops
new captures only - existing snapshots/logs stay on disk and stay
browsable and deletable.

### History doesn't fill up with duplicates

All four of the custom save scripts (window-position, gnome-terminal,
wezterm, tilix) run on a timer regardless of whether anything actually
changed, which at one point meant e.g. wezterm's history directory held
20 files with exactly 1 unique content between them. `history-snapshot.sh`
is a small shared helper - compare the new snapshot against the most
recent existing one, byte-for-byte, and skip writing a new history entry
if they're identical - that every save script now calls instead of
unconditionally `cp`-ing a new timestamped file every run. tmux-resurrect
(third-party, so not editable directly) gets the same treatment via a
wrapper, `resurrect-save-dedup.sh`, that runs its real save script and
then collapses the result if it matches the prior save. The "latest"
pointer files (`windows.json`, `wezterm-tabs.json`, etc. - what the
restore scripts actually read) are unaffected either way; only the
*history* used for browsing is deduplicated.

### `wmctrl` needs `DISPLAY` set - and one long-lived shell didn't have it

Running window-position restore from a real terminal hit an uncaught
Python traceback: `wmctrl -lpxG` exited 1. Reproduced directly - `wmctrl`
needs `DISPLAY` to reach the X server, and it was unset in that
particular shell (a long-lived byobu pane whose environment predates
whatever set `DISPLAY` for the rest of the session is the likely cause,
though the exact origin doesn't matter as much as the fix). Every script
that shells out to `wmctrl` (`window-session-save.sh`,
`window-session-restore.sh`, `gterm-tabs-save.sh`, `tilix-tabs-save.sh`,
`wezterm-tabs-save.sh`) now does `export DISPLAY="${DISPLAY:-:0}"` up
front - `:0` because that's the only display this machine ever runs -
and none of them let a `wmctrl` failure crash with a raw traceback
any more: a real failure (as opposed to just "unset, now defaulted")
prints one clear line and leaves whatever was already saved untouched,
rather than silently overwriting it with an empty window list.

### `session-browser.sh` delete confirmations are a single keypress

`confirm()` used to need `y` *and* Enter, which - combined with `del`
switching fzf to a full alternate screen to ask the question - felt like
a lot of ceremony for a delete. It now reads a single keypress with no
Enter required (`read -n 1`); the alternate-screen switch itself is
inherent to how fzf's `execute()` works when it needs real interactive
input, not something scriptable away without dropping the confirmation
prompt entirely.

## Window borders (global)

Cinnamon's Mint GTK theme gives every window a 1px near-black edge with a soft
shadow, which disappears against a dark desktop. In this Muffin (6.6) the
frame Cinnamon draws around non-GTK apps comes from the GTK theme's CSS -
`.ssd decoration { box-shadow: 0 0 0 1px rgba(0,0,0,.65) }` - not from a
Metacity `metacity-theme-3.xml`, so a custom Metacity window-border theme is
silently ignored here (tried; a test theme with 8px red edges drew nothing).

`gtk-3.0/gtk.css` (linked to `~/.config/gtk-3.0/gtk.css`) overrides that ring
for every GTK3 app and for Cinnamon-drawn frames: 2px **blue** (`#5b8cff`) while
the window is focused, **grey** (`#7a7a7a`) when it isn't. Maximized, tiled,
fullscreen windows and popups keep no border. Change the two hex values to
recolor; delete the file to undo.

Cinnamon-drawn frames pick it up after a Cinnamon restart (Alt+F2, `r` - or
`gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method
org.Cinnamon.RestartCinnamon true`; windows stay open). Already-running GTK
apps pick it up the next time they start. Good test windows: Geany, Nemo,
gnome-terminal, `xcalc`/`xterm`, and the wezterm windows.

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
