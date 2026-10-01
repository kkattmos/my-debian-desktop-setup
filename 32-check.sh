#!/usr/bin/env bash
# Read-only status report - changes nothing. Run it in a GNOME terminal after logging in:
#   bash 32-check.sh
row() { printf '%-22s %s\n' "$1" "$2"; }
uid=$(id -u)
(( uid != 0 )) || { echo "Run as your normal user, not with sudo."; exit 1; }

echo "--- session"
row "variables" "RUNTIME=${XDG_RUNTIME_DIR:-<unset>} BUS=${DBUS_SESSION_BUS_ADDRESS:-<unset>}"
row "" "TYPE=${XDG_SESSION_TYPE:-<unset>} DESKTOP=${XDG_CURRENT_DESKTOP:-<unset>} ID=${XDG_SESSION_ID:-<unset>}"
for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$USER" '$3==u{print $1}'); do
  row "logind session $s" "$(loginctl show-session "$s" -p Class -p Type -p Service -p Active 2>/dev/null | paste -sd' ')"
done
row "linger" "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)"
row "user bus socket" "$([[ -S /run/user/$uid/bus ]] && echo yes || echo NO)"
row "dbus-user-session" "$(dpkg-query -W -f='${Status}' dbus-user-session 2>/dev/null || echo 'not installed')"
row "ly PAM pam_systemd" "$(grep -h 'pam_systemd' /etc/pam.d/ly 2>/dev/null | xargs)"

echo "--- shell"
row "TERM (this terminal)" "$TERM  (want xterm-256color here; linux = leaked from the text console)"
row "login shell" "$(getent passwd "$USER" | cut -d: -f7)"
row "powerlevel10k" "$(git -C ~/.local/share/powerlevel10k log -1 --format='%h %cs' 2>/dev/null || echo missing)"
row "~/.p10k.zsh" "$([[ -f ~/.p10k.zsh ]] && echo yes || echo 'no -> wizard runs at next zsh start')"
pu=$(dconf read /org/gnome/Ptyxis/default-profile-uuid 2>/dev/null | tr -d "'")
row "Ptyxis profile" "$([[ -n $pu ]] && echo "palette $(dconf read /org/gnome/Ptyxis/Profiles/$pu/palette) opacity $(dconf read /org/gnome/Ptyxis/Profiles/$pu/opacity)" || echo 'none (36-terminal-look.sh)')"
row "nvim" "$(~/.local/bin/nvim --version 2>/dev/null | head -1 || echo missing)"

echo "--- GNOME"
row "dconf profile" "$(paste -sd' ' /etc/dconf/profile/user 2>/dev/null || echo none)"
row "system defaults" "$(ls /etc/dconf/db/local.d/ 2>/dev/null | paste -sd' ')"
for k in "org.gnome.shell enabled-extensions" "org.gnome.desktop.interface color-scheme" \
         "org.gnome.desktop.input-sources sources" "org.gnome.desktop.interface monospace-font-name" \
         "org.gnome.mutter dynamic-workspaces"; do
  row "${k#* }" "$(gsettings get $k 2>&1)"
done
row "extension files" "$(ls ~/.local/share/gnome-shell/extensions/ 2>/dev/null | paste -sd' ')"
for e in tilingshell@ferrarodomenico.com blur-my-shell@aunetx switchWorkSpace@sun.wxg@gmail.com \
         gooey-dock@kkattmos workspace-label@kkattmos; do
  row "  ${e%%@*}" "$(gnome-extensions info "$e" 2>&1 | grep -E 'State|Enabled' | xargs)"
done
row "Nerd Font" "$(fc-list | grep -c 'JetBrainsMono Nerd Font') file(s)"
row "Thai fallback" "$(fc-match -s -f '%{family[0]}\t%{charset}\n' sans-serif | awk -F'\t' '$2 ~ /(^| )e0[01]-e3a/ {print $1; exit}')  (want Sarabun; 35-thai-font.sh)"

echo "--- look (37-desktop-look.sh)"
row "blurred apps" "$(dconf read /org/gnome/shell/extensions/blur-my-shell/applications/whitelist 2>/dev/null)"
row "icon theme" "$(gsettings get org.gnome.desktop.interface icon-theme 2>&1)"
row "wallpaper" "$(gsettings get org.gnome.desktop.background picture-uri-dark 2>&1)"
row "GTK4 gtk.css" "$([[ -f ~/.config/gtk-4.0/gtk.css ]] && echo yes || echo no)"
row "nvim colorscheme" "$([[ -f ~/.config/nvim/lua/plugins/colorscheme.lua ]] && echo gooey || echo 'default tokyonight')"
row "Firefox userChrome" "$(ls ~/.mozilla/firefox/*.default-esr/chrome/userChrome.css 2>/dev/null | wc -l) profile(s)"

echo "--- boot"
row "GRUB theme" "$(sed -n 's/^GRUB_THEME=//p' /etc/default/grub | tr -d '"')  files: $([[ -f /boot/grub/themes/space-isolation/theme.txt ]] && echo ok || echo 'missing (sudo bash 38-grub-theme.sh)')"
row "GRUB os-prober" "$(grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub && echo on || echo 'off -> no Ubuntu entry in the GRUB menu')"

echo "--- services"
row "seadrive.service" "$(systemctl --user is-active seadrive 2>&1)"
row "~/SeaDrive mounted" "$(findmnt -n -o FSTYPE ~/SeaDrive 2>/dev/null || echo no)"
row "tailscale" "$(tailscale status --peers=false 2>&1 | head -1)"
sw=$(awk 'NR>1{print $1}' /proc/swaps | paste -sd' ')
[[ " $sw " == *" /dev/nvme"* ]] && sw="$sw   !! disk swap in use: sudo bash 34-no-ubuntu-swap.sh"
row "swap" "$sw"
