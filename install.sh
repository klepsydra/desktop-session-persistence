#!/bin/bash
# Symlinks this repo's files into place. Safe to re-run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REPO="$(pwd)"

link() {
  local src="$REPO/$1" dest="$HOME/$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "skip (real file exists, not overwriting): $dest"
    return
  fi
  ln -sfn "$src" "$dest"
  echo "linked: $dest -> $src"
}

link tmux/tmux.conf .tmux.conf
link tmux/byobu-include.tmux.conf .config/byobu/.tmux.conf
link tmux/scripts/replay-logs.sh .tmux/scripts/replay-logs.sh

link window-session/window-session-save.sh .local/bin/window-session-save.sh
link window-session/window-session-restore.sh .local/bin/window-session-restore.sh
link window-session/gterm-tabs-save.sh .local/bin/gterm-tabs-save.sh
link window-session/session-browser.sh .local/bin/session-browser.sh
link wezterm/wezterm-tabs-save.sh .local/bin/wezterm-tabs-save.sh
link wezterm/wezterm-tabs-restore.sh .local/bin/wezterm-tabs-restore.sh
link tilix/tilix-tabs-save.sh .local/bin/tilix-tabs-save.sh
chmod +x "$HOME/.local/bin/window-session-save.sh" "$HOME/.local/bin/window-session-restore.sh" \
  "$HOME/.local/bin/gterm-tabs-save.sh" "$HOME/.local/bin/session-browser.sh" \
  "$HOME/.local/bin/wezterm-tabs-save.sh" "$HOME/.local/bin/wezterm-tabs-restore.sh" \
  "$HOME/.local/bin/tilix-tabs-save.sh"
chmod +x "$HOME/.tmux/scripts/replay-logs.sh"

link wezterm/wezterm.lua .config/wezterm/wezterm.lua

link systemd/user/tmux-resurrect-save.service .config/systemd/user/tmux-resurrect-save.service
link systemd/user/tmux-resurrect-save.timer .config/systemd/user/tmux-resurrect-save.timer
link systemd/user/window-session-save.service .config/systemd/user/window-session-save.service
link systemd/user/window-session-save.timer .config/systemd/user/window-session-save.timer
link systemd/user/window-session-sentinel.service .config/systemd/user/window-session-sentinel.service
link systemd/user/wezterm-mux-server.service .config/systemd/user/wezterm-mux-server.service

link autostart/window-session-restore.desktop .config/autostart/window-session-restore.desktop
link autostart/wezterm.desktop .config/autostart/wezterm.desktop

mkdir -p "$HOME/.tmux/logs" "$HOME/.local/share/window-session"

echo
echo "Done. Next steps (not run automatically):"
echo "  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm"
echo "  ~/.tmux/plugins/tpm/bin/install_plugins"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable --now tmux-resurrect-save.timer"
echo "  systemctl --user enable --now window-session-save.timer"
echo "  systemctl --user enable --now window-session-sentinel.service"
echo "  systemctl --user enable --now wezterm-mux-server.service"
echo
echo "WezTerm itself isn't installed by this script - add the official apt"
echo "repo first (see https://wezterm.org/install/linux.html), or 'apt"
echo "install tilix' for Tilix. To make WezTerm the default terminal:"
echo "  sudo update-alternatives --set x-terminal-emulator /usr/bin/open-wezterm-here"
echo "  gsettings set org.cinnamon.desktop.default-applications.terminal exec 'wezterm'"
echo "  gsettings set org.cinnamon.desktop.default-applications.terminal exec-arg '--'"
