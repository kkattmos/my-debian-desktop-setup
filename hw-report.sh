#!/usr/bin/env bash
# Read-only hardware report for a machine we haven't set up yet (e.g. the HP Mini 311).
# Run it from any live Linux system:   bash hw-report.sh
# Optional, for the kernel's firmware/driver messages:   sudo bash hw-report.sh
# Writes hw-report-<model>-<date>.txt next to this script (or to $HOME if that folder is read-only).
# No set -e on purpose: a missing tool (lspci, lsusb, ...) must not stop the report.
set -u

here=$(cd "$(dirname "$0")" && pwd)
model=$(tr -c 'A-Za-z0-9\n' '-' < /sys/class/dmi/id/product_name 2>/dev/null | sed -n 1p)
name="hw-report-${model:-unknown}-$(date +%Y%m%d-%H%M).txt"
if [ -w "$here" ]; then out="$here/$name"; else out="$HOME/$name"; fi

section() { printf '\n===== %s =====\n' "$1"; }
run() {     # run a command, or say why it couldn't
    section "$*"
    if command -v "$1" >/dev/null 2>&1; then "$@" 2>&1; else echo "(not installed: $1)"; fi
}

{
    echo "hw-report  $(date -Is)  user=$(id -un)  euid=$EUID"

    section "machine (DMI)"
    for f in sys_vendor product_name product_version bios_version bios_date; do
        printf '%-16s %s\n' "$f" "$(cat /sys/class/dmi/id/$f 2>/dev/null || echo '?')"
    done

    section "CPU"
    if grep -qw lm /proc/cpuinfo; then echo "64-bit capable (lm flag present)"; else echo "32-bit only (no lm flag)"; fi
    grep -m1 'model name' /proc/cpuinfo
    grep -m1 '^flags' /proc/cpuinfo

    section "boot mode"
    if [ -d /sys/firmware/efi ]; then echo "UEFI"; else echo "legacy BIOS"; fi

    section "running kernel / live system"
    uname -a
    sed -n '1,4p' /etc/os-release 2>/dev/null

    run free -h
    run lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,ROTA
    run lspci -nnk          # -k: which kernel driver is bound to each device
    run lsusb
    run rfkill list         # Wi-Fi hard/soft block switch
    run nmcli -f DEVICE,TYPE,STATE device

    section "network interfaces (names only)"
    ls /sys/class/net

    section "kernel messages about firmware / wifi / ethernet"
    if [ "$EUID" -eq 0 ]; then
        dmesg 2>&1 | grep -iE 'firmware|wlan|wifi|80211|b43|brcm|wl |ath|rtl|r8169|sky2|eth' || echo "(no matches)"
    else
        echo "(skipped: needs root - rerun with sudo bash hw-report.sh to include it)"
    fi
} > "$out" 2>&1

sync
echo "Report written to: $out"
