#!/bin/bash
# Best-effort snapshot of Tilix tabs: same approach as
# gterm-tabs-save.sh (Tilix is also a single shared GApplication process
# across every window, and its tabs aren't separate X11 windows either).
# For every live shell directly attached to a tilix process, record its
# tty and current working directory.
#
# Known limits: same as gnome-terminal - only cwd is recovered (no
# scrollback, no foreground command), and which tab belonged to which
# window can't be recovered, so window-session-restore.sh reopens each
# saved tab as its own separate window instead.
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"

OUT_DIR="$HOME/.local/share/window-session"
HIST_DIR="$OUT_DIR/history"
mkdir -p "$OUT_DIR" "$HIST_DIR"

TMP="$OUT_DIR/tilix-tabs.json.tmp.$$"

python3 - "$TMP" <<'PYEOF'
import glob, json, os, re, subprocess, sys

out_path = sys.argv[1]

def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None

def tilix_pids():
    pids = []
    for p in glob.glob('/proc/[0-9]*/cmdline'):
        data = read(p)
        if not data:
            continue
        argv0 = data.split('\x00', 1)[0]
        if os.path.basename(argv0) == 'tilix':
            pids.append(int(p.split('/')[2]))
    return pids

def children_of(pid):
    kids = []
    for p in glob.glob('/proc/[0-9]*/stat'):
        data = read(p)
        if not data:
            continue
        rparen = data.rfind(')')
        fields = data[rparen + 2:].split()
        try:
            ppid = int(fields[1])
        except (IndexError, ValueError):
            continue
        if ppid == pid:
            kids.append(int(p.split('/')[2]))
    return kids

def tty_of(pid):
    try:
        target = os.readlink(f'/proc/{pid}/fd/0')
    except OSError:
        return None
    if target.startswith('/dev/pts/') or target.startswith('/dev/tty'):
        return target
    return None

def cwd_of(pid):
    try:
        return os.readlink(f'/proc/{pid}/cwd')
    except OSError:
        return None

def tty_num(tty):
    m = re.search(r'(\d+)$', tty or '')
    return int(m.group(1)) if m else 10**9

active_ttys = set()
try:
    r = subprocess.run(['wmctrl', '-lx'], capture_output=True, text=True, check=True)
    for line in r.stdout.splitlines():
        if 'tilix.Tilix' in line:
            m = re.search(r'(/dev/pts/\d+)', line)
            if m:
                active_ttys.add(m.group(1))
except (subprocess.CalledProcessError, FileNotFoundError):
    pass

tabs = []
for server_pid in tilix_pids():
    for child in children_of(server_pid):
        tty = tty_of(child)
        if not tty:
            continue
        cwd = cwd_of(child)
        if not cwd:
            continue
        tabs.append({'tty': tty, 'cwd': cwd, 'active_window': tty in active_ttys})

tabs.sort(key=lambda t: tty_num(t['tty']))

with open(out_path, 'w') as f:
    json.dump({'tabs': tabs}, f, indent=2)
PYEOF

LATEST="$OUT_DIR/tilix-tabs.json"
mv "$TMP" "$LATEST"

"$HOME/.local/bin/history-snapshot.sh" "$LATEST" "$HIST_DIR" tilix-tabs json
