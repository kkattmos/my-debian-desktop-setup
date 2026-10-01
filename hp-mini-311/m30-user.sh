#!/usr/bin/env bash
# HP Mini 311: run as your normal user inside the Xfce session (after m10-system.sh + reboot):
#   bash ~/debian13-setup/hp-mini-311/m30-user.sh
# Order: shell + fonts + tools, the Gooey look (m37), Tailscale, Seafile sync, then the long
# Neovim build (m31) last, so the desktop is finished before the slow part starts.
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "!! Run this as your normal user, WITHOUT sudo (it asks for sudo itself when needed)."; exit 1; }
KIT="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$KIT")"
DOT="$KIT/dotfiles"
mkdir -p ~/.local/bin ~/.local/opt ~/.config/systemd/user ~/.local/share/fonts
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
gh_asset() {  # repo asset-name dest - latest release asset, checked against GitHub's sha256 digest
  local json url sum
  json=$(curl -fsS "https://api.github.com/repos/$1/releases/latest")
  read -r url sum < <(python3 -c '
import json, sys
a = next(a for a in json.load(sys.stdin)["assets"] if a["name"] == sys.argv[1])
print(a["browser_download_url"], (a.get("digest") or "sha256:").split(":")[1])' "$2" <<<"$json")
  [[ -n $sum ]] || { echo "!! no sha256 digest published for $2"; return 1; }
  curl -fsSL "$url" -o "$3"
  echo "$sum  $3" | sha256sum -c --quiet - && echo "  $2 ($(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' <<<"$json" | sed -n 1p)) checksum ok"
}

step "User session bus (systemctl --user needs it, for the Seafile service)"
# Lingering starts your systemd user manager at boot (Seafile syncs before you log in) and
# creates /run/user/<uid>/bus; pointing this shell at it works from any terminal.
sudo loginctl enable-linger "$USER"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
for _ in $(seq 20); do [[ -S $XDG_RUNTIME_DIR/bus ]] && break; sleep 0.5; done
[[ -S $XDG_RUNTIME_DIR/bus ]] || {
  echo "!! No user D-Bus at $XDG_RUNTIME_DIR/bus."
  echo "   Run: sudo apt install dbus-user-session libpam-systemd   then log out and back in."; exit 1; }
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
systemctl --user show-environment >/dev/null || { echo "!! cannot reach your systemd user manager"; exit 1; }

step "ZSH + Powerlevel10k (prompt wizard: p10k configure)"
install -m 644 "$DOT/zshrc" ~/.zshrc
P10K=~/.local/share/powerlevel10k
if [[ -d $P10K/.git ]]; then git -C "$P10K" pull --ff-only -q
else git clone -q --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K"; fi
# p10k downloads its git-status helper (gitstatusd) itself; it has a linux-i686 build
[[ $(getent passwd "$USER" | cut -d: -f7) == */zsh ]] || chsh -s /usr/bin/zsh

step "JetBrainsMono Nerd Font (icons for LazyVim + Powerlevel10k)"
curl -fL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | \
  tar -xJ -C ~/.local/share/fonts --wildcards 'JetBrainsMonoNerdFont-Regular.ttf' 'JetBrainsMonoNerdFont-Bold.ttf' \
  'JetBrainsMonoNerdFont-Italic.ttf' 'JetBrainsMonoNerdFont-BoldItalic.ttf'
fc-cache -f ~/.local/share/fonts

step "Sarabun as the Thai fallback font"
bash "$ROOT/35-thai-font.sh"

step "fastfetch + lazygit (official 32-bit builds; not packaged in Debian 12)"
gh_asset fastfetch-cli/fastfetch fastfetch-linux-i686.tar.gz "$TMP/fastfetch.tar.gz"
rm -rf ~/.local/opt/fastfetch && mkdir -p ~/.local/opt/fastfetch
tar -xzf "$TMP/fastfetch.tar.gz" -C ~/.local/opt/fastfetch --strip-components=1
ln -sf ~/.local/opt/fastfetch/usr/bin/fastfetch ~/.local/bin/fastfetch
~/.local/bin/fastfetch --version
LG=$(curl -fsS https://api.github.com/repos/jesseduffield/lazygit/releases/latest | python3 -c 'import json,sys;print(next(a["name"] for a in json.load(sys.stdin)["assets"] if a["name"].endswith("_linux_32-bit.tar.gz")))')
gh_asset jesseduffield/lazygit "$LG" "$TMP/lazygit.tar.gz"
tar -xzf "$TMP/lazygit.tar.gz" -C ~/.local/bin lazygit
~/.local/bin/lazygit --version | sed -n 1p

step "Desktop look: Gooey theme, terminal, panels, wallpaper, blur, shortcuts, Thai keyboard"
# a wrong setting must not stop Tailscale/Seafile below; reported again at the end
LOOK_OK=1; bash "$KIT/m37-xfce-look.sh" || LOOK_OK=0

step "Tailscale (your Seafile server lives on your tailnet)"
if ! tailscale status >/dev/null 2>&1; then
  echo "Log in to Tailscale in the browser window/URL that follows:"
  sudo tailscale up
fi

step "Seafile sync client (seaf-cli; SeaDrive has no 32-bit build)"
# Libraries sync into real folders under ~/Seafile (not a virtual drive like SeaDrive on the Dell)
if [[ ! -d ~/.ccnet ]]; then
  mkdir -p ~/.local/share/seafile ~/Seafile
  seaf-cli init -d ~/.local/share/seafile
fi
install -m 644 "$DOT/systemd/seafile.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now seafile.service
sleep 3
systemctl --user is-active --quiet seafile.service || {
  echo "!! seafile.service is not running:"; systemctl --user status seafile --no-pager | tail -15; exit 1; }
if [[ -z $(seaf-cli list 2>/dev/null | sed -n '2,$p') ]]; then
  SF_URL=
  while [[ -z $SF_URL ]]; do read -rp "Seafile server URL (e.g. http://<tailscale-ip>:8000): " SF_URL; done
  read -rp  "Seafile login (username/email): " SF_USER
  read -rsp "Seafile password (used once to get a token, not stored): " SF_PW; echo
  TOKEN=$(curl -fsS -d "username=$SF_USER" --data-urlencode "password=$SF_PW" "$SF_URL/api2/auth-token/" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
  unset SF_PW
  echo "Your libraries:"
  seaf-cli list-remote -s "$SF_URL" -u "$SF_USER" -T "$TOKEN"
  echo "Type the ID of each library to sync to ~/Seafile/<name> (empty line = done)."
  echo "The disk is 320 GB but the Mini is slow: start with the libraries you need here."
  while :; do
    read -rp "Library ID: " LIB
    [[ -z $LIB ]] && break
    seaf-cli download -l "$LIB" -s "$SF_URL" -d ~/Seafile -u "$SF_USER" -T "$TOKEN" || echo "!! could not add $LIB"
  done
  unset TOKEN
fi
seaf-cli status || true

step "Neovim + LazyVim (built here - the long part, runs unattended)"
NVIM_OK=1; bash "$KIT/m31-neovim.sh" || NVIM_OK=0

echo
(( LOOK_OK )) || echo "!! The look step reported a problem (scroll up). Fix it, then rerun: bash $KIT/m37-xfce-look.sh"
(( NVIM_OK )) || echo "!! The Neovim step reported a problem (scroll up). Rerun: bash $KIT/m31-neovim.sh"
echo "Done. Log out and back in (zsh, groups and the keyboard shortcuts take effect)."
echo "Check everything afterwards with:  bash $KIT/m32-check.sh"
