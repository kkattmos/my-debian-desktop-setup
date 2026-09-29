#!/usr/bin/env bash
# GNOME settings + shell extensions, WITHOUT needing a D-Bus session:
#  - the extensions are unzipped straight into ~/.local/share/gnome-shell/extensions:
#    Tiling Shell, Blur my Shell, Switch Workspace (extensions.gnome.org) and the kit's own
#    Gooey Shell + Workspace Label (dotfiles/gnome-shell/extensions)
#  - the settings become system-wide dconf defaults (/etc/dconf/db/local.d), written with sudo
# Takes effect at the next login. Called by 30-user.sh; safe to run on its own any time:
#   bash 31-gnome-settings.sh
# The look (blur settings, colours, wallpaper) is 37-desktop-look.sh.
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "!! Run this as your normal user, WITHOUT sudo (it asks for sudo itself when needed)."; exit 1; }
KIT="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
EXT=~/.local/share/gnome-shell/extensions
EGO_UUIDS=(tilingshell@ferrarodomenico.com blur-my-shell@aunetx switchWorkSpace@sun.wxg@gmail.com)
OWN_UUIDS=(gooey-dock@kkattmos workspace-label@kkattmos)   # gooey-dock = "Gooey Shell" (renaming the uuid breaks a running shell)
ALL=$(printf "'%s', " "${EGO_UUIDS[@]}" "${OWN_UUIDS[@]}"); ALL="[${ALL%, }]"

for UUID in "${EGO_UUIDS[@]}"; do
  echo "== $UUID (extensions.gnome.org)"
  URL=$(curl -fsS "https://extensions.gnome.org/extension-info/?uuid=$UUID&shell_version=48" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["download_url"])')
  curl -fsSL "https://extensions.gnome.org$URL" -o "$TMP/ext.zip"
  DEST=$EXT/$UUID
  rm -rf "$DEST"; mkdir -p "$DEST"
  unzip -q "$TMP/ext.zip" -d "$DEST"
  [[ -f $DEST/metadata.json ]] || { echo "!! extension did not unpack into $DEST"; exit 1; }
  if [[ -d $DEST/schemas && ! -f $DEST/schemas/gschemas.compiled ]]; then glib-compile-schemas "$DEST/schemas"; fi
  python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print("  installed", m["uuid"], "for GNOME", ", ".join(m["shell-version"]))' "$DEST/metadata.json"
done
for UUID in "${OWN_UUIDS[@]}"; do
  echo "== $UUID (this kit)"
  mkdir -p "$EXT/$UUID"
  install -m 644 "$KIT/dotfiles/gnome-shell/extensions/$UUID"/* "$EXT/$UUID/"
  echo "  installed $UUID"
done

echo "== GNOME settings as system defaults (dconf)"
command -v dconf >/dev/null || sudo apt-get install -y dconf-cli
sudo mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
printf 'user-db:user\nsystem-db:local\n' | sudo tee /etc/dconf/profile/user >/dev/null
sudo tee /etc/dconf/db/local.d/00-debian13-setup >/dev/null <<EOF
[org/gnome/shell]
enabled-extensions=$ALL
disable-user-extensions=false

[org/gnome/desktop/input-sources]
sources=[('xkb', 'us'), ('xkb', 'th')]

[org/gnome/desktop/interface]
color-scheme='prefer-dark'
monospace-font-name='JetBrainsMono Nerd Font 11'

[org/gnome/mutter]
dynamic-workspaces=false

[org/gnome/desktop/wm/preferences]
num-workspaces=4

[org/gnome/desktop/wm/keybindings]
switch-to-workspace-1=['<Super>1']
switch-to-workspace-2=['<Super>2']
switch-to-workspace-3=['<Super>3']
switch-to-workspace-4=['<Super>4']
move-to-workspace-1=['<Super><Shift>1']
move-to-workspace-2=['<Super><Shift>2']
move-to-workspace-3=['<Super><Shift>3']
move-to-workspace-4=['<Super><Shift>4']

[org/gnome/shell/keybindings]
switch-to-application-1=@as []
switch-to-application-2=@as []
switch-to-application-3=@as []
switch-to-application-4=@as []
EOF
sudo dconf update

echo "== Verify (what GNOME will read at login)"
# GNOME writes some per-user values itself at the first login (e.g. the keyboard layout from the
# installer), and a per-user value hides the system default. If the default is right but the user
# value differs, reset the user value. (`dconf dump /` also shows system defaults, so it can't tell.)
BAD=0
check() {
  local path="/${1//.//}/$2" got user def
  got=$(gsettings get "$1" "$2" 2>&1)
  if [[ $got != "$3" ]]; then
    user=$(dconf read "$path" 2>/dev/null); def=$(dconf read -d "$path" 2>/dev/null)
    if [[ -n $user && $user != "$def" ]] && dconf reset "$path" 2>/dev/null; then
      printf '  reset your own %s (was %s)\n' "$path" "$user"
      got=$(gsettings get "$1" "$2" 2>&1)
    fi
  fi
  if [[ $got == "$3" ]]; then printf '  ok  %s %s\n' "$1" "$2"
  else printf '  !!  %s %s = %s (expected %s)\n' "$1" "$2" "$got" "$3"; BAD=1; fi
}
check org.gnome.shell enabled-extensions "$ALL"
check org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'th')]"
check org.gnome.desktop.interface color-scheme "'prefer-dark'"
check org.gnome.desktop.interface monospace-font-name "'JetBrainsMono Nerd Font 11'"
check org.gnome.mutter dynamic-workspaces "false"
check org.gnome.desktop.wm.preferences num-workspaces "4"
check org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Super>1']"
if (( BAD )); then
  echo
  echo "!! Some settings above are still wrong. A per-user value can only be reset from inside the"
  echo "   GNOME session: open a GNOME terminal there and run this script again."
  exit 1
fi
echo "All settings are in place. Log out and log back in through Ly."
