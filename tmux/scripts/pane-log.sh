#!/bin/bash
# Start appending a pane's output to ~/.tmux/logs/<name>.log, unless the
# "logs" feature is switched off. Called from the tmux.conf hooks and from
# session-browser.sh -> settings.
# Usage: pane-log.sh <pane_id> <name>
"$HOME/.local/bin/dsp-enabled" logs || exit 0
mkdir -p "$HOME/.tmux/logs"
tmux pipe-pane -o -t "$1" "cat >> '$HOME/.tmux/logs/$2.log'"
