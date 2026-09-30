#!/bin/bash
# Best-effort snapshot of gnome-terminal tabs: for every live shell directly
# attached to a gnome-terminal-server process, record its tty and current
# working directory. Paired with window-session-restore.sh, which uses this
# to reopen that many tabs at their last directories.
#
# Known limits: gnome-terminal-server is a single shared process for every
# window, so which tabs belonged to which window can't be recovered - on
# restore they're all consolidated into one new window. Only cwd is
# recovered, not scrollback or whatever foreground command was running.
set -euo pipefail

OUT_DIR="$HOME/.local/share/window-session"
HIST_DIR="$OUT_DIR/history"
mkdir -p "$OUT_DIR" "$HIST_DIR"

TMP="$OUT_DIR/gterm-tabs.json.tmp.$$"

python3 - "$TMP" <<'PYEOF'
import glob, json, os, re, subprocess, sys

out_path = sys.argv[1]

def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None

def gnome_terminal_server_pids():
    # /proc/<pid>/comm truncates to 15 chars, so "gnome-terminal-server" (22
    # chars) is unreadable there - use cmdline's argv[0] basename instead.
    pids = []
    for p in glob.glob('/proc/[0-9]*/cmdline'):
        data = read(p)
        if not data:
            continue
        argv0 = data.split('\x00', 1)[0]
        if os.path.basename(argv0) == 'gnome-terminal-server':
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

# ttys that are the currently-focused tab of some gnome-terminal window
# (recoverable from the window title, which gnome-terminal sets from the
# shell prompt - best-effort signal, not used for anything critical).
active_ttys = set()
try:
    r = subprocess.run(['wmctrl', '-lx'], capture_output=True, text=True, check=True)
    for line in r.stdout.splitlines():
        if 'gnome-terminal-server' in line:
            m = re.search(r'(/dev/pts/\d+)', line)
            if m:
                active_ttys.add(m.group(1))
except (subprocess.CalledProcessError, FileNotFoundError):
    pass

def tty_num(tty):
    m = re.search(r'(\d+)$', tty or '')
    return int(m.group(1)) if m else 10**9

tabs = []
for server_pid in gnome_terminal_server_pids():
    for child in children_of(server_pid):
        tty = tty_of(child)
        if not tty:
            continue
        cwd = cwd_of(child)
        if not cwd:
            continue
        tabs.append({'tty': tty, 'cwd': cwd, 'active_window': tty in active_ttys})

# Ascending tty order: on restore, reopening in this same order gives the
# best (still not guaranteed) chance devpts hands back the same low pty
# numbers, since it reuses the lowest free one each time.
tabs.sort(key=lambda t: tty_num(t['tty']))

with open(out_path, 'w') as f:
    json.dump({'tabs': tabs}, f, indent=2)
PYEOF

LATEST="$OUT_DIR/gterm-tabs.json"
mv "$TMP" "$LATEST"

"$HOME/.local/bin/history-snapshot.sh" "$LATEST" "$HIST_DIR" gterm-tabs json
