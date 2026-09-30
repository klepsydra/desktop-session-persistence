#!/bin/bash
# tmux-resurrect's own save.sh always writes a new timestamped file, with
# no check for whether anything actually changed. This wraps it: if the
# save it just produced is byte-identical to the one before it, remove the
# new (redundant) file and point 'last' back at the surviving older one.
set -uo pipefail

RESURRECT_DIR="$HOME/.local/share/tmux/resurrect"
SAVE_SCRIPT="$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh"

before=$(ls -t "$RESURRECT_DIR"/tmux_resurrect_*.txt 2>/dev/null | head -1)

bash "$SAVE_SCRIPT" "$@"

after=$(ls -t "$RESURRECT_DIR"/tmux_resurrect_*.txt 2>/dev/null | head -1)

if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ] && cmp -s "$before" "$after"; then
  rm -f "$after"
  ln -sfn "$before" "$RESURRECT_DIR/last"
fi
