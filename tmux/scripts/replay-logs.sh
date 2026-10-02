#!/bin/bash
# Runs after tmux-resurrect restores panes. Prints the tail of each pane's
# persistent log back into the (freshly relaunched, empty-scrollback) pane
# so recent history is visually present again after a reboot.
LOGDIR="$HOME/.tmux/logs"
LINES=51000

# Off unless switched on in session-browser.sh -> settings. It types a
# command into each restored pane, which lands in shell history.
[ -f "$HOME/.config/desktop-session-persistence/replay-scrollback.enabled" ] || exit 0

tmux list-panes -a -F '#{session_name} #{window_index} #{pane_index} #{pane_id}' | while read -r sess win pane pane_id; do
  log="$LOGDIR/${sess}_${win}-${pane}.log"
  if [ -f "$log" ]; then
    tmux send-keys -t "$pane_id" "clear; echo '--- restored scrollback (last $LINES lines) ---'; tail -n $LINES '$log'" Enter
  fi
done
