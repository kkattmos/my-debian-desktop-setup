#!/usr/bin/env bash
# Stop Debian from using Ubuntu's UNENCRYPTED swap partition (p6).
# It is not in /etc/fstab: systemd-gpt-auto-generator switches on any partition whose GPT type is
# "Linux swap". Masking that one generator stops it (everything Debian mounts is listed in
# /etc/fstab, so nothing else depends on it). GRUB, the kernel command line and the initramfs are
# not touched. p6 itself is NOT changed: Ubuntu still uses it as its swap.
# Undo: sudo rm /etc/systemd/system-generators/systemd-gpt-auto-generator
#   sudo bash 34-no-ubuntu-swap.sh      (safe to run again)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
MASK=/etc/systemd/system-generators/systemd-gpt-auto-generator

echo "== Mask systemd-gpt-auto-generator"
mkdir -p /etc/systemd/system-generators
ln -sfn /dev/null "$MASK"
ls -l "$MASK"

echo "== Switch off disk swap now (it holds nothing: Debian's zram has priority)"
awk 'NR>1 && $1 !~ /zram/ {print $1}' /proc/swaps | while read -r dev; do swapoff "$dev" && echo "swapoff $dev"; done
systemctl daemon-reload
left=$(find /run/systemd/generator.late -name '*.swap' 2>/dev/null | wc -l)
(( left == 0 )) || { echo "!! gpt-auto swap units still generated:"; find /run/systemd/generator.late -name '*.swap'; exit 1; }
echo "--- /proc/swaps"; cat /proc/swaps
echo "Done. No gpt-auto swap unit is generated any more; after a reboot /proc/swaps lists only /dev/zram0."
