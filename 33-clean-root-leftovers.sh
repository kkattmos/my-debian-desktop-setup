#!/usr/bin/env bash
# One-off cleanup: an earlier `sudo bash 30-user.sh` installed the user setup into ROOT's home.
# Lists what that left in /root, asks, then removes only those paths and undoes root's zsh + linger.
#   sudo bash 33-clean-root-leftovers.sh
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
cd /root || exit 1

PATHS=(
  .zshrc .config/starship.toml .npmrc
  .local/opt/nvim .local/bin/nvim .local/bin/jupytext .local/bin/seadrive .local/bin/tree-sitter
  .local/lib/node_modules/tree-sitter-cli .local/share/nvim-py .local/share/jupyter
  .config/nvim .local/share/nvim .local/state/nvim .cache/nvim
  .local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf .local/share/fonts/JetBrainsMonoNerdFont-Bold.ttf
  .local/share/fonts/JetBrainsMonoNerdFont-Italic.ttf .local/share/fonts/JetBrainsMonoNerdFont-BoldItalic.ttf
  .local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com
  .config/seadrive .seadrive .config/systemd/user/seadrive.service .config/systemd/user/photoprism.service
  .config/photoprism .local/share/photoprism Pictures/import
)
found=()
for p in "${PATHS[@]}"; do [[ -e $p || -L $p ]] && found+=("$p"); done
echo "Found in /root:"; ((${#found[@]})) && du -sh "${found[@]}" 2>/dev/null | sed 's/^/  /' || echo "  (nothing)"
echo "root's shell: $(getent passwd root | cut -d: -f7)   root linger: $(loginctl show-user root -p Linger --value 2>/dev/null || echo no)"
read -rp "Remove these and reset root's shell/linger? [y/N] " a
[[ $a == [yY] ]] || exit 0

findmnt /root/SeaDrive >/dev/null 2>&1 && fusermount3 -uz /root/SeaDrive
((${#found[@]})) && rm -rf -- "${found[@]}"
rmdir /root/SeaDrive /root/Pictures 2>/dev/null
[[ $(getent passwd root | cut -d: -f7) == */zsh ]] && chsh -s /bin/bash root
loginctl disable-linger root 2>/dev/null
echo "Cleaned. root's shell: $(getent passwd root | cut -d: -f7)"
