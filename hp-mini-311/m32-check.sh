#!/usr/bin/env bash
# HP Mini 311: read-only status report - changes nothing. Run it in a terminal inside Xfce:
#   bash m32-check.sh
# Prints the report and saves it as ~/m32-check-<date>.txt; when the Ventoy stick is mounted, a copy
# goes to its debian-install/ folder too (bring that file back to the Dell).
row() { printf '%-22s %s\n' "$1" "$2"; }
uid=$(id -u)
(( uid != 0 )) || { echo "Run as your normal user, not with sudo."; exit 1; }
xq() { xfconf-query -c "$1" -p "$2" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'; }
OUT=~/m32-check-$(hostname)-$(date +%Y%m%d-%H%M).txt

{
echo "m32-check  $(date -Is)  $(hostname)"

echo "--- system"
row "debian / arch" "$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"') / $(dpkg --print-architecture)"
row "kernel" "$(uname -r)"
row "clock" "$(date '+%F %T')  NTP synced: $(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
row "clock-from-http" "$(systemctl is-enabled clock-from-http 2>&1), last boot: $(systemctl show clock-from-http -p Result --value 2>/dev/null)"
e2=$(grep -h broken_system_clock /etc/e2fsck.conf 2>/dev/null | xargs)
row "e2fsck.conf" "${e2:-missing (m10-system.sh)}"
row "swap" "$(awk 'NR>1{print $1}' /proc/swaps | paste -sd' ')  (want only /dev/zram0)"
for m in / /home /.snapshots /var/log /var/cache; do row "btrfs $m" "$(findmnt -no FSROOT,OPTIONS "$m" 2>/dev/null | cut -c1-70)"; done

echo "--- network"
row "BCM4312 driver" "$(lspci -k -d 14e4:4315 2>/dev/null | sed -n 's/.*Kernel driver in use: //p')"
row "b43 firmware" "$([[ -f /lib/firmware/b43/ucode15.fw ]] && echo installed || echo 'MISSING (sudo apt install --reinstall firmware-b43-installer)')"
row "rfkill" "$(rfkill -n -o TYPE,SOFT,HARD 2>/dev/null | paste -sd',' )"
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null | while IFS=: read -r d t s c; do row "  $d ($t)" "$s ${c:+-> $c}"; done
row "ifupdown leftovers" "$(grep -cE '^\s*iface\s+[^l ]' /etc/network/interfaces 2>/dev/null) (want 0)"

echo "--- session"
row "type / desktop" "${XDG_SESSION_TYPE:-<unset>} / ${XDG_CURRENT_DESKTOP:-<unset>}"
row "ly PAM pam_systemd" "$(grep -h 'pam_systemd' /etc/pam.d/ly 2>/dev/null | xargs)"
row "linger" "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)"
row "user bus socket" "$([[ -S /run/user/$uid/bus ]] && echo yes || echo NO)"
row "OpenGL renderer" "$(glxinfo -B 2>/dev/null | sed -n 's/^OpenGL renderer string: //p')"

echo "--- shell + tools"
row "TERM (this terminal)" "$TERM  (want xterm-256color)"
row "login shell" "$(getent passwd "$USER" | cut -d: -f7)"
row "powerlevel10k" "$(git -C ~/.local/share/powerlevel10k log -1 --format='%h %cs' 2>/dev/null || echo missing)"
row "~/.p10k.zsh" "$([[ -f ~/.p10k.zsh ]] && echo yes || echo 'no -> wizard runs at next zsh start')"
row "nvim" "$(~/.local/bin/nvim --version 2>/dev/null | sed -n 1p || echo 'missing (m31-neovim.sh)')"
row "tree-sitter" "$(~/.local/bin/tree-sitter --version 2>/dev/null || echo 'missing (m31-neovim.sh)')"
row "fastfetch / lazygit" "$(~/.local/bin/fastfetch --version 2>/dev/null | sed -n 1p) / $(~/.local/bin/lazygit --version 2>/dev/null | sed -n 's/.*version=\([^,]*\),.*/\1/p')"
row "Nerd Font" "$(fc-list | grep -c 'JetBrainsMono Nerd Font') file(s)"
row "Thai fallback" "$(fc-match -s -f '%{family[0]}\t%{charset}\n' sans-serif | awk -F'\t' '$2 ~ /(^| )e0[01]-e3a/ {print $1; exit}')  (want Sarabun)"

echo "--- look (m37-xfce-look.sh)"
row "GTK / icons / font" "$(xq xsettings /Net/ThemeName) / $(xq xsettings /Net/IconThemeName) / $(xq xsettings /Gtk/FontName)"
row "Gooey GTK3 theme" "$([[ -s ~/.local/share/themes/Gooey/gtk-3.0/gtk.css ]] && echo yes || echo missing)"
row "window borders" "$(xq xfwm4 /general/theme)"
row "keyboard layouts" "$(xq keyboard-layout /Default/XkbLayout)  switch: $(xq keyboard-layout /Default/XkbOptions/Group)"
row "terminal" "bg $(xq xfce4-terminal /color-background), $(xq xfce4-terminal /background-mode) $(xq xfce4-terminal /background-darkness), $(xq xfce4-terminal /font-name)"
row "blur (picom)" "$(pgrep -x picom >/dev/null && echo running || echo 'not running')  xfwm4 compositor: $(xq xfwm4 /general/use_compositing)"
row "screen lock" "xscreensaver $(pgrep -x xscreensaver >/dev/null && echo running || echo 'NOT running')"
row "Firefox userChrome" "$(ls ~/.mozilla/firefox/*.default-esr/chrome/userChrome.css 2>/dev/null | wc -l) profile(s)"
# picom's blur rule matches these class names; compare with dotfiles/picom/picom.conf
if command -v xprop >/dev/null && [[ -n ${DISPLAY:-} ]]; then
  for w in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+'); do
    row "  window class" "$(xprop -id "$w" WM_CLASS 2>/dev/null | sed 's/.*= //')"
  done | sort -u
fi

echo "--- services"
row "tailscale" "$(tailscale status --peers=false 2>&1 | sed -n 1p)"
row "seafile.service" "$(systemctl --user is-active seafile 2>&1)"
seaf-cli status 2>/dev/null | sed -n '2,$p' | while read -r line; do row "  seafile" "$line"; done
} 2>&1 | tee "$OUT"

echo
echo "Saved: $OUT"
for d in /media/"$USER"/Ventoy/debian-install /run/media/"$USER"/Ventoy/debian-install; do
  if [[ -d $d && -w $d ]]; then cp "$OUT" "$d/" && sync && echo "Copied to the stick: $d/$(basename "$OUT")"; fi
done
