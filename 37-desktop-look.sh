#!/usr/bin/env bash
# Desktop look, "Gooey everywhere": the Ptyxis terminal's Gooey palette (navy #0D101B, blue #6488C4,
# off-white #EBEEF9) and its blur carried over to the GNOME shell, the GNOME apps, Firefox, OnlyOffice
# and Neovim. Per-user settings, so the apps' own preferences can change them later.
# Called by 30-user.sh after 31 (installs the extensions) and 36 (terminal); safe to rerun:
#   bash 37-desktop-look.sh
# Asks for sudo only to install papirus-icon-theme when no Papirus icons are present.
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "!! Run this as your normal user, WITHOUT sudo (it asks for sudo itself when needed)."; exit 1; }
KIT="$(cd "$(dirname "$0")" && pwd)"
DOT="$KIT/dotfiles"
EXT=~/.local/share/gnome-shell/extensions
WALLPAPER_URL=https://w.wallhaven.cc/full/72/wallhaven-72mrmv.jpg
WALLPAPER_SHA256=9045b1023969660f48c0f5ba4a9710427c7ecbd7fe75bec09acea3d00e61d600

# dconf needs the user session bus (unlike gsettings it fails loudly without one)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
[[ -S $XDG_RUNTIME_DIR/bus ]] || { echo "!! no user D-Bus at $XDG_RUNTIME_DIR/bus - run this inside your GNOME session"; exit 1; }

BAD=0
put() {  # src dest - keeps your old file as .bak when it differs
  mkdir -p "$(dirname "$2")"
  if [[ -f $2 ]] && ! cmp -s "$1" "$2"; then cp "$2" "$2.bak"; echo "  kept your old $2 as $2.bak"; fi
  install -m 644 "$1" "$2"; echo "  $2"
}
same() {  # dconf prints 0.7 as 0.69999999999999996, so numbers are compared as numbers
  [[ $1 == "$2" || $1 == "${2#uint32 }" ]] && return 0
  python3 -c 'import sys; sys.exit(float(sys.argv[1]) != float(sys.argv[2]))' "$1" "$2" 2>/dev/null
}
set_key() {  # path value(GVariant text) - write, then read back
  dconf write "$1" "$2"
  local got; got=$(dconf read "$1")
  if same "$got" "$2"; then printf '  ok  %s = %s\n' "$1" "$got"
  else printf '  !!  %s = %s (expected %s)\n' "$1" "$got" "$2"; BAD=1; fi
}
load_ini() {  # dconf-dir file.ini - merge the file's keys into dconf, then check every key via dconf dump
  dconf load "$1" <"$2"
  python3 - "$2" "$(dconf dump "$1")" <<'EOF' || BAD=1
import configparser, sys
def parse(text):
    c = configparser.ConfigParser(delimiters=("=",), interpolation=None, strict=False)
    c.optionxform = str
    c.read_string(text)
    return c
want, have = parse(open(sys.argv[1]).read()), parse(sys.argv[2])
bad = n = 0
for s in want.sections():
    for k, v in want[s].items():
        n += 1
        got = have[s].get(k) if have.has_section(s) else None
        if got != v:
            print(f"  !!  [{s}] {k} = {str(got)[:60]} (expected {v[:60]})")
            bad = 1
if not bad:
    print(f"  ok  {n} keys from {sys.argv[1].rsplit('/', 1)[-1]}")
sys.exit(bad)
EOF
}

echo "== Blur my Shell: live blur behind the terminal, Files and Firefox; wallpaper-only blur on the top bar"
# Measured on this laptop: live blur on every app + top bar cost ~4 W; this set costs ~0 W idle,
# ~1.2 W while the terminal scrolls, and ~1.4-2 W while a blurred Firefox is visible.
[[ -d $EXT/blur-my-shell@aunetx ]] || echo "  !! Blur my Shell is not installed yet - run 31-gnome-settings.sh (settings are stored anyway)"
load_ini /org/gnome/shell/extensions/blur-my-shell/ "$DOT/dconf/blur-my-shell.ini"

echo "== Tiling Shell layouts"
load_ini /org/gnome/shell/extensions/tilingshell/ "$DOT/dconf/tilingshell.ini"

echo "== Icons: Papirus-Dark"
if [[ ! -d ~/.local/share/icons/Papirus-Dark && ! -d /usr/share/icons/Papirus-Dark ]]; then
  sudo apt-get install -y papirus-icon-theme
fi
set_key /org/gnome/desktop/interface/icon-theme "'Papirus-Dark'"

echo "== Top bar and fonts: 24 h clock, battery percentage, Cantarell 12"
set_key /org/gnome/desktop/interface/clock-format "'24h'"
set_key /org/gnome/desktop/interface/show-battery-percentage true
set_key /org/gnome/desktop/interface/font-name "'Cantarell 12'"

echo "== Wallpaper (wallhaven 72mrmv, 16:10)"
shopt -s nullglob; have=(~/.local/share/backgrounds/*wallhaven-72mrmv.jpg); shopt -u nullglob
if (( ${#have[@]} )); then
  WP=${have[0]}
else
  WP=~/.local/share/backgrounds/wallhaven-72mrmv.jpg
  mkdir -p "$(dirname "$WP")"
  curl -fsSL "$WALLPAPER_URL" -o "$WP.part"
  echo "$WALLPAPER_SHA256  $WP.part" | sha256sum -c --quiet - || { rm -f "$WP.part"; echo "  !! wallpaper checksum mismatch"; exit 1; }
  mv "$WP.part" "$WP"
fi
set_key /org/gnome/desktop/background/picture-uri "'file://$WP'"
set_key /org/gnome/desktop/background/picture-uri-dark "'file://$WP'"

echo "== GNOME apps (GTK4 / libadwaita): Gooey navy, Files see-through + blurred"
put "$DOT/gtk-4.0/gtk.css" ~/.config/gtk-4.0/gtk.css

echo "== Neovim: tokyonight recoloured with the terminal's Gooey colours, transparent background"
if [[ -d ~/.config/nvim/lua/plugins ]]; then put "$DOT/nvim/lua/plugins/colorscheme.lua" ~/.config/nvim/lua/plugins/colorscheme.lua
else echo "  no ~/.config/nvim yet (30-user.sh installs LazyVim with this file)"; fi

echo "== Firefox ESR: solid navy header, 70% navy page area blurred by Blur my Shell"
shopt -s nullglob; profiles=(~/.mozilla/firefox/*.default-esr); shopt -u nullglob
if (( ${#profiles[@]} )); then
  for p in "${profiles[@]}"; do
    put "$DOT/firefox/user.js" "$p/user.js"
    put "$DOT/firefox/chrome/userChrome.css" "$p/chrome/userChrome.css"
    put "$DOT/firefox/chrome/userContent.css" "$p/chrome/userContent.css"
  done
  echo "  Restart Firefox to load it: Ctrl+Q, reopen, then History -> Restore Previous Session."
else
  echo "  !! no Firefox ESR profile yet: start Firefox once, close it, then rerun this script"; BAD=1
fi

echo "== ONLYOFFICE: Gooey interface theme (colours + Cantarell)"
put "$DOT/onlyoffice/Gooey.json" ~/.local/share/onlyoffice/Gooey.json
OO=~/.local/share/onlyoffice/desktopeditors/uithemes/Gooey.json
if [[ -f $OO ]]; then
  put "$DOT/onlyoffice/Gooey.json" "$OO"   # the copy ONLYOFFICE made when the theme was imported
else
  echo "  Import it once: ONLYOFFICE -> Settings -> Interface theme -> add theme,"
  echo "  Ctrl+L, paste ~/.local/share/onlyoffice/Gooey.json, then pick 'Gooey'."
fi

echo
(( ! BAD )) || { echo "!! Some settings above did not stick (lines with !!)."; exit 1; }
echo "Done. The shell picks up the Gooey Shell extension and blur at the next login; GNOME apps,"
echo "Firefox and ONLYOFFICE when they are restarted (Files keeps running in the background: nautilus -q)."
