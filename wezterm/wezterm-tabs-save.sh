#!/bin/bash
# Snapshot every live wezterm pane (tty, cwd, original window/tab grouping)
# via wezterm's own `cli list --format json` - no /proc scraping needed,
# unlike the gnome-terminal/tilix tracks, because wezterm's mux server
# exposes this natively. Paired with wezterm-tabs-restore.sh.
set -euo pipefail
"$HOME/.local/bin/dsp-enabled" wezterm || exit 0
export DISPLAY="${DISPLAY:-:0}"

OUT_DIR="$HOME/.local/share/window-session"
HIST_DIR="$OUT_DIR/history"
mkdir -p "$OUT_DIR" "$HIST_DIR"

command -v wezterm >/dev/null 2>&1 || exit 0
systemctl --user is-active --quiet wezterm-mux-server.service || exit 0

TMP="$OUT_DIR/wezterm-tabs.json.tmp.$$"

python3 - "$TMP" <<'PYEOF'
import json, re, subprocess, sys
from urllib.parse import urlparse, unquote

out_path = sys.argv[1]

def cwd_path(cwd_uri):
    if not cwd_uri:
        return None
    return unquote(urlparse(cwd_uri).path) or None

def tty_num(tty_name):
    m = re.search(r'(\d+)$', tty_name or '')
    return int(m.group(1)) if m else 10**9

try:
    r = subprocess.run(['wezterm', 'cli', '--prefer-mux', 'list', '--format', 'json'],
                        capture_output=True, text=True, timeout=15, check=True)
    panes = json.loads(r.stdout or '[]')
except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
        json.JSONDecodeError, FileNotFoundError):
    panes = []

out = []
for p in panes:
    if not p.get('tty_name'):  # stale/phantom pane-table entry, no real pty
        continue
    out.append({
        'window_id': p['window_id'],
        'tab_id': p['tab_id'],
        'pane_id': p['pane_id'],
        'tty_name': p['tty_name'],
        'cwd': cwd_path(p.get('cwd')),
        'title': p.get('title', ''),
    })
out.sort(key=lambda t: tty_num(t['tty_name']))

with open(out_path, 'w') as f:
    json.dump({'panes': out}, f, indent=2)
PYEOF

LATEST="$OUT_DIR/wezterm-tabs.json"
mv "$TMP" "$LATEST"

"$HOME/.local/bin/history-snapshot.sh" "$LATEST" "$HIST_DIR" wezterm-tabs json
