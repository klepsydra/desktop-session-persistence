#!/bin/bash
# Snapshot open windows (class, geometry, workspace, relaunch command) to JSON.
# Run periodically and on logout; paired with window-session-restore.sh.
set -euo pipefail

OUT="$HOME/.local/share/window-session/windows.json"
TMP="$OUT.tmp.$$"

python3 - "$TMP" <<'PYEOF'
import json, re, subprocess, sys, os

out_path = sys.argv[1]

# Window classes that are desktop chrome / already-running singletons -
# never relaunch these, just skip them.
SKIP_CLASS_RE = re.compile(
    r'nemo-desktop|cairo-dock|^cinnamon|panel|applet|Xfdesktop|plank|^Guake',
    re.IGNORECASE,
)

def read_cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            raw = f.read()
        parts = [p for p in raw.split(b'\x00') if p]
        return [p.decode('utf-8', 'replace') for p in parts]
    except OSError:
        return None

result = subprocess.run(
    ['wmctrl', '-lpxG'], capture_output=True, text=True, check=True
)

windows = []
for line in result.stdout.splitlines():
    # id desktop pid x y w h wm_class host title...
    fields = line.split(None, 8)
    if len(fields) < 9:
        continue
    win_id, desktop, pid, x, y, w, h, wm_class, rest = fields
    title = rest.split(None, 1)[1] if ' ' in rest else ''
    try:
        pid = int(pid)
    except ValueError:
        pid = -1

    if SKIP_CLASS_RE.search(wm_class):
        continue
    if int(desktop) < 0:
        continue

    cmdline = read_cmdline(pid) if pid > 0 else None

    windows.append({
        'class': wm_class,
        'title': title,
        'desktop': int(desktop),
        'geometry': {'x': int(x), 'y': int(y), 'w': int(w), 'h': int(h)},
        'pid': pid,
        'cmdline': cmdline,
    })

with open(out_path, 'w') as f:
    json.dump({'windows': windows}, f, indent=2)
PYEOF

mv "$TMP" "$OUT"
