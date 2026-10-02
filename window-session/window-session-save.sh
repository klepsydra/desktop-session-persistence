#!/bin/bash
# Snapshot open windows (class, geometry, workspace, relaunch command) to JSON.
# Run periodically and on logout; paired with window-session-restore.sh.
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"

if "$HOME/.local/bin/dsp-enabled" windows; then
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

result = subprocess.run(['wmctrl', '-lpxG'], capture_output=True, text=True)
if result.returncode != 0:
    sys.stderr.write(
        f"wmctrl failed ({result.stderr.strip() or 'no error message'}); "
        "leaving the previous saved window list untouched. Is DISPLAY set "
        "correctly?\n"
    )
    sys.exit(1)

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

# Keep a rotating history of snapshots (last 20, skipping ones identical to
# the prior save) so they're browsable later.
"$HOME/.local/bin/history-snapshot.sh" "$OUT" "$HOME/.local/share/window-session/history" windows json
fi

# Best-effort gnome-terminal tab/cwd capture (separate script - see there
# for what it can/can't recover).
"$HOME/.local/bin/gterm-tabs-save.sh" || true

# wezterm pane/cwd capture (separate script - see there for what it can/
# can't recover, and why restore is manual-only rather than automatic).
"$HOME/.local/bin/wezterm-tabs-save.sh" || true

# Tilix tab/cwd capture (separate script - proc-based, same approach as
# gnome-terminal since Tilix has no equivalent to wezterm's `cli list`).
"$HOME/.local/bin/tilix-tabs-save.sh" || true
