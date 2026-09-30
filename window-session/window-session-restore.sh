#!/bin/bash
# Relaunch apps recorded by window-session-save.sh and move them back to
# their saved geometry/workspace. Skips any class that already has at least
# as many open windows as were saved (treated as "already restored").
#
# Usage: window-session-restore.sh [--dry-run] [--only-class SUBSTRING]
set -uo pipefail
export DISPLAY="${DISPLAY:-:0}"

DRY_RUN=0
ONLY_CLASS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --only-class) ONLY_CLASS="$2"; shift ;;
  esac
  shift
done

IN="$HOME/.local/share/window-session/windows.json"
[ -f "$IN" ] || { echo "no saved session at $IN"; exit 0; }

export DRY_RUN ONLY_CLASS

python3 - "$IN" <<'PYEOF'
import json, os, re, subprocess, sys, time

in_path = sys.argv[1]
dry_run = os.environ.get('DRY_RUN') == '1'
only_class = os.environ.get('ONLY_CLASS', '')

with open(in_path) as f:
    saved = json.load(f)['windows']

if only_class:
    saved = [w for w in saved if only_class in w['class']]

def current_windows():
    r = subprocess.run(['wmctrl', '-lpxG'], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"! wmctrl failed ({r.stderr.strip() or 'no error message'}); "
              "treating as no windows open. Is DISPLAY set correctly?")
        return []
    wins = []
    for line in r.stdout.splitlines():
        fields = line.split(None, 8)
        if len(fields) < 9:
            continue
        win_id, desktop, pid, x, y, w, h, wm_class, rest = fields
        wins.append({'id': win_id, 'class': wm_class, 'desktop': int(desktop)})
    return wins

def gnome_terminal_tabs_cmd():
    # Best-effort: reopen every tab gterm-tabs-save.sh last saw, at its last
    # working directory, consolidated into one window (which tab belonged to
    # which of possibly several windows isn't recoverable - see that script).
    path = os.path.expanduser('~/.local/share/window-session/gterm-tabs.json')
    try:
        with open(path) as f:
            tabs = json.load(f).get('tabs', [])
    except (OSError, json.JSONDecodeError):
        return None
    cwds = [t['cwd'] for t in tabs if t.get('cwd') and os.path.isdir(t['cwd'])]
    if not cwds:
        return None
    cmd = ['gnome-terminal']
    for cwd in cwds:
        cmd += ['--tab', '--working-directory', cwd]
    return cmd

def load_cwds(name):
    path = os.path.expanduser(f'~/.local/share/window-session/{name}.json')
    try:
        with open(path) as f:
            tabs = json.load(f).get('tabs', [])
    except (OSError, json.JSONDecodeError):
        return []
    return [t['cwd'] for t in tabs if t.get('cwd') and os.path.isdir(t['cwd'])]

_gterm_tabs_consumed = False
_tilix_cwds = load_cwds('tilix-tabs')  # consumed one-per-window, see below

def launch_cmd_for(win):
    global _gterm_tabs_consumed, _tilix_cwds
    cls = win['class']
    cmdline = win.get('cmdline')

    if cls.startswith('gnome-terminal-server'):
        # gnome-terminal can chain multiple --tab flags into one command,
        # so all saved tabs get consolidated into this one relaunched window.
        if not _gterm_tabs_consumed:
            _gterm_tabs_consumed = True
            return gnome_terminal_tabs_cmd() or ['gnome-terminal']
        return ['gnome-terminal']

    if cls.startswith('tilix'):
        # Tilix has no equivalent chaining, so each restored window gets at
        # most one saved tab's cwd; extra missing windows fall back to a
        # bare default.
        if _tilix_cwds:
            cwd = _tilix_cwds.pop(0)
            return ['tilix', '--working-directory', cwd]
        return ['tilix']

    if not cmdline:
        return None
    return cmdline

# group saved windows by class
by_class = {}
for w in saved:
    by_class.setdefault(w['class'], []).append(w)

for cls, wins in by_class.items():
    existing = [w for w in current_windows() if w['class'] == cls]
    missing = len(wins) - len(existing)
    if missing <= 0:
        print(f"[skip] {cls}: {len(existing)} already open (saved {len(wins)})")
        continue

    to_launch = wins[len(existing):]
    for win in to_launch:
        cmd = launch_cmd_for(win)
        geom = win['geometry']
        desktop = win['desktop']
        if not cmd:
            print(f"[skip] {cls}: no relaunch command recorded")
            continue

        print(f"[launch] {cls}: {cmd} -> geometry {geom} desktop {desktop}")
        if dry_run:
            continue

        before_ids = {w['id'] for w in current_windows() if w['class'] == cls}
        subprocess.Popen(
            cmd, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        new_id = None
        for _ in range(40):  # ~20s
            time.sleep(0.5)
            after = [w for w in current_windows() if w['class'] == cls]
            after_ids = {w['id'] for w in after}
            diff = after_ids - before_ids
            if diff:
                new_id = next(iter(diff))
                break

        if not new_id:
            print(f"  ! timed out waiting for a new '{cls}' window")
            continue

        subprocess.run(['wmctrl', '-ir', new_id, '-t', str(desktop)])
        subprocess.run([
            'wmctrl', '-ir', new_id, '-e',
            f"0,{geom['x']},{geom['y']},{geom['w']},{geom['h']}",
        ])
        print(f"  -> moved {new_id} to {geom}")
PYEOF
