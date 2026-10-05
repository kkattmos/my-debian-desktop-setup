#!/usr/bin/env bash
# Run on the fresh Debian 13 install, from the text console, as root - TWICE:
#   sudo bash 10-system.sh <your-username>    # run 1: Btrfs subvolumes + compression, then reboot
#   sudo bash 10-system.sh <your-username>    # run 2: everything else
# Needs the Wi-Fi the installer configured (home WPA-PSK network).
set -euo pipefail
U=${1:?usage: sudo bash 10-system.sh <username>}
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
id "$U" >/dev/null
KIT="$(cd "$(dirname "$0")" && pwd)"
export DEBIAN_FRONTEND=noninteractive
TMP=$(mktemp -d)

step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }

# ---------- Btrfs layout (the normal installer puts everything in one uncompressed @rootfs) ----------
# Run 1: turn on zstd compression, create @home @snapshots @var_log @var_cache @docker,
#        copy the current data into them, add them to fstab, then ask for a reboot.
# Run 2: check the new mounts, delete the old copies hidden under them, install everything else.
O=noatime,compress=zstd:1
[[ $(findmnt -no FSTYPE /) == btrfs ]] || { echo "/ is not Btrfs - choose btrfs for / in the installer"; exit 1; }
FSUUID=$(findmnt -no UUID /)
SUBVOLS=("@home:/home" "@snapshots:/.snapshots" "@var_log:/var/log" "@var_cache:/var/cache" "@docker:/var/lib/docker")
TOP=/mnt/btrfs-top

if ! grep -q 'subvol=@home' /etc/fstab; then
  step "Btrfs layout, run 1 of 2: compression + subvolumes"
  mount -o remount,compress=zstd:1 /
  echo "Compressing the files the installer wrote (about a minute)..."
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
  # The installer switches on any swap partition it finds - here Ubuntu's UNENCRYPTED p6. Turn it off.
  if grep -qE '^[^#]\S*\s+\S+\s+swap\s' /etc/fstab; then
    swapoff -a
    sed -i -E 's|^([^#]\S*\s+\S+\s+swap\s.*)$|# \1   # disabled: unencrypted Ubuntu swap, zram is used instead|' /etc/fstab
    rm -f /etc/initramfs-tools/conf.d/resume
    update-initramfs -u -k all
    echo "Ubuntu's swap partition is no longer used by Debian."
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

step "APT: no recommends, deb822 sources with contrib + non-free-firmware"
cat > /etc/apt/apt.conf.d/99-minimal <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
cat > /etc/apt/sources.list.d/debian.sources <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
[[ -f /etc/apt/sources.list ]] && mv /etc/apt/sources.list /etc/apt/sources.list.installer-bak
install -m 0755 -d /etc/apt/keyrings
apt-get update
apt-get -y full-upgrade
apt-get -y install curl ca-certificates

step "Third-party repos: Docker CE, ONLYOFFICE, Tailscale"
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE -o /etc/apt/keyrings/onlyoffice.asc
cat > /etc/apt/sources.list.d/onlyoffice.sources <<'EOF'
Types: deb
URIs: https://download.onlyoffice.com/repo/debian
Suites: squeeze
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/onlyoffice.asc
EOF
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
apt-get update

step "Packages"
# Wireshark: let members of group 'wireshark' capture without root
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

PKGS=(
  # base hardware / boot / storage
  firmware-realtek firmware-sof-signed firmware-intel-graphics intel-microcode
  cryptsetup-initramfs keyutils btrfs-progs snapper btrfsmaintenance os-prober
  systemd-zram-generator network-manager wpasupplicant bash-completion sudo locales dconf-cli
  # minimal GNOME 48 (no gnome-core, no GDM)
  gnome-session gnome-shell gnome-control-center gnome-keyring libpam-gnome-keyring
  nautilus ptyxis xdg-desktop-portal-gnome xdg-user-dirs-gtk xwayland
  pipewire-audio wireplumber gstreamer1.0-pipewire gstreamer1.0-plugins-good
  gnome-shell-extension-manager gnome-shell-extension-prefs gnome-tweaks
  loupe papers file-roller gnome-system-monitor gnome-disk-utility
  power-profiles-daemon bluez gvfs-backends gvfs-fuse adwaita-icon-theme
  fonts-cantarell fonts-noto-core fonts-thai-tlwg fonts-noto-color-emoji ibus
  # apps
  firefox-esr wireshark onlyoffice-desktopeditors
  # desktop look (37-desktop-look.sh) + everyday tools that were added by hand after the first install
  papirus-icon-theme btop htop vlc pavucontrol gh xclip
  # Tailscale (your Seafile server is reached over the tailnet)
  tailscale
  # shell + CLI
  zsh zsh-autosuggestions zsh-syntax-highlighting fzf ripgrep fd-find lazygit bat eza zoxide fastfetch cava kitty imagemagick
  # build + dev
  build-essential git wget unzip xz-utils python3-venv python3-pip python3-dev nodejs npm
  # Docker (disabled at boot, toggled with `svc docker on|off`)
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  # PhotoPrism runtime deps + SeaDrive/PacketTracer FUSE deps
  ffmpeg libimage-exiftool-perl libheif-examples libheif-plugin-libde265 sqlite3 libvips42t64
  fuse3 libfuse2t64 libxcb-xinerama0 libxcb-cursor0 libxkbcommon-x11-0 libnss3 libpcre2-dev xdg-utils
  # Ly build deps (libpam0g-dev removed again at the end)
  libpam0g-dev brightnessctl
)
apt-get -y install "${PKGS[@]}"

step "Groups: sudo, wireshark, docker, dialout/plugdev (STM32 serial + ST-LINK)"
for g in sudo wireshark docker dialout plugdev; do getent group $g >/dev/null && usermod -aG $g "$U"; done

step "Docker: installed but OFF at boot"
systemctl disable --now docker.service docker.socket containerd.service || true

step "zram swap (no disk swap)"
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
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
chattr +C /var/lib/docker 2>/dev/null || true   # no copy-on-write for container layers

step "Never auto-enable Ubuntu's unencrypted swap (p6 itself stays untouched for Ubuntu)"
# systemd-gpt-auto-generator switches on every "Linux swap" GPT partition, fstab or not
mkdir -p /etc/systemd/system-generators
ln -sfn /dev/null /etc/systemd/system-generators/systemd-gpt-auto-generator

step "GRUB: show Ubuntu in the boot menu"
grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub || echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
update-grub

step "STM32CubeIDE: libncurses5 + libtinfo5 from Debian 12 (removed in 13)"
cd "$TMP"
curl -fLO http://deb.debian.org/debian/pool/main/n/ncurses/libtinfo5_6.4-4_amd64.deb
curl -fLO http://deb.debian.org/debian/pool/main/n/ncurses/libncurses5_6.4-4_amd64.deb
sha256sum -c - <<'EOF'
dd347f794e651039e7b4c391f86c674fed7f415b3dca6b0937beb0d470f09c1a  libtinfo5_6.4-4_amd64.deb
02f4f7f52c4ce2fc4021793a931bfd85f7870554b8e4d56576d73a4ed0bdb390  libncurses5_6.4-4_amd64.deb
EOF
apt-get -y install ./libtinfo5_6.4-4_amd64.deb ./libncurses5_6.4-4_amd64.deb

step "PhotoPrism (native .deb, off at boot)"
curl -fL https://dl.photoprism.app/pkg/linux/deb/amd64.deb -o photoprism.deb
apt-get -y install ./photoprism.deb

step "Ly 1.4.1 login manager (built with Zig 0.16.0, Wayland-only build)"
ZIG=zig-x86_64-linux-0.16.0
curl -fL "https://ziglang.org/download/0.16.0/$ZIG.tar.xz" | tar -xJ
git clone --depth 1 --branch v1.4.1 https://codeberg.org/fairyglade/ly.git
( cd ly && "../$ZIG/zig" build installexe -Dinit_system=systemd -Denable_x11_support=false -Doptimize=ReleaseSafe )
# Ly's PAM file registers the DESKTOP session as a login-screen ("greeter") session; make it a user session
sed -i -E 's/(pam_systemd\.so[[:space:]]+)class=greeter/\1class=user/' /etc/pam.d/ly
grep -n pam_systemd /etc/pam.d/ly
systemctl disable getty@tty2.service
systemctl enable ly@tty2.service
systemctl set-default graphical.target

step "Move Wi-Fi from ifupdown (installer) to NetworkManager"
if grep -qE '^\s*iface\s+wl' /etc/network/interfaces 2>/dev/null; then
  IF=$(awk '/^\s*iface\s+wl/{print $2; exit}' /etc/network/interfaces)
  SSID=$(awk '/wpa-ssid/{sub(/^[ \t]*wpa-ssid[ \t]+/,""); print; exit}' /etc/network/interfaces)
  PSK=$(awk '/wpa-psk/{print $2; exit}' /etc/network/interfaces)
  nmcli connection add type wifi con-name "$SSID" ifname '*' ssid "$SSID" \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PSK" connection.autoconnect yes || true
  cp /etc/network/interfaces /etc/network/interfaces.installer-bak
  sed -i -E "/^(allow-hotplug|auto)\s+$IF/,\$ s/^/# /" /etc/network/interfaces
  echo "Wi-Fi '$SSID' is now a NetworkManager profile (takes over after reboot)."
fi

step "Clean up"
apt-get -y purge libpam0g-dev
apt-get -y autoremove --purge
apt-get clean
rm -rf "$TMP"
[[ -e "/home/$U/debian13-setup" ]] || { cp -r "$KIT" "/home/$U/debian13-setup" && chown -R "$U:$U" "/home/$U/debian13-setup"; }

echo
echo "Done. Reboot now:  systemctl reboot"
echo "Ly appears on tty2. Pick 'GNOME' as session, log in, then run as your user:"
echo "  bash ~/debian13-setup/20-wifi.sh && bash ~/debian13-setup/30-user.sh"
