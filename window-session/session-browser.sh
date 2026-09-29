#!/bin/bash
# Interactive fzf browser + manager over everything the session-persistence
# setup saves: tmux/byobu layout snapshots, window-position snapshots, and
# per-pane scrollback logs.
#
# Keys inside each list:
#   enter   restore this snapshot (tmux/windows) or view it (logs)
#   alt-s   save a new snapshot right now
#   ctrl-x  delete the selected snapshot
#   esc     back / quit
#
# (ctrl-s/ctrl-q are terminal XOFF/XON flow control, swallowed by the tty
# driver itself before any application - including fzf - ever sees them;
# that's why "save now" is alt-s instead.)
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

export RESURRECT_DIR RESURRECT_RESTORE RESURRECT_SAVE
export WINSESS_LATEST WINSESS_HIST WINSESS_RESTORE WINSESS_SAVE TMUX_LOGS

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
  echo "Restore tmux/byobu layout from: $(basename "$f")"
  echo "Creates any sessions/windows from that snapshot that aren't already"
  echo "running now. Sessions that already exist are left untouched."
  confirm "Proceed?" || { echo cancelled; sleep 1; return; }
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

browse_resurrect() {
  if [ ! -d "$RESURRECT_DIR" ] || [ -z "$(list_resurrect)" ]; then
    echo "no tmux-resurrect snapshots yet"; sleep 1; return
  fi
  list_resurrect | fzf --delimiter='\t' --with-nth=1 \
    --header 'tmux/byobu snapshots | enter:restore alt-s:save-now ctrl-x:delete esc:back  (* = "last")' \
    --preview 'fmt_resurrect {2}' --preview-window=right:65% \
    --bind 'enter:execute(restore_resurrect {2})+reload(list_resurrect)' \
    --bind 'alt-s:execute-silent(save_resurrect_now)+reload(list_resurrect)' \
    --bind 'ctrl-x:execute(delete_resurrect {2})+reload(list_resurrect)' \
    > /dev/null
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
  echo "Restore window positions from: $(basename "$f")"
  echo "Relaunches any app whose window class isn't already open at least as"
  echo "many times as was saved, then moves it to its saved spot. Windows"
  echo "already open are left alone."
  confirm "Proceed?" || { echo cancelled; sleep 1; return; }
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

browse_windows() {
  if [ ! -d "$WINSESS_HIST" ] || [ -z "$(list_windows)" ]; then
    echo "no window-position snapshots yet"; sleep 1; return
  fi
  list_windows | fzf --delimiter='\t' --with-nth=1 \
    --header 'window-position snapshots | enter:restore alt-s:save-now ctrl-x:delete esc:back' \
    --preview 'fmt_window_snapshot {2}' --preview-window=right:65% \
    --bind 'enter:execute(restore_windows {2})+reload(list_windows)' \
    --bind 'alt-s:execute-silent(save_windows_now)+reload(list_windows)' \
    --bind 'ctrl-x:execute(delete_windows {2})+reload(list_windows)' \
    > /dev/null
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

browse_logs() {
  if [ ! -d "$TMUX_LOGS" ] || [ -z "$(list_logs)" ]; then
    echo "no scrollback logs yet"; sleep 1; return
  fi
  list_logs | fzf --delimiter='\t' --with-nth=1 \
    --header 'scrollback logs | enter:view (less) ctrl-x:delete esc:back' \
    --preview 'tail -c 4000 {2} | cat -v' --preview-window=right:65% \
    --bind 'enter:execute(less -R {2})' \
    --bind 'ctrl-x:execute(delete_log {2})+reload(list_logs)' \
    > /dev/null
}

# ---------- top level ----------

main_menu() {
  printf 'tmux/byobu layout snapshots\nwindow-position snapshots\nscrollback logs\n' \
    | fzf --header 'view/manage saved sessions - pick a category (esc to quit)'
}

case "${1:-}" in
  tmux) browse_resurrect ;;
  windows) browse_windows ;;
  logs) browse_logs ;;
  *)
    while true; do
      choice=$(main_menu)
      case "$choice" in
        "tmux/byobu layout snapshots") browse_resurrect ;;
        "window-position snapshots") browse_windows ;;
        "scrollback logs") browse_logs ;;
        *) break ;;
      esac
    done
    ;;
esac
