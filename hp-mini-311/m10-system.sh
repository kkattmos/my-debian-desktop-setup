#!/usr/bin/env bash
# HP Mini 311 (Atom N280 = 32-bit only): Debian 12 "bookworm" i386 + Xfce. Run on the fresh install,
# from the text console, as root - TWICE:
#   sudo bash m10-system.sh <your-username>    # run 1: Btrfs subvolumes + compression, then reboot
#   sudo bash m10-system.sh <your-username>    # run 2: everything else
# Needs a network: the Ethernet cable, or the Wi-Fi the installer set up (Ralink USB dongle).
# The built-in Broadcom BCM4312 only works after run 2 has downloaded its firmware.
set -euo pipefail
U=${1:?usage: sudo bash m10-system.sh <username>}
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
id "$U" >/dev/null
[[ $(dpkg --print-architecture) == i386 ]] || { echo "this kit is for Debian 12 i386 (the HP Mini 311)"; exit 1; }
. /etc/os-release
[[ ${VERSION_CODENAME:-} == bookworm ]] || { echo "this kit is for Debian 12 bookworm, found ${PRETTY_NAME:-?}"; exit 1; }
KIT="$(cd "$(dirname "$0")" && pwd)"
export DEBIAN_FRONTEND=noninteractive
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }

# ---------- Btrfs layout (the installer puts everything in one uncompressed @rootfs) ----------
# Run 1: turn on zstd compression, create @home @snapshots @var_log @var_cache,
#        copy the current data into them, add them to fstab, then ask for a reboot.
# Run 2: check the new mounts, delete the old copies hidden under them, install everything else.
O=noatime,compress=zstd:1
[[ $(findmnt -no FSTYPE /) == btrfs ]] || { echo "/ is not Btrfs - choose btrfs for / in the installer"; exit 1; }
FSUUID=$(findmnt -no UUID /)
SUBVOLS=("@home:/home" "@snapshots:/.snapshots" "@var_log:/var/log" "@var_cache:/var/cache")
TOP=/mnt/btrfs-top

if ! grep -q 'subvol=@home' /etc/fstab; then
  step "Btrfs layout, run 1 of 2: compression + subvolumes"
  grep -qE '^\S+\s+/\s+btrfs\s+\S*subvol=@rootfs' /etc/fstab || {
    echo "!! the / line in /etc/fstab has no subvol=@rootfs - this script expects the installer's layout:"
    grep -E '^\S+\s+/\s' /etc/fstab; exit 1; }
  mount -o remount,compress=zstd:1 /
  echo "Compressing the files the installer wrote (a few minutes on this disk)..."
  btrfs filesystem defragment -r -czstd / || true
  mkdir -p "$TOP"; mountpoint -q "$TOP" || mount -o subvolid=5 UUID="$FSUUID" "$TOP"
  for sv in "${SUBVOLS[@]}"; do
    name=${sv%%:*} dir=${sv#*:}
    [[ -d $TOP/$name ]] || btrfs subvolume create "$TOP/$name"
    # reflink=auto: journald's no-copy-on-write files can't be reflinked, those get a normal copy
    if [[ -d $dir && $name != @snapshots ]]; then cp -a --reflink=auto "$dir/." "$TOP/$name/"; fi
    mkdir -p "$dir"
  done
  umount "$TOP"
  [[ -f /etc/fstab.installer-bak ]] || cp /etc/fstab /etc/fstab.installer-bak
  # No disk swap: zram is used instead (a swap partition would also have to be encrypted)
  if grep -qE '^[^#]\S*\s+\S+\s+swap\s' /etc/fstab; then
    swapoff -a
    sed -i -E 's|^([^#]\S*\s+\S+\s+swap\s.*)$|# \1   # disabled: zram is used instead|' /etc/fstab
    rm -f /etc/initramfs-tools/conf.d/resume
    update-initramfs -u -k all
    echo "The installer's swap is no longer used."
  fi
  # root line: mount by filesystem UUID, add noatime + compression
  sed -i -E "s|^\S+(\s+/\s+btrfs\s+)\S*subvol=@rootfs\S*|UUID=$FSUUID\1$O,subvol=@rootfs|" /etc/fstab
  grep -qE "^UUID=$FSUUID\s+/\s+btrfs\s+$O,subvol=@rootfs" /etc/fstab || {
    cp /etc/fstab.installer-bak /etc/fstab; echo "could not rewrite the / line in /etc/fstab (restored)"; exit 1; }
  for sv in "${SUBVOLS[@]}"; do
    printf 'UUID=%s %-16s btrfs %s,subvol=%s 0 0\n' "$FSUUID" "${sv#*:}" "$O" "${sv%%:*}" >> /etc/fstab
  done
  echo "--- /etc/fstab"; cat /etc/fstab
  findmnt --verify --tab-file /etc/fstab || {
    echo "!! /etc/fstab has problems (above) - fix before rebooting; original: /etc/fstab.installer-bak"; exit 1; }
  echo
  echo "Run 1 done. Reboot, log in again, and run the same command once more:"
  echo "  systemctl reboot"
  echo "  sudo bash $0 $U"
  exit 0
fi
for sv in "${SUBVOLS[@]}"; do
  findmnt -no FSROOT "${sv#*:}" | grep -qx "/${sv%%:*}" || { echo "${sv#*:} is not mounted from ${sv%%:*} - reboot first"; exit 1; }
done
step "Btrfs layout, run 2 of 2: remove the old copies hidden under the new mounts"
mkdir -p "$TOP"; mountpoint -q "$TOP" || mount -o subvolid=5 UUID="$FSUUID" "$TOP"
for d in home var/log var/cache; do find "$TOP/@rootfs/$d" -mindepth 1 -delete 2>/dev/null || true; done
umount "$TOP"

step "Clock: the Mini's CMOS clock was months off - sync it from the network (apt needs a correct date)"
apt-get -y install systemd-timesyncd || true   # may fail if the date is so wrong that apt refuses; set it in the BIOS then
timedatectl set-ntp true || true
for _ in $(seq 30); do [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null) == yes ]] && break; sleep 1; done
if [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null) == yes ]]; then
  hwclock --systohc && echo "  clock synced and written to the BIOS: $(date)"
else
  echo "  !! not synced yet, the date is now: $(date) - if that is wrong, fix it in the BIOS (F10) and rerun"
fi

step "APT: no recommends, deb822 sources with contrib + non-free-firmware"
cat > /etc/apt/apt.conf.d/99-minimal <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
cat > /etc/apt/sources.list.d/debian.sources <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: bookworm bookworm-updates
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: bookworm-security
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
[[ -f /etc/apt/sources.list ]] && mv /etc/apt/sources.list /etc/apt/sources.list.installer-bak
apt-get update
apt-get -y full-upgrade
apt-get -y install curl ca-certificates

step "Third-party repo: Tailscale (has i386; Docker, ONLYOFFICE and PhotoPrism have no 32-bit builds)"
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
apt-get update

step "Packages (every name checked against the Debian 12 i386 index)"
# Wireshark: let members of group 'wireshark' capture without root
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

PKGS=(
  # base hardware / boot / storage. Wi-Fi: firmware-misc-nonfree has rt2870.bin for the Ralink USB
  # dongle; the BCM4312's b43 firmware is downloaded by firmware-b43-installer below.
  firmware-misc-nonfree intel-microcode pciutils usbutils rfkill
  cryptsetup-initramfs keyutils btrfs-progs snapper btrfsmaintenance
  systemd-zram-generator systemd-timesyncd network-manager network-manager-gnome wpasupplicant
  bash-completion sudo locales dconf-cli dbus-user-session libpam-systemd
  # X11 (Xfce 4.18 is X11-only) + ION graphics through the open nouveau driver
  xserver-xorg xserver-xorg-legacy xauth x11-xserver-utils x11-utils libgl1-mesa-dri mesa-utils
  # Xfce, piece by piece (no recommends -> the useful recommends are listed by hand)
  xfce4-session xfwm4 xfdesktop4 xfce4-panel xfce4-settings xfconf xfce4-appfinder
  xfce4-terminal thunar thunar-volman tumbler gvfs gvfs-backends gvfs-fuse udisks2 xdg-user-dirs xdg-utils
  xfce4-power-manager xfce4-power-manager-plugins xfce4-pulseaudio-plugin xfce4-notifyd
  xfce4-xkb-plugin xfce4-screenshooter xfce4-taskmanager upower librsvg2-common
  policykit-1-gnome gnome-keyring libpam-gnome-keyring xscreensaver
  mousepad ristretto atril engrampa
  pipewire-audio pavucontrol bluez blueman
  # look (m37-xfce-look.sh): blur compositor, dark GTK theme, icons, fonts
  picom gnome-themes-extra adwaita-icon-theme papirus-icon-theme
  fonts-cantarell fonts-dejavu-core fonts-noto-core fonts-thai-tlwg fonts-noto-color-emoji
  # apps (LibreOffice instead of ONLYOFFICE, which has no 32-bit build)
  firefox-esr wireshark libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-gtk3
  btop htop vlc gh xclip
  # Tailscale (your Seafile server is reached over the tailnet) + Seafile sync client (no SeaDrive for i386)
  tailscale seafile-cli
  # shell + CLI (exa instead of eza; lazygit + fastfetch come from upstream in m30)
  zsh zsh-autosuggestions zsh-syntax-highlighting fzf ripgrep fd-find bat exa zoxide cava
  # build + dev (cmake/ninja/gettext: Neovim is compiled from source on this machine by m31)
  build-essential git wget unzip xz-utils cmake ninja-build gettext
  python3-venv python3-pip python3-dev nodejs npm
  # Neovim notebooks: the compiled Python modules come from Debian (no i686 wheels on PyPI)
  python3-pynvim python3-jupyter-client python3-ipykernel python3-nbformat
  # Ly build deps (with X11 support this time)
  libpam0g-dev libxcb-xkb-dev brightnessctl
)
apt-get -y install "${PKGS[@]}"

step "Built-in Wi-Fi (Broadcom BCM4312, b43): download + extract its firmware (needs internet)"
if apt-get -y install firmware-b43-installer && [[ -f /lib/firmware/b43/ucode15.fw ]]; then
  echo "  b43 firmware installed: /lib/firmware/b43/ucode15.fw"
  if grep -q '^b43 ' /proc/modules; then modprobe -r b43 && modprobe b43 && echo "  b43 reloaded"; fi
else
  echo "  !! b43 firmware not installed (no internet?). Later: sudo apt install --reinstall firmware-b43-installer"
fi

step "Groups: sudo, wireshark, dialout/plugdev"
for g in sudo wireshark dialout plugdev; do getent group $g >/dev/null && usermod -aG $g "$U"; done

step "zram swap (no disk swap): as big as the RAM, zstd-compressed"
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF

step "Snapper: snapshots of / before/after every apt run (no timeline, keep 10)"
if ! snapper list-configs 2>/dev/null | grep -q '^root'; then
  umount /.snapshots && rmdir /.snapshots
  snapper --no-dbus -c root create-config /
  btrfs subvolume delete /.snapshots
  mkdir /.snapshots && mount /.snapshots && chmod 750 /.snapshots
  snapper --no-dbus -c root set-config TIMELINE_CREATE=no NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 ALLOW_USERS="$U"
fi

step "Ly 1.4.1 login manager (built with Zig 0.16.0 for 32-bit x86, X11 support on for Xfce)"
ZIG=zig-x86-linux-0.16.0
cd "$TMP"
curl -fLO "https://ziglang.org/download/0.16.0/$ZIG.tar.xz"
echo "4e34e279a9f856358de420490b531974c3d37f8f3707eef9f0342e92c14c301f  $ZIG.tar.xz" | sha256sum -c -
tar -xJf "$ZIG.tar.xz"
git clone --depth 1 --branch v1.4.1 https://codeberg.org/fairyglade/ly.git
( cd ly && "../$ZIG/zig" build installexe -Dinit_system=systemd -Doptimize=ReleaseSafe )
# Ly's PAM file registers the DESKTOP session as a login-screen ("greeter") session; make it a user session
sed -i -E 's/(pam_systemd\.so[[:space:]]+)class=greeter/\1class=user/' /etc/pam.d/ly
grep -n pam_systemd /etc/pam.d/ly
systemctl disable getty@tty2.service
systemctl enable ly@tty2.service
systemctl set-default graphical.target

step "Network: hand Ethernet + Wi-Fi from ifupdown (installer) to NetworkManager"
if grep -qE '^\s*iface\s+[^l ]' /etc/network/interfaces 2>/dev/null; then
  cp -n /etc/network/interfaces /etc/network/interfaces.installer-bak
  # the installer's Wi-Fi (USB dongle, wlx...) becomes a NetworkManager profile
  if grep -qE '^\s*iface\s+wl' /etc/network/interfaces; then
    SSID=$(awk '/wpa-ssid/{sub(/^[ \t]*wpa-ssid[ \t]+/,""); print; exit}' /etc/network/interfaces)
    PSK=$(awk '/wpa-psk/{print $2; exit}' /etc/network/interfaces)
    if [[ -n $SSID ]] && ! nmcli -t -f NAME connection show | grep -xF "$SSID" >/dev/null; then
      nmcli connection add type wifi con-name "$SSID" ifname '*' ssid "$SSID" \
        wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PSK" connection.autoconnect yes
    fi
    echo "  Wi-Fi '$SSID' is now a NetworkManager profile (any Wi-Fi card can use it)."
  fi
  # only loopback stays in ifupdown, so NetworkManager manages Ethernet (DHCP) + Wi-Fi after the reboot
  cat > /etc/network/interfaces <<'EOF'
# Networks are managed by NetworkManager (nmcli / the tray icon).
# The installer's version is /etc/network/interfaces.installer-bak
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback
EOF
  echo "  /etc/network/interfaces now only has loopback (takes effect after the reboot)."
fi

step "Clean up"
apt-get -y purge libpam0g-dev
apt-get -y autoremove --purge
apt-get clean
# the whole kit (Dell scripts + this folder share dotfiles and 35-thai-font.sh)
ROOT=$(dirname "$KIT")
[[ -e "/home/$U/debian13-setup" ]] || { cp -r "$ROOT" "/home/$U/debian13-setup" && chown -R "$U:$U" "/home/$U/debian13-setup"; }

echo
echo "Done. Reboot now:  systemctl reboot"
echo "Ly appears on tty2. Pick 'Xfce Session', log in, answer 'Use default config' for the panel, then"
echo "open a terminal and run as your user:"
echo "  bash ~/debian13-setup/20-wifi.sh && bash ~/debian13-setup/hp-mini-311/m30-user.sh"
