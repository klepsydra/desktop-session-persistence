#!/bin/bash
# Reopen the most recently active wezterm pane recorded by
# wezterm-tabs-save.sh, at its last working directory.
#
# Deliberately restores only ONE window, not the full saved set. Tested
# extensively (including on wezterm-nightly): calling `wezterm cli spawn
# --new-window` more than once in a row - with or without a GUI already
# attached, with generous delays between calls - reliably corrupts
# wezterm-mux-server's internal pane/window bookkeeping: later calls return
# stale/duplicate pane ids, and with a GUI attached it can spray out a dozen
# extra empty windows. This is a real bug in wezterm's mux server, not
# something safe to script around - so rather than risk a runaway window
# explosion during an unattended login, this only ever issues a single
# spawn call. If you had several wezterm windows, only the most recent
# comes back automatically; open more normally afterwards (interactive,
# GUI-driven tab/window creation is unaffected by this - it's specifically
# rapid unattended CLI spawning that triggers it).
#
# Usage: wezterm-tabs-restore.sh [--boot]
#   --boot   only used by the login autostart entry: gated by a per-boot
#            marker so it only ever fires once per boot, and first kills
#            whatever placeholder pane wezterm-mux-server auto-spawned on
#            its own startup (freeing its tty number) before restoring.
set -uo pipefail

IN="$HOME/.local/share/window-session/wezterm-tabs.json"
MARKER="$HOME/.local/share/window-session/.wezterm-restored-boot-id"
BOOT_MODE=0
[ "${1:-}" = "--boot" ] && BOOT_MODE=1

command -v wezterm >/dev/null 2>&1 || exit 0
systemctl --user is-active --quiet wezterm-mux-server.service || exit 0
[ -f "$IN" ] || exit 0

if [ "$BOOT_MODE" -eq 1 ]; then
  boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)
  if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$boot_id" ]; then
    exit 0  # already restored this boot
  fi
fi

export BOOT_MODE MARKER

python3 - "$IN" <<'PYEOF'
import json, os, re, subprocess, sys

in_path = sys.argv[1]
boot_mode = os.environ.get('BOOT_MODE') == '1'
marker = os.environ.get('MARKER')
CLI = ['wezterm', 'cli', '--prefer-mux']

def tty_num(tty_name):
    m = re.search(r'(\d+)$', tty_name or '')
    return int(m.group(1)) if m else 10**9

def run(args, timeout=15):
    try:
        return subprocess.run(CLI + args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None

with open(in_path) as f:
    panes = json.load(f).get('panes', [])
panes = [p for p in panes if p.get('cwd') and os.path.isdir(p['cwd'])]
panes.sort(key=lambda p: tty_num(p.get('tty_name')))

if not panes:
    sys.exit(0)
primary = panes[0]

if boot_mode:
    r = run(['list', '--format', 'json'])
    if r and r.returncode == 0:
        try:
            for p in json.loads(r.stdout or '[]'):
                if p.get('tty_name'):
                    run(['kill-pane', '--pane-id', str(p['pane_id'])])
        except json.JSONDecodeError:
            pass

r = run(['spawn', '--domain-name', 'mux', '--new-window', '--cwd', primary['cwd']])
ok = r is not None and r.returncode == 0
print(f"[{'ok' if ok else 'FAIL'}] {primary['cwd']}  (was {primary.get('tty_name')})")

if boot_mode and marker:
    try:
        with open('/proc/sys/kernel/random/boot_id') as f:
            boot_id = f.read().strip()
        with open(marker, 'w') as f:
            f.write(boot_id)
    except OSError:
        pass
PYEOF
