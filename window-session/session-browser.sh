#!/bin/bash
# Interactive fzf browser + manager over everything the session-persistence
# setup saves: tmux/byobu layout snapshots, window-position snapshots, and
# per-pane scrollback logs.
#
# Navigation is plain list selection - up/down arrows or tab/shift-tab to
# move, enter to choose, esc to back out. No ctrl/alt/function-key
# shortcuts to remember or that risk being intercepted elsewhere
# (ctrl-s/ctrl-q are terminal flow control; alt-<letter> is grabbed by
# gnome-terminal and most GTK apps for menu mnemonics before it ever
# reaches the program running inside them). Picking a snapshot opens a
# small action menu (Restore / Delete / Back, or View / Delete / Back for
# logs); "save a new snapshot now" is a pinned row at the top of the list.
set -uo pipefail
export SHELL=bash

RESURRECT_DIR="$HOME/.local/share/tmux/resurrect"
RESURRECT_RESTORE="$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
RESURRECT_SAVE="$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"
WINSESS_LATEST="$HOME/.local/share/window-session/windows.json"
WINSESS_HIST="$HOME/.local/share/window-session/history"
WINSESS_RESTORE="$HOME/.local/bin/window-session-restore.sh"
WINSESS_SAVE="$HOME/.local/bin/window-session-save.sh"
TMUX_LOGS="$HOME/.tmux/logs"
WEZTERM_LATEST="$HOME/.local/share/window-session/wezterm-tabs.json"
WEZTERM_HIST="$HOME/.local/share/window-session/history"
WEZTERM_SAVE="$HOME/.local/bin/wezterm-tabs-save.sh"
WEZTERM_RESTORE="$HOME/.local/bin/wezterm-tabs-restore.sh"
TILIX_LATEST="$HOME/.local/share/window-session/tilix-tabs.json"
TILIX_HIST="$HOME/.local/share/window-session/history"
TILIX_SAVE="$HOME/.local/bin/tilix-tabs-save.sh"

export RESURRECT_DIR RESURRECT_RESTORE RESURRECT_SAVE
export WINSESS_LATEST WINSESS_HIST WINSESS_RESTORE WINSESS_SAVE TMUX_LOGS
export WEZTERM_LATEST WEZTERM_HIST WEZTERM_SAVE WEZTERM_RESTORE
export TILIX_LATEST TILIX_HIST TILIX_SAVE
export WINSESS_RESTORE  # also used by tilix's restore (--only-class tilix)

FZF_NAV=(--bind 'tab:down,shift-tab:up')

human_ts() {  # 20260929T083525 -> 2026-09-29 08:35:25
  local raw="$1"
  echo "${raw:0:4}-${raw:4:2}-${raw:6:2} ${raw:9:2}:${raw:11:2}:${raw:13:2}"
}
export -f human_ts

confirm() {
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}
export -f confirm

pause() { read -r -p "press enter to continue..." _; }
export -f pause

menu_pick() {  # menu_pick "header" "opt1" "opt2" ...
  local header="$1"; shift
  printf '%s\n' "$@" | fzf --header "$header  (enter:choose  tab/shift-tab:move  esc:back)" \
    --bind 'tab:down,shift-tab:up'
}
export -f menu_pick

# ---------- tmux / byobu layout snapshots ----------

fmt_resurrect() {
  python3 - "$1" <<'PYEOF'
import sys
path = sys.argv[1]
sessions, windows, panes = set(), 0, 0
lines_out = []
with open(path) as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        kind = parts[0]
        if kind in ("pane", "window"):
            sessions.add(parts[1])
        if kind == "window":
            windows += 1
        if kind == "pane":
            panes += 1
            cwd = parts[7].lstrip(":") if len(parts) > 7 else "?"
            cmd = parts[9] if len(parts) > 9 else "?"
            lines_out.append(f"  session {parts[1]} window {parts[2]}: {cmd}  (cwd: {cwd})")
print(f"sessions: {', '.join(sorted(sessions)) or '(none)'}")
print(f"windows: {windows}   panes: {panes}")
print()
print("\n".join(lines_out))
PYEOF
}
export -f fmt_resurrect

preview_resurrect_row() {
  if [ "$1" = "__SAVE_NOW__" ]; then
    echo "Creates a fresh snapshot of the current tmux/byobu session layout"
    echo "(sessions, windows, panes, working directories, running commands)."
  else
    fmt_resurrect "$1"
  fi
}
export -f preview_resurrect_row

list_resurrect() {
  local files last_target
  files=$(ls -t "$RESURRECT_DIR"/tmux_resurrect_*.txt 2>/dev/null)
  [ -n "$files" ] || return
  last_target=$(readlink -f "$RESURRECT_DIR/last" 2>/dev/null || true)
  echo "$files" | while read -r f; do
    ts=$(basename "$f" | sed 's/tmux_resurrect_//; s/\.txt//')
    mark=" "
    [ "$f" = "$last_target" ] && mark="*"
    printf '%s %s\t%s\n' "$mark" "$(human_ts "$ts")" "$f"
  done
}
export -f list_resurrect

restore_resurrect() {
  local f="$1"
  [ -n "$f" ] || return
  echo "Restoring tmux/byobu layout from: $(basename "$f")"
  echo "(creates any sessions/windows from it that aren't already running;"
  echo " sessions that already exist are left untouched)"
  ln -sfn "$f" "$RESURRECT_DIR/last"
  bash "$RESURRECT_RESTORE"
  pause
}
export -f restore_resurrect

delete_resurrect() {
  local f="$1"
  [ -n "$f" ] || return
  confirm "Delete snapshot $(basename "$f")?" || { echo cancelled; sleep 1; return; }
  if [ "$(readlink -f "$RESURRECT_DIR/last" 2>/dev/null)" = "$(readlink -f "$f")" ]; then
    echo "(that was the 'last' snapshot; clearing the pointer)"
    rm -f "$RESURRECT_DIR/last"
  fi
  rm -f "$f"
  sleep 1
}
export -f delete_resurrect

save_resurrect_now() { bash "$RESURRECT_SAVE" quiet; }
export -f save_resurrect_now

resurrect_action_menu() {
  local f="$1"
  local choice
  choice=$(menu_pick "acting on: $(basename "$f")" \
    "Restore this snapshot" "Delete this snapshot" "Back")
  case "$choice" in
    "Restore this snapshot") restore_resurrect "$f" ;;
    "Delete this snapshot") delete_resurrect "$f" ;;
  esac
}

browse_resurrect() {
  while true; do
    local sel path
    sel=$( { printf '\xe2\x98\x85 save a new snapshot now\t__SAVE_NOW__\n'; list_resurrect; } \
      | fzf --delimiter='\t' --with-nth=1 \
        --header 'tmux/byobu snapshots  (* = "last")  (enter:choose  tab/shift-tab:move  esc:back)' \
        --preview 'preview_resurrect_row {2}' --preview-window=right:65% \
        "${FZF_NAV[@]}" )
    [ -n "$sel" ] || return
    path=$(printf '%s' "$sel" | cut -f2)
    if [ "$path" = "__SAVE_NOW__" ]; then
      save_resurrect_now
    else
      resurrect_action_menu "$path"
    fi
  done
}

# ---------- window-position snapshots ----------

fmt_window_snapshot() {
  python3 - "$1" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for w in d['windows']:
    g = w['geometry']
    print(f"{w['class']:<40} {g['w']}x{g['h']}+{g['x']}+{g['y']}  ws{w['desktop']}")
    print(f"   {w['title'][:90]}")
PYEOF
}
export -f fmt_window_snapshot

preview_windows_row() {
  if [ "$1" = "__SAVE_NOW__" ]; then
    echo "Creates a fresh snapshot of currently open windows"
    echo "(class, geometry, workspace, relaunch command)."
  else
    fmt_window_snapshot "$1"
  fi
}
export -f preview_windows_row

list_windows() {
  local files
  files=$(ls -t "$WINSESS_HIST"/windows_*.json 2>/dev/null)
  [ -n "$files" ] || return
  echo "$files" | while read -r f; do
    ts=$(basename "$f" | sed 's/windows_//; s/\.json//')
    n=$(python3 -c "import json;print(len(json.load(open('$f'))['windows']))" 2>/dev/null || echo '?')
    printf '%s  (%s windows)\t%s\n' "$(human_ts "$ts")" "$n" "$f"
  done
}
export -f list_windows

restore_windows() {
  local f="$1"
  [ -n "$f" ] || return
  echo "Restoring window positions from: $(basename "$f")"
  echo "(relaunches any app whose class isn't already open at least as many"
  echo " times as was saved, then moves it to its saved spot; already-open"
  echo " windows are left alone)"
  cp "$f" "$WINSESS_LATEST"
  bash "$WINSESS_RESTORE"
  pause
}
export -f restore_windows

delete_windows() {
  local f="$1"
  [ -n "$f" ] || return
  confirm "Delete snapshot $(basename "$f")?" || { echo cancelled; sleep 1; return; }
  rm -f "$f"
  sleep 1
}
export -f delete_windows

save_windows_now() { bash "$WINSESS_SAVE"; }
export -f save_windows_now

windows_action_menu() {
  local f="$1"
  local choice
  choice=$(menu_pick "acting on: $(basename "$f")" \
    "Restore this snapshot" "Delete this snapshot" "Back")
  case "$choice" in
    "Restore this snapshot") restore_windows "$f" ;;
    "Delete this snapshot") delete_windows "$f" ;;
  esac
}

browse_windows() {
  while true; do
    local sel path
    sel=$( { printf '\xe2\x98\x85 save a new snapshot now\t__SAVE_NOW__\n'; list_windows; } \
      | fzf --delimiter='\t' --with-nth=1 \
        --header 'window-position snapshots  (enter:choose  tab/shift-tab:move  esc:back)' \
        --preview 'preview_windows_row {2}' --preview-window=right:65% \
        "${FZF_NAV[@]}" )
    [ -n "$sel" ] || return
    path=$(printf '%s' "$sel" | cut -f2)
    if [ "$path" = "__SAVE_NOW__" ]; then
      save_windows_now
    else
      windows_action_menu "$path"
    fi
  done
}

# ---------- wezterm panes ----------

fmt_wezterm_row() {
  python3 - "$1" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
by_win = {}
for p in d.get('panes', []):
    by_win.setdefault(p['window_id'], []).append(p)
for win_id, panes in by_win.items():
    print(f"window {win_id}:")
    for p in panes:
        print(f"  {p.get('tty_name','?'):<14} {p.get('cwd','?')}")
PYEOF
}
export -f fmt_wezterm_row

preview_wezterm_row() {
  if [ "$1" = "__SAVE_NOW__" ]; then
    echo "Creates a fresh snapshot of current wezterm panes (tty, cwd,"
    echo "window/tab grouping) via 'wezterm cli list'."
  else
    fmt_wezterm_row "$1"
  fi
}
export -f preview_wezterm_row

list_wezterm() {
  local files
  files=$(ls -t "$WEZTERM_HIST"/wezterm-tabs_*.json 2>/dev/null)
  [ -n "$files" ] || return
  echo "$files" | while read -r f; do
    ts=$(basename "$f" | sed 's/wezterm-tabs_//; s/\.json//')
    n=$(python3 -c "import json;print(len(json.load(open('$f'))['panes']))" 2>/dev/null || echo '?')
    printf '%s  (%s panes)\t%s\n' "$(human_ts "$ts")" "$n" "$f"
  done
}
export -f list_wezterm

restore_wezterm() {
  local f="$1"
  [ -n "$f" ] || return
  echo "Restoring ONE wezterm pane (the most recently active) from: $(basename "$f")"
  echo
  echo "Deliberately restores only one window, not the full saved set -"
  echo "wezterm-mux-server has a real bug where spawning more than one new"
  echo "window in a row without a GUI actively attached corrupts its"
  echo "internal state (confirmed via a panic in its own log). See the"
  echo "repo README for details. This may also simply fail (a [FAIL] line,"
  echo "nothing opened) - that's the known/expected failure mode, not"
  echo "something gone wrong on your end."
  confirm "Proceed?" || { echo cancelled; sleep 1; return; }
  cp "$f" "$WEZTERM_LATEST"
  bash "$WEZTERM_RESTORE"
  pause
}
export -f restore_wezterm

delete_wezterm() {
  local f="$1"
  [ -n "$f" ] || return
  confirm "Delete snapshot $(basename "$f")?" || { echo cancelled; sleep 1; return; }
  rm -f "$f"
  sleep 1
}
export -f delete_wezterm

save_wezterm_now() { bash "$WEZTERM_SAVE"; }
export -f save_wezterm_now

wezterm_action_menu() {
  local f="$1"
  local choice
  choice=$(menu_pick "acting on: $(basename "$f")" \
    "Restore this snapshot (single pane, experimental)" "Delete this snapshot" "Back")
  case "$choice" in
    "Restore this snapshot (single pane, experimental)") restore_wezterm "$f" ;;
    "Delete this snapshot") delete_wezterm "$f" ;;
  esac
}

browse_wezterm() {
  while true; do
    local sel path
    sel=$( { printf '\xe2\x98\x85 save a new snapshot now\t__SAVE_NOW__\n'; list_wezterm; } \
      | fzf --delimiter='\t' --with-nth=1 \
        --header 'wezterm panes  (restore is single-pane/experimental - see README)  (enter:choose  tab/shift-tab:move  esc:back)' \
        --preview 'preview_wezterm_row {2}' --preview-window=right:65% \
        "${FZF_NAV[@]}" )
    [ -n "$sel" ] || return
    path=$(printf '%s' "$sel" | cut -f2)
    if [ "$path" = "__SAVE_NOW__" ]; then
      save_wezterm_now
    else
      wezterm_action_menu "$path"
    fi
  done
}

# ---------- tilix tabs ----------

fmt_tilix_row() {
  python3 - "$1" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for t in d.get('tabs', []):
    mark = '*' if t.get('active_window') else ' '
    print(f"{mark} {t.get('tty','?'):<14} {t.get('cwd','?')}")
PYEOF
}
export -f fmt_tilix_row

preview_tilix_row() {
  if [ "$1" = "__SAVE_NOW__" ]; then
    echo "Creates a fresh snapshot of current Tilix tabs (tty, cwd) via a"
    echo "/proc walk - Tilix has no introspection API of its own."
  else
    fmt_tilix_row "$1"
  fi
}
export -f preview_tilix_row

list_tilix() {
  local files
  files=$(ls -t "$TILIX_HIST"/tilix-tabs_*.json 2>/dev/null)
  [ -n "$files" ] || return
  echo "$files" | while read -r f; do
    ts=$(basename "$f" | sed 's/tilix-tabs_//; s/\.json//')
    n=$(python3 -c "import json;print(len(json.load(open('$f'))['tabs']))" 2>/dev/null || echo '?')
    printf '%s  (%s tabs)\t%s\n' "$(human_ts "$ts")" "$n" "$f"
  done
}
export -f list_tilix

restore_tilix() {
  local f="$1"
  [ -n "$f" ] || return
  echo "Restoring Tilix tabs from: $(basename "$f")"
  echo "(each saved tab reopens as its own new Tilix window at its last"
  echo " cwd - Tilix's CLI can't chain multiple tabs into one window the"
  echo " way gnome-terminal's --tab flag can)"
  confirm "Proceed?" || { echo cancelled; sleep 1; return; }
  cp "$f" "$TILIX_LATEST"
  bash "$WINSESS_RESTORE" --only-class tilix
  pause
}
export -f restore_tilix

delete_tilix() {
  local f="$1"
  [ -n "$f" ] || return
  confirm "Delete snapshot $(basename "$f")?" || { echo cancelled; sleep 1; return; }
  rm -f "$f"
  sleep 1
}
export -f delete_tilix

save_tilix_now() { bash "$TILIX_SAVE"; }
export -f save_tilix_now

tilix_action_menu() {
  local f="$1"
  local choice
  choice=$(menu_pick "acting on: $(basename "$f")" \
    "Restore this snapshot" "Delete this snapshot" "Back")
  case "$choice" in
    "Restore this snapshot") restore_tilix "$f" ;;
    "Delete this snapshot") delete_tilix "$f" ;;
  esac
}

browse_tilix() {
  while true; do
    local sel path
    sel=$( { printf '\xe2\x98\x85 save a new snapshot now\t__SAVE_NOW__\n'; list_tilix; } \
      | fzf --delimiter='\t' --with-nth=1 \
        --header 'tilix tabs  (* = currently-focused tab)  (enter:choose  tab/shift-tab:move  esc:back)' \
        --preview 'preview_tilix_row {2}' --preview-window=right:65% \
        "${FZF_NAV[@]}" )
    [ -n "$sel" ] || return
    path=$(printf '%s' "$sel" | cut -f2)
    if [ "$path" = "__SAVE_NOW__" ]; then
      save_tilix_now
    else
      tilix_action_menu "$path"
    fi
  done
}

# ---------- scrollback logs ----------

list_logs() {
  local files
  files=$(ls -t "$TMUX_LOGS"/*.log 2>/dev/null)
  [ -n "$files" ] || return
  echo "$files" | while read -r f; do
    sz=$(du -h "$f" | cut -f1)
    mt=$(date -r "$f" '+%Y-%m-%d %H:%M:%S')
    printf '%s  %s  (%s)\t%s\n' "$(basename "$f")" "$mt" "$sz" "$f"
  done
}
export -f list_logs

delete_log() {
  local f="$1"
  [ -n "$f" ] || return
  confirm "Delete log $(basename "$f")?" || { echo cancelled; sleep 1; return; }
  rm -f "$f"
  sleep 1
}
export -f delete_log

log_action_menu() {
  local f="$1"
  local choice
  choice=$(menu_pick "acting on: $(basename "$f")" \
    "View in less" "Delete this log" "Back")
  case "$choice" in
    "View in less") less -R "$f" ;;
    "Delete this log") delete_log "$f" ;;
  esac
}

browse_logs() {
  while true; do
    if [ -z "$(list_logs)" ]; then echo "no scrollback logs yet"; sleep 1; return; fi
    local sel path
    sel=$(list_logs | fzf --delimiter='\t' --with-nth=1 \
      --header 'scrollback logs  (enter:choose  tab/shift-tab:move  esc:back)' \
      --preview 'tail -c 4000 {2} | cat -v' --preview-window=right:65% \
      "${FZF_NAV[@]}")
    [ -n "$sel" ] || return
    path=$(printf '%s' "$sel" | cut -f2)
    log_action_menu "$path"
  done
}

# ---------- top level ----------

main_menu() {
  printf 'tmux/byobu layout snapshots\nwindow-position snapshots\nwezterm panes\ntilix tabs\nscrollback logs\n' \
    | fzf --header 'view/manage saved sessions  (enter:choose  tab/shift-tab:move  esc:quit)' \
      "${FZF_NAV[@]}"
}

case "${1:-}" in
  tmux) browse_resurrect ;;
  windows) browse_windows ;;
  wezterm) browse_wezterm ;;
  tilix) browse_tilix ;;
  logs) browse_logs ;;
  *)
    while true; do
      choice=$(main_menu)
      case "$choice" in
        "tmux/byobu layout snapshots") browse_resurrect ;;
        "window-position snapshots") browse_windows ;;
        "wezterm panes") browse_wezterm ;;
        "tilix tabs") browse_tilix ;;
        "scrollback logs") browse_logs ;;
        *) break ;;
      esac
    done
    ;;
esac
