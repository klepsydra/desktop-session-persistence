#!/bin/bash
# Interactive fzf browser over everything the session-persistence setup saves:
# tmux/byobu layout snapshots, window-position snapshots, and per-pane
# scrollback logs.
set -uo pipefail
export SHELL=bash

RESURRECT_DIR="$HOME/.local/share/tmux/resurrect"
WINSESS_HIST="$HOME/.local/share/window-session/history"
TMUX_LOGS="$HOME/.tmux/logs"

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

browse_resurrect() {
  [ -d "$RESURRECT_DIR" ] || { echo "no tmux-resurrect snapshots yet"; return; }
  local files
  files=$(ls -t "$RESURRECT_DIR"/tmux_resurrect_*.txt 2>/dev/null)
  [ -n "$files" ] || { echo "no tmux-resurrect snapshots yet"; return; }

  local last_target
  last_target=$(readlink -f "$RESURRECT_DIR/last" 2>/dev/null || true)

  echo "$files" | while read -r f; do
    ts=$(basename "$f" | sed 's/tmux_resurrect_//; s/\.txt//')
    mark=" "
    [ "$f" = "$last_target" ] && mark="*"
    printf '%s %s\t%s\n' "$mark" "$ts" "$f"
  done | fzf --delimiter='\t' --with-nth=1 \
    --header 'tmux/byobu layout snapshots  (* = "last", used on next tmux restore)' \
    --preview 'fmt_resurrect {2}' \
    --preview-window=right:65%
}

browse_windows() {
  [ -d "$WINSESS_HIST" ] || { echo "no window-position snapshots yet"; return; }
  local files
  files=$(ls -t "$WINSESS_HIST"/windows_*.json 2>/dev/null)
  [ -n "$files" ] || { echo "no window-position snapshots yet"; return; }

  echo "$files" | while read -r f; do
    ts=$(basename "$f" | sed 's/windows_//; s/\.json//')
    n=$(python3 -c "import json;print(len(json.load(open('$f'))['windows']))" 2>/dev/null || echo '?')
    printf '%s (%s windows)\t%s\n' "$ts" "$n" "$f"
  done | fzf --delimiter='\t' --with-nth=1 \
    --header 'window-position snapshots' \
    --preview 'fmt_window_snapshot {2}' \
    --preview-window=right:65%
}

browse_logs() {
  [ -d "$TMUX_LOGS" ] || { echo "no scrollback logs yet"; return; }
  local files
  files=$(ls -t "$TMUX_LOGS"/*.log 2>/dev/null)
  [ -n "$files" ] || { echo "no scrollback logs yet"; return; }

  local pick
  pick=$(echo "$files" | while read -r f; do
    sz=$(du -h "$f" | cut -f1)
    mt=$(date -r "$f" '+%Y-%m-%d %H:%M')
    printf '%s  (%s, updated %s)\t%s\n' "$(basename "$f")" "$sz" "$mt" "$f"
  done | fzf --delimiter='\t' --with-nth=1 \
    --header 'scrollback logs (enter to open full log in less)' \
    --preview 'tail -c 4000 {2} | cat -v' \
    --preview-window=right:65%)

  [ -n "$pick" ] || return
  less -R "$(echo "$pick" | cut -f2)"
}

main_menu() {
  printf 'tmux/byobu layout snapshots\nwindow-position snapshots\nscrollback logs\n' \
    | fzf --header 'view saved sessions - pick a category (esc to quit)'
}

case "${1:-}" in
  tmux) browse_resurrect ;;
  windows) browse_windows ;;
  logs) browse_logs ;;
  *)
    choice=$(main_menu)
    case "$choice" in
      "tmux/byobu layout snapshots") browse_resurrect ;;
      "window-position snapshots") browse_windows ;;
      "scrollback logs") browse_logs ;;
    esac
    ;;
esac
