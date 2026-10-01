#!/usr/bin/env bash
# HP Mini 311: the Dell's "Gooey" look on Xfce 4.18 - navy #0D101B, raised #1F222D, blue #6488C4,
# off-white #EBEEF9 - for GTK apps (own "Gooey" theme = Adwaita-dark recoloured), window borders,
# panels, terminal, Firefox, Neovim; frosted-glass blur from picom. Per-user settings (xfconf), so
# Xfce's own settings dialogs can change them later.
# Run as your user INSIDE the Xfce session (xfconf needs it); safe to rerun:
#   bash m37-xfce-look.sh
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "!! Run this as your normal user, WITHOUT sudo."; exit 1; }
KIT="$(cd "$(dirname "$0")" && pwd)"
DOT="$KIT/dotfiles"                 # files that differ on the Mini
SHARED="$(dirname "$KIT")/dotfiles" # files shared with the Dell (fastfetch, nvim, firefox)
WALLPAPER_URL=https://w.wallhaven.cc/full/72/wallhaven-72mrmv.jpg
WALLPAPER_SHA256=9045b1023969660f48c0f5ba4a9710427c7ecbd7fe75bec09acea3d00e61d600
NAVY_RGBA=(0.050980 0.062745 0.105882 0.700000)   # #0D101B at 70%, like the Dell's terminal
[[ -n ${DISPLAY:-} ]] && command -v xfconf-query >/dev/null || { echo "!! run this inside the Xfce session (no DISPLAY / xfconf-query)"; exit 1; }
xfconf-query -c xfwm4 -p /general/theme >/dev/null || { echo "!! xfconf is not reachable - run this inside the Xfce session"; exit 1; }

BAD=0
put() {  # src dest - keeps your old file as .bak when it differs
  mkdir -p "$(dirname "$2")"
  if [[ -f $2 ]] && ! cmp -s "$1" "$2"; then cp "$2" "$2.bak"; echo "  kept your old $2 as $2.bak"; fi
  install -m 644 "$1" "$2"; echo "  $2"
}
same() {  # xfconf prints 0.7 as 0.700000, so numbers are compared as numbers
  [[ $1 == "$2" ]] && return 0
  python3 -c 'import sys; sys.exit(float(sys.argv[1]) != float(sys.argv[2]))' "$1" "$2" 2>/dev/null
}
xset() {  # channel property type value - set (create if missing), then read back
  xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4"
  local got; got=$(xfconf-query -c "$1" -p "$2" 2>&1)
  if same "$got" "$4"; then printf '  ok  %s %s = %s\n' "$1" "$2" "$got"
  else printf '  !!  %s %s = %s (expected %s)\n' "$1" "$2" "$got" "$4"; BAD=1; fi
}
xset_array() {  # channel property type value... - array property, read back item by item
  local ch=$1 p=$2 t=$3; shift 3
  local args=() v; for v in "$@"; do args+=(-t "$t" -s "$v"); done
  xfconf-query -c "$ch" -p "$p" -n --force-array "${args[@]}"
  local got; mapfile -t got < <(xfconf-query -c "$ch" -p "$p" | sed -n '3,$p')
  local i ok=1; (( ${#got[@]} == $# )) || ok=0
  for (( i = 0; ok && i < $#; i++ )); do same "${got[i]}" "${@:i+1:1}" || ok=0; done
  if (( ok )); then printf '  ok  %s %s = [%s]\n' "$ch" "$p" "$*"
  else printf '  !!  %s %s = [%s] (expected [%s])\n' "$ch" "$p" "${got[*]}" "$*"; BAD=1; fi
}

echo "== GTK theme 'Gooey': Adwaita-dark from Debian's GTK3, recoloured (~/.local/share/themes/Gooey)"
THEME=~/.local/share/themes/Gooey
LIBGTK=$(ldconfig -p | awk '/libgtk-3\.so\.0 /{print $NF; exit}')
[[ -n $LIBGTK ]] || LIBGTK=/usr/lib/i386-linux-gnu/libgtk-3.so.0
command -v gresource >/dev/null || sudo apt-get install -y libglib2.0-bin
mkdir -p "$THEME/gtk-3.0"
TMPCSS=$(mktemp); trap 'rm -f "$TMPCSS"' EXIT
gresource extract "$LIBGTK" /org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css > "$TMPCSS"
python3 "$KIT/gooey-gtk3-theme.py" "$TMPCSS" "$THEME/gtk-3.0/gtk.css" || { echo "  !! recolouring failed"; BAD=1; }
cat > "$THEME/index.theme" <<'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Gooey
Comment=Adwaita-dark in the Gooey colours (debian13-setup/hp-mini-311)

[X-GNOME-Metatheme]
GtkTheme=Gooey
MetacityTheme=Gooey
IconTheme=Papirus-Dark
EOF

echo "== Window borders: xfwm4 'Default' images with the Gooey colours ($THEME/xfwm4)"
# The Default theme's images use named colours (active_color_2, ...); themerc sets them.
rm -rf "$THEME/xfwm4"; cp -r /usr/share/themes/Default/xfwm4 "$THEME/xfwm4"
grep -vE '^(active|inactive)_text(_shadow)?_color=' /usr/share/themes/Default/xfwm4/themerc > "$THEME/xfwm4/themerc"
cat >> "$THEME/xfwm4/themerc" <<'EOF'
# Gooey colours (m37-xfce-look.sh)
active_text_color=#EBEEF9
inactive_text_color=#858893
active_text_shadow_color=#0D101B
inactive_text_shadow_color=#0D101B
active_color_2=#1F222D
active_mid_2=#1F222D
active_hilight_2=#2A2E3C
active_shadow_2=#0D101B
inactive_color_2=#0D101B
inactive_mid_2=#0D101B
inactive_shadow_2=#06080F
EOF
echo "  $THEME/xfwm4"

echo "== Appearance: theme, icons, fonts"
if [[ ! -d /usr/share/icons/Papirus-Dark && ! -d ~/.local/share/icons/Papirus-Dark ]]; then sudo apt-get install -y papirus-icon-theme; fi
xset xsettings /Net/ThemeName string Gooey
xset xsettings /Net/IconThemeName string Papirus-Dark
xset xsettings /Gtk/CursorThemeName string Adwaita
xset xsettings /Gtk/FontName string "Cantarell 12"
xset xsettings /Gtk/MonospaceFontName string "JetBrainsMono Nerd Font 11"
xset xfwm4 /general/theme string Gooey
xset xfwm4 /general/title_font string "Cantarell Bold 11"

echo "== Workspaces + tiling (xfwm4's own: drag a window to an edge, or Super+arrows)"
xset xfwm4 /general/workspace_count int 4
xset xfwm4 /general/tile_on_move bool true
KS=xfce4-keyboard-shortcuts
# Xfce only reads /xfwm4/custom once it holds a full copy of the defaults (+ override=true),
# which is what its Keyboard settings dialog does on the first change; do the same.
if [[ $(xfconf-query -c $KS -p /xfwm4/custom/override 2>/dev/null) != true ]]; then
  n=0
  while read -r prop val; do
    [[ $prop == /xfwm4/default/* && -n $val ]] || continue
    xfconf-query -c $KS -p "/xfwm4/custom/${prop#/xfwm4/default/}" -n -t string -s "$val"; n=$((n + 1))
  done < <(xfconf-query -c $KS -l -v)
  xfconf-query -c $KS -p /xfwm4/custom/override -n -t bool -s true
  echo "  copied $n default window-manager shortcuts to /xfwm4/custom"
fi
for i in 1 2 3 4; do
  xset $KS "/xfwm4/custom/<Super>$i" string "workspace_${i}_key"
  xset $KS "/xfwm4/custom/<Super><Shift>$i" string "move_window_workspace_${i}_key"
done
xset $KS "/xfwm4/custom/<Super>Left" string tile_left_key
xset $KS "/xfwm4/custom/<Super>Right" string tile_right_key
xset $KS "/xfwm4/custom/<Super>Up" string maximize_window_key

echo "== Keyboard: English + Thai, switch with Super+Space (as on the Dell)"
xset keyboard-layout /Default/XkbDisable bool false
xset keyboard-layout /Default/XkbLayout string "us,th"
xset keyboard-layout /Default/XkbVariant string ","
xset keyboard-layout /Default/XkbOptions/Group string "grp:win_space_toggle"

echo "== Panels: 70% Gooey navy (picom blurs behind them), 24 h clock, battery %"
for panel in $(xfconf-query -c xfce4-panel -l | sed -nE 's|^/panels/(panel-[0-9]+)/position$|\1|p'); do
  xset xfce4-panel /panels/$panel/background-style uint 1
  xset_array xfce4-panel /panels/$panel/background-rgba double "${NAVY_RGBA[@]}"
done
plugin_of() { xfconf-query -c xfce4-panel -l -v | awk -v t="$1" '$1 ~ /^\/plugins\/plugin-[0-9]+$/ && $2 == t {print $1; exit}'; }
CLOCK=$(plugin_of clock)
if [[ -n $CLOCK ]]; then xset xfce4-panel "$CLOCK/digital-time-format" string "%H:%M"
else echo "  !! no clock in the panel (did the first login use 'Use default config'?)"; BAD=1; fi
xset xfce4-power-manager /xfce4-power-manager/show-panel-label int 1   # 1 = percentage
# keyboard-layout indicator (like GNOME's), in the top panel before the tray
if [[ -z $(plugin_of xkb) ]]; then
  ids=$(xfconf-query -c xfce4-panel -l | sed -nE 's|^/plugins/plugin-([0-9]+)$|\1|p' | sort -n | tail -1)
  new=$((ids + 1)); tray=$(plugin_of systray); tray=${tray##*-}
  mapfile -t cur < <(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids | sed -n '3,$p')
  out=(); for v in "${cur[@]}"; do [[ $v == "$tray" ]] && out+=("$new"); out+=("$v"); done
  [[ " ${out[*]} " == *" $new "* ]] || out+=("$new")
  xfconf-query -c xfce4-panel -p /plugins/plugin-$new -n -t string -s xkb
  xset_array xfce4-panel /panels/panel-1/plugin-ids int "${out[@]}"
fi
xfce4-panel -r || true

echo "== Wallpaper (wallhaven 72mrmv, zoomed to fill the 16:9 screen)"
WP=~/.local/share/backgrounds/wallhaven-72mrmv.jpg
if [[ ! -s $WP ]]; then
  mkdir -p "$(dirname "$WP")"
  curl -fsSL "$WALLPAPER_URL" -o "$WP.part"
  echo "$WALLPAPER_SHA256  $WP.part" | sha256sum -c --quiet - || { rm -f "$WP.part"; echo "  !! wallpaper checksum mismatch"; exit 1; }
  mv "$WP.part" "$WP"
fi
xset xfce4-desktop /backdrop/single-workspace-mode bool true
xset xfce4-desktop /backdrop/single-workspace-number int 0
mapfile -t mons < <( { xfconf-query -c xfce4-desktop -l 2>/dev/null | sed -nE 's|^/backdrop/screen0/monitor([^/]+)/.*|\1|p'
                       xrandr --listmonitors | awk 'NR > 1 {print $NF}'; } | sort -u)
for m in "${mons[@]}"; do
  xset xfce4-desktop "/backdrop/screen0/monitor$m/workspace0/last-image" string "$WP"
  xset xfce4-desktop "/backdrop/screen0/monitor$m/workspace0/image-style" int 5   # 5 = zoomed
done

echo "== Terminal: xfce4-terminal with the Gooey palette, 70% opaque, JetBrainsMono Nerd Font 12"
T=xfce4-terminal
PALETTE='#000009;#BB4F6C;#72CCAE;#C65E3D;#58B6CA;#6488C4;#8D84C6;#858893;#1F222D;#EE829F;#A5FFE1;#F99170;#8BE9FD;#97BBF7;#C0B7F9;#FFFFFF'
xset $T /color-use-theme bool false
xset $T /color-foreground string "#EBEEF9"
xset $T /color-background string "#0D101B"
xset $T /color-palette string "$PALETTE"
xset $T /background-mode string TERMINAL_BACKGROUND_TRANSPARENT
xset $T /background-darkness double 0.70
xset $T /font-use-system bool false
xset $T /font-name string "JetBrainsMono Nerd Font 12"
xset $T /misc-default-geometry string 110x32
xset $T /misc-bell bool false
xset $T /misc-menubar-default bool false

echo "== Blur: picom (xfwm4's compositor off while picom runs; svc blur off switches back)"
put "$DOT/picom/picom.conf" ~/.config/picom/picom.conf
[[ -f ~/.config/autostart/picom.desktop ]] || put "$DOT/autostart/picom.desktop" ~/.config/autostart/picom.desktop
if grep -q '^Hidden=true' ~/.config/autostart/picom.desktop; then
  echo "  blur is switched off (svc blur off) - leaving it off"
else
  xset xfwm4 /general/use_compositing bool false
  pkill -x picom || true; sleep 0.5
  setsid -f picom --experimental-backends >/dev/null 2>&1
  sleep 3
  if pgrep -x picom >/dev/null; then echo "  ok  picom is running"
  else
    echo "  !!  picom stopped right away - back to xfwm4's compositor. Try it by hand: picom --experimental-backends"
    xfconf-query -c xfwm4 -p /general/use_compositing -s true; BAD=1
  fi
fi

echo "== Screen lock: xscreensaver (Xfce's 'Lock Screen' and suspend use it)"
if [[ ! -f ~/.config/autostart/xscreensaver.desktop ]]; then
  mkdir -p ~/.config/autostart
  printf '[Desktop Entry]\nType=Application\nName=XScreenSaver\nExec=xscreensaver --no-splash\n' > ~/.config/autostart/xscreensaver.desktop
  echo "  ~/.config/autostart/xscreensaver.desktop"
fi
pgrep -x xscreensaver >/dev/null || setsid -f xscreensaver --no-splash >/dev/null 2>&1

echo "== fastfetch + cava configs, zshrc"
put "$SHARED/fastfetch/config.jsonc" ~/.config/fastfetch/config.jsonc
put "$DOT/cava/config" ~/.config/cava/config
put "$DOT/zshrc" ~/.zshrc

echo "== Neovim: Gooey colour scheme"
if [[ -d ~/.config/nvim/lua/plugins ]]; then put "$SHARED/nvim/lua/plugins/colorscheme.lua" ~/.config/nvim/lua/plugins/colorscheme.lua
else echo "  no ~/.config/nvim yet (m31-neovim.sh installs LazyVim with this file)"; fi

echo "== Firefox ESR: solid navy header, 70% navy page area (blurred by picom, if Firefox goes see-through on X11)"
shopt -s nullglob; profiles=(~/.mozilla/firefox/*.default-esr); shopt -u nullglob
if (( ${#profiles[@]} )); then
  for p in "${profiles[@]}"; do
    put "$SHARED/firefox/user.js" "$p/user.js"
    put "$SHARED/firefox/chrome/userChrome.css" "$p/chrome/userChrome.css"
    put "$SHARED/firefox/chrome/userContent.css" "$p/chrome/userContent.css"
  done
  echo "  Restart Firefox to load it."
else
  echo "  !! no Firefox ESR profile yet: start Firefox once, close it, then rerun this script"; BAD=1
fi

echo
(( ! BAD )) || { echo "!! Some settings above did not stick (lines with !!)."; exit 1; }
echo "Done. Open apps pick up the theme right away; restart Firefox and LibreOffice."
echo "Check the look against the Dell and send screenshots (xfce4-screenshooter) if a colour is off."
