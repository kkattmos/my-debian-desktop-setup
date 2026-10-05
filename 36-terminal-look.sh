#!/usr/bin/env bash
# Terminal look: Ptyxis (Gooey palette, 70% opaque navy, JetBrainsMono Nerd Font) + fastfetch
# at the top of each new Ptyxis tab + cava audio visualizer. kitty with the same look for Jupyter
# notebooks in Neovim (it can draw plots inline, Ptyxis can't). Called by 30-user.sh; safe to rerun:
#   bash 36-terminal-look.sh
# Settings are YOUR (per-user) Ptyxis settings, so Ptyxis' Preferences (Ctrl+,) can change them later.
# The blur behind the window comes from Blur my Shell (31 installs it, 37 configures it).
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "!! Run this as your normal user, WITHOUT sudo (it asks for sudo itself when needed)."; exit 1; }
KIT="$(cd "$(dirname "$0")" && pwd)"
DOT="$KIT/dotfiles"
PALETTE='Gooey'         # any name from Ptyxis' Preferences -> Profiles -> palette list; the whole desktop
                        # (37-desktop-look.sh, nvim colorscheme.lua) is matched to Gooey's colours
OPACITY=0.70            # 1 = solid, lower = more of the blurred background shows through
FONT='JetBrainsMono Nerd Font 12'

echo "== Packages"
missing=()
for p in ptyxis fastfetch cava kitty imagemagick; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || missing+=("$p")
done
if (( ${#missing[@]} )); then sudo apt-get install -y "${missing[@]}"; else echo "  ptyxis fastfetch cava kitty imagemagick already installed"; fi

echo "== Ptyxis settings"
# dconf write needs the user session bus (unlike gsettings it fails loudly without one)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
[[ -S $XDG_RUNTIME_DIR/bus ]] || { echo "!! no user D-Bus at $XDG_RUNTIME_DIR/bus - run this inside your GNOME session"; exit 1; }
P=/org/gnome/Ptyxis
# reuse the profile Ptyxis already made (first start), else create one; Ptyxis ids are 32 hex chars
UUID=$(dconf read $P/default-profile-uuid | tr -d "'")
[[ -n $UUID ]] || UUID=$(python3 -c 'import uuid; print(uuid.uuid4().hex)')
UUIDS=$(python3 -c '
import ast, sys
cur, new = sys.argv[1].replace("@as ", ""), sys.argv[2]
l = ast.literal_eval(cur) if cur.strip() else []
print(repr(l if new in l else l + [new]))' "$(dconf read $P/profile-uuids)" "$UUID")
BAD=0
same() {  # dconf prints 0.7 as 0.69999999999999996, so numbers are compared as numbers
  [[ $1 == "$2" || $1 == "${2#uint32 }" ]] && return 0
  python3 -c 'import sys; sys.exit(float(sys.argv[1]) != float(sys.argv[2]))' "$1" "$2" 2>/dev/null
}
set_key() {  # path value(GVariant text) - write, then read back
  dconf write "$1" "$2"
  local got; got=$(dconf read "$1")
  if same "$got" "$2"; then printf '  ok  %s = %s\n' "${1#$P/}" "$got"
  else printf '  !!  %s = %s (expected %s)\n' "$1" "$got" "$2"; BAD=1; fi
}
set_key $P/profile-uuids "$UUIDS"
set_key $P/default-profile-uuid "'$UUID'"
set_key $P/Profiles/$UUID/label "'$PALETTE'"
set_key $P/Profiles/$UUID/palette "'$PALETTE'"
set_key $P/Profiles/$UUID/opacity "$OPACITY"
set_key $P/use-system-font false
set_key $P/font-name "'$FONT'"
set_key $P/interface-style "'dark'"
set_key $P/default-columns "uint32 110"
set_key $P/default-rows "uint32 32"
set_key $P/audible-bell false
(( ! BAD )) || { echo "!! some Ptyxis settings did not stick (see above)"; exit 1; }

# apps that ask for "a terminal" (Terminal=true .desktop files, xdg-terminal-exec) get Ptyxis
if [[ ! -f ~/.config/xdg-terminals.list ]]; then
  echo org.gnome.Ptyxis.desktop > ~/.config/xdg-terminals.list
  echo "  default terminal (xdg-terminal-exec): Ptyxis"
fi

echo "== fastfetch + cava configs, zshrc"
put() {  # src dest - keeps your old file as .bak when it differs
  mkdir -p "$(dirname "$2")"
  if [[ -f $2 ]] && ! cmp -s "$1" "$2"; then cp "$2" "$2.bak"; echo "  kept your old $2 as $2.bak"; fi
  install -m 644 "$1" "$2"; echo "  $2"
}
put "$DOT/fastfetch/config.jsonc" ~/.config/fastfetch/config.jsonc
put "$DOT/cava/config" ~/.config/cava/config
put "$DOT/zshrc" ~/.zshrc

echo "== kitty for notebooks (nb x.ipynb; .ipynb files from Files open there too)"
put "$DOT/kitty/kitty.conf" ~/.config/kitty/kitty.conf
put "$DOT/applications/nvim-notebook.desktop" ~/.local/share/applications/nvim-notebook.desktop
update-desktop-database ~/.local/share/applications 2>/dev/null || true
xdg-mime default nvim-notebook.desktop application/x-ipynb+json
echo "  .ipynb opens with: $(xdg-mime query default application/x-ipynb+json)"

echo
echo "Done. Open Ptyxis (Activities -> Terminal / Ptyxis). fastfetch runs at the top of each new tab;"
echo "turn that off in ~/.zshrc (FASTFETCH_ON_START=0). Audio bars: cava. Notebooks: nb x.ipynb"
