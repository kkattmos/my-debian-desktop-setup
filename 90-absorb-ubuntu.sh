#!/usr/bin/env bash
# LATER, once you are happy with Debian: give Ubuntu's partition to Debian and end up with
# ONE encrypted partition, done while Debian is running.
#
#   before:  p1 EFI | p2 Ubuntu        | p3 Debian (LUKS) | /boot | p4 | p5 | p6
#   after:   p1 EFI | p2 Debian (LUKS, ~650 GB)           | /boot | p4 | p5 | p6
#
# How: encrypt p2 -> add it to the Btrfs filesystem -> `btrfs device remove` the old partition
# (Btrfs copies your data onto p2) -> delete the old partition -> grow p2 over the gap.
# Needs the install-time layout from the guide: Debian's encrypted partition directly after p2.
#
# Every step checks whether it is already done, so after an interruption or a reboot just run it
# again. Rebooting is safe at any point: /etc/crypttab always lists what the next boot needs.
#
#   sudo bash 90-absorb-ubuntu.sh              # full merge into one partition
#   sudo bash 90-absorb-ubuntu.sh --join-only  # only add p2 to the filesystem (two partitions)
set -euo pipefail
DISK=/dev/nvme0n1
P2=${DISK}p2
NEW=nvme0n1p2_crypt
STATE=/var/lib/absorb-ubuntu.env
JOIN_ONLY=0; [[ ${1:-} == --join-only ]] && JOIN_ONLY=1

step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m!! %s\033[0m\n' "$*"; exit 1; }
[[ $EUID -eq 0 ]] || die "run with sudo"

in_fs() { btrfs filesystem show / | grep -qE "path $1\$"; }

# Replace the lines for OLD/NEW in /etc/crypttab, keep everything else.
crypttab_set() {
  [[ -f /etc/crypttab.before-absorb ]] || cp /etc/crypttab /etc/crypttab.before-absorb
  grep -vE "^[[:space:]]*($OLDNAME|$NEW)[[:space:]]" /etc/crypttab > /etc/crypttab.new || true
  printf '%s\n' "$@" >> /etc/crypttab.new
  mv /etc/crypttab.new /etc/crypttab
  echo "--- /etc/crypttab"; grep -v '^#' /etc/crypttab
}

# Rebuild the initramfs and prove it will unlock every given LUKS UUID at boot.
rebuild_and_verify() {
  update-initramfs -u -k all
  local tmp ct u
  tmp=$(mktemp -d)
  unmkinitramfs "/boot/initrd.img-$(uname -r)" "$tmp"
  ct=$(find "$tmp" -path '*cryptroot/crypttab' | head -1)
  [[ -n $ct ]] || { rm -rf "$tmp"; die "initramfs has no cryptroot/crypttab - DO NOT REBOOT, check /etc/crypttab"; }
  for u in "$@"; do
    grep -q "$u" "$ct" || { rm -rf "$tmp"; die "initramfs will not unlock UUID=$u - DO NOT REBOOT, check /etc/crypttab"; }
  done
  rm -rf "$tmp"
  echo "initramfs verified: unlocks $*"
}

step "Tools (parted, growpart)"
apt-get -y install parted cloud-guest-utils >/dev/null

# ---------- find Debian's current encrypted partition (remembered across runs) ----------
if [[ -f $STATE ]]; then
  source "$STATE"
else
  SRC=$(findmnt -no SOURCE / | sed 's/\[.*//')
  OLDNAME=$(basename "$SRC")
  OLDPART=$(cryptsetup status "$OLDNAME" 2>/dev/null | awk '$1=="device:"{print $2}')
  [[ -n $OLDPART && $OLDPART != "$P2" ]] || die "could not find Debian's encrypted partition behind $SRC"
  printf 'OLDNAME=%s\nOLDPART=%s\nOLDUUID=%s\n' "$OLDNAME" "$OLDPART" "$(cryptsetup luksUUID "$OLDPART")" > "$STATE"
  source "$STATE"
fi
OLDNUM=${OLDPART##*p}
FSUUID=$(findmnt -no UUID /)
echo "Debian now: $OLDPART ($OLDNAME), Btrfs UUID $FSUUID"

# ---------- safety checks ----------
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$DISK"
findmnt -rn -S "$P2" >/dev/null && die "$P2 is mounted - unmount it first"
if [[ $JOIN_ONLY == 0 && -e $OLDPART ]]; then
  s() { cat "/sys/class/block/$(basename "$1")/$2"; }
  gap=$(( $(s "$OLDPART" start) - $(s "$P2" start) - $(s "$P2" size) ))
  (( gap >= 0 && gap < 4096 )) || die "$OLDPART does not start right after $P2 (gap: $gap sectors), so p2 cannot be grown over it.
   Use --join-only instead (p2 joins the filesystem, you keep two partitions)."
fi

# ---------- 1. encrypt p2 ----------
if ! cryptsetup isLuks "$P2"; then
  step "1. Wipe Ubuntu and encrypt $P2"
  echo "Back up anything you still need from Ubuntu FIRST (sudo mount -o ro $P2 /mnt)."
  read -rp "Type ERASE-UBUNTU to wipe $P2: " ok
  [[ $ok == ERASE-UBUNTU ]] || exit 1
  for n in $(efibootmgr | awk '/[Uu]buntu/{sub(/^Boot/,"",$1); sub(/\*$/,"",$1); print $1}'); do efibootmgr -b "$n" -B; done
  rm -rf /boot/efi/EFI/ubuntu
  wipefs -a "$P2"
  echo "Use the SAME passphrase as your Debian disk (so one prompt unlocks both during the move)."
  cryptsetup luksFormat --type luks2 "$P2"
fi
[[ -e /dev/mapper/$NEW ]] || cryptsetup open "$P2" "$NEW"
NEWUUID=$(cryptsetup luksUUID "$P2")

# ---------- 2. fstab by filesystem UUID (the /dev/mapper name of the old partition goes away) ----------
step "2. /etc/fstab: mount by Btrfs UUID"
[[ -f /etc/fstab.before-absorb ]] || cp /etc/fstab /etc/fstab.before-absorb
sed -i -E "s|^/dev/mapper/$OLDNAME([[:space:]])|UUID=$FSUUID\1|" /etc/fstab
grep -q "^/dev/mapper/$OLDNAME" /etc/fstab && die "fstab still references /dev/mapper/$OLDNAME"
grep -c "UUID=$FSUUID" /etc/fstab | xargs echo "fstab lines using the Btrfs UUID:"

# ---------- 3. boot must unlock both devices while data is being moved ----------
step "3. crypttab + initramfs: unlock both partitions with one passphrase"
if [[ -e $OLDPART ]]; then
  crypttab_set \
    "$OLDNAME UUID=$OLDUUID debian luks,discard,keyscript=decrypt_keyctl" \
    "$NEW UUID=$NEWUUID debian luks,discard,initramfs,keyscript=decrypt_keyctl"
  rebuild_and_verify "$OLDUUID" "$NEWUUID"
fi

# ---------- 4. add p2 to the filesystem ----------
step "4. Add p2 to the Btrfs filesystem"
in_fs "/dev/mapper/$NEW" || btrfs device add -f "/dev/mapper/$NEW" /
btrfs filesystem show /

if [[ $JOIN_ONLY == 1 ]]; then
  update-grub
  echo "Done (join-only): one filesystem on two partitions, one passphrase at boot."
  exit 0
fi

# ---------- 5. move everything off the old partition ----------
if in_fs "/dev/mapper/$OLDNAME"; then
  step "5. Move data onto p2 (btrfs device remove) - can take a while, safe to interrupt"
  used=$(btrfs filesystem usage -b / | awk '$1=="Used:"{print $2; exit}')
  room=$(blockdev --getsize64 "/dev/mapper/$NEW")
  (( used < room * 9 / 10 )) || die "not enough room on p2 for $((used>>30)) GiB"
  echo "Moving about $((used>>30)) GiB ..."
  btrfs device remove "/dev/mapper/$OLDNAME" /
fi
in_fs "/dev/mapper/$OLDNAME" && die "old partition is still part of the filesystem"

# ---------- 6. boot only needs p2 from now on ----------
step "6. crypttab + initramfs: only p2"
crypttab_set "$NEW UUID=$NEWUUID none luks,discard,initramfs"
rebuild_and_verify "$NEWUUID"

# ---------- 7. delete the old partition ----------
if [[ -e $OLDPART ]]; then
  step "7. Delete the old partition $OLDPART"
  [[ -e /dev/mapper/$OLDNAME ]] && cryptsetup close "$OLDNAME"
  wipefs -a "$OLDPART"
  parted -s "$DISK" rm "$OLDNUM"
  partprobe "$DISK" 2>/dev/null || partx -d --nr "$OLDNUM" "$DISK" 2>/dev/null || true
fi

# ---------- 8. grow p2 over the gap, then LUKS, then Btrfs ----------
step "8. Grow p2 -> LUKS -> Btrfs"
rc=0; growpart "$DISK" 2 || rc=$?
(( rc <= 1 )) || die "growpart failed (rc=$rc)"   # 1 = already grown
echo "cryptsetup may ask for the passphrase once more:"
cryptsetup resize "$NEW"
DEVID=$(btrfs filesystem show / | awk -v p="/dev/mapper/$NEW" '$NF==p{print $2}')
btrfs filesystem resize "$DEVID:max" /

# ---------- 9. finish ----------
step "9. GRUB"
update-grub
grep -q "root=UUID=$FSUUID" /boot/grub/grub.cfg || die "grub.cfg does not boot root=UUID=$FSUUID - check /etc/default/grub before rebooting"
apt-get -y purge cloud-guest-utils >/dev/null
rm -f "$STATE"

lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$DISK"
btrfs filesystem usage -T /
echo
echo "Done: one encrypted partition ($P2). Reboot and check that one passphrase prompt appears."
echo "Backups of the old files: /etc/fstab.before-absorb, /etc/crypttab.before-absorb"
echo "Ubuntu's old swap (p6, 763 MB) is unused; you may delete it with GNOME Disks."
