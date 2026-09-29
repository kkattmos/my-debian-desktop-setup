#!/usr/bin/env bash
# Run on the CURRENT Ubuntu system, as your normal user.
# 1. Checks that nvme0n1p3 (the future Debian partition) holds nothing you need.
# 2. Downloads + verifies the official Debian 13 netinst ISO.
# 3. Stashes this kit + installers in ~/debian13-stash (Debian will read it from p2 later).
# 4. Optionally writes the ISO to a USB stick (asks twice).
set -euo pipefail

ISO=debian-13.7.0-amd64-netinst.iso
BASE=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
STASH="$HOME/debian13-stash"
KIT="$(cd "$(dirname "$0")" && pwd)"

echo "== 1. What is on nvme0n1p3?"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS /dev/nvme0n1
tmp=$(mktemp -d)
if sudo mount -o ro /dev/nvme0n1p3 "$tmp" 2>/dev/null; then
  echo "Top-level contents of p3 (used: $(df -h --output=used "$tmp" | tail -1)):"
  sudo ls -la "$tmp" | head -30
  sudo umount "$tmp"
else
  echo "p3 could not be mounted (maybe empty/unformatted) - fine."
fi
rmdir "$tmp"
read -rp "Everything on p3 will be DESTROYED by the Debian installer. Continue? [y/N] " a
[[ $a == [yY] ]] || exit 1

echo "== 2. Download + verify ISO"
mkdir -p "$STASH"
cd "$STASH"
curl -fLO -C - "$BASE/$ISO"
curl -fLO "$BASE/SHA512SUMS"
curl -fLO "$BASE/SHA512SUMS.sign"
if command -v gpg >/dev/null; then
  # Debian CD signing key (listed on https://www.debian.org/CD/verify)
  gpg --keyserver keyring.debian.org --recv-keys DF9B9C49EAA9298432589D76DA87E80D6294BE9B || true
  gpg --verify SHA512SUMS.sign SHA512SUMS || { echo "!! signature check failed"; exit 1; }
fi
grep " $ISO\$" SHA512SUMS | sha512sum -c -

echo "== 3. Stash kit + installers"
cp -r "$KIT" "$STASH/kit"
for f in ~/Downloads/CiscoPacketTracer_*_Ubuntu_64bit.deb ~/Downloads/*stm32cubeide*1.9.1*; do
  [[ -e $f ]] && cp -v "$f" "$STASH/"
done
echo "Put the STM32CubeIDE 1.9.1 Linux installer (from st.com) into $STASH too if it is not there yet."
ls -la "$STASH"

echo "== 4. Write USB (optional)"
lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -E 'usb|NAME'
read -rp "USB device to OVERWRITE (e.g. sdb), or empty to skip: " dev
if [[ -n $dev ]]; then
  [[ $dev == nvme* ]] && { echo "refusing to write to an NVMe disk"; exit 1; }
  read -rp "Type YES to erase /dev/$dev: " ok
  [[ $ok == YES ]] || exit 1
  sudo dd if="$STASH/$ISO" of="/dev/$dev" bs=4M status=progress oflag=sync
  echo "USB ready."
fi
