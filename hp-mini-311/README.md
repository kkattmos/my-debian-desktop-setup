# HP Mini 311: the same setup on a 32-bit netbook

The Dell's setup (LUKS + Btrfs + Snapper, Ly, zsh + Powerlevel10k, LazyVim, Tailscale, the Gooey look),
rebuilt for an **HP Mini 311-1000** on **Debian 12 "bookworm" i386 + Xfce 4.18**.

## Why Debian 12 and not 13

| | |
|---|---|
| CPU | Intel Atom N280: 32-bit only (no `lm` flag), no AES acceleration |
| Firmware | legacy BIOS (no UEFI) |
| RAM / disk | 3 GB (2.7 GiB usable) / 320 GB spinning disk |
| Graphics | NVIDIA ION (GeForce 9400M), open `nouveau` driver |
| Network | Ethernet (`forcedeth`, no firmware needed), Broadcom BCM4312 Wi-Fi (`b43`, firmware downloaded after install), Ralink RT3070 USB dongle (`rt2800usb`, `rt2870.bin`) |

Debian 13 has no 32-bit installer or kernel ("there is no official kernel and no Debian installer for i386
systems", trixie release notes 5.1.2). Debian 12 i386 gets LTS security updates until **2028-06-30**.

## What is different from the Dell

| Dell (Debian 13, GNOME) | Mini (Debian 12 i386, Xfce) | Why |
|---|---|---|
| GNOME 48 + Tiling Shell | Xfce 4.18, xfwm4's own tiling (drag to an edge, `Super+←/→`, `Super+↑` maximize) | lighter; Tiling Shell is GNOME-only |
| Blur my Shell | **picom** blur behind the terminal, the panels and Firefox; `svc blur off` switches to xfwm4's plain compositor | GNOME extension |
| Gooey Shell extension + gtk.css | own **Gooey GTK3 theme** (Adwaita-dark recoloured) + Gooey window borders | Xfce uses GTK3 themes |
| Ptyxis | xfce4-terminal, same palette / 70% / font | Ptyxis isn't in Debian 12 |
| eza, `fzf --zsh` | exa, fzf's scripts | eza has no 32-bit build; fzf 0.38 |
| Neovim tarball | **compiled on the Mini** (+ tree-sitter CLI via Rust) | no 32-bit Neovim builds; tree-sitter's need glibc 2.39 |
| ONLYOFFICE | LibreOffice (follows the Gooey GTK theme) | no 32-bit ONLYOFFICE |
| SeaDrive (virtual drive) | `seaf-cli` sync into `~/Seafile/<library>` | no 32-bit SeaDrive |
| Docker, PhotoPrism, STM32CubeIDE, Packet Tracer | **not available** | 64-bit only |
| GRUB theme | not applied | no 1366×768 build; untested with BIOS graphics |

**Firefox ESR on 32-bit:** Mozilla promised security updates for 32-bit ESR 140 "until at least
September 2026". Debian 12 i386 has `140.12.0esr`; whether more updates come is not known.

## Walkthrough

Commands below are typed on the Mini.

### 0. Before you start
- **The CMOS battery is dead**, so every cold boot starts at a wrong date. You don't need to fix it in the
  BIOS: the installer takes the time from the network, and `m10-system.sh` (already in run 1) makes the
  installed system sync at **every boot**: `systemd-timesyncd` (NTP), plus `clock-from-http.service`
  (time from deb.debian.org's HTTP `Date` header when NTP gets no answer). It also sets
  `broken_system_clock = 1` in `/etc/e2fsck.conf`, so the boot-time check of `/boot` doesn't fail on the
  wrong date. Until the network is up after a boot, the clock shows the time of the last shutdown.
  Replacing the CMOS battery is the real fix.
- Have the **Ralink USB Wi-Fi dongle** plugged in, or an **Ethernet cable**.
- Download `debian-12.15.0-i386-netinst.iso` (+ `SHA512SUMS`) from
  `https://cdimage.debian.org/cdimage/archive/latest-oldstable/i386/iso-cd/`, check it, and copy it
  to the Ventoy stick. Copy this repo (or update it) on the stick: `debian-install/debian13-setup/`.

### 1. Install Debian 12 (graphical installer)
1. Boot the stick, pick the i386 netinst ISO, **Graphical install**.
2. Firmware popup for `b43/ucode15.fw`: answer **No**. That's the built-in Broadcom card; its
   firmware can't be shipped by Debian and is downloaded by `m10-system.sh` later.
3. Network: pick the **USB dongle** (`wlx…`) with your home WPA2 Wi-Fi (the installer can't join
   WPA2-Enterprise networks), or the Ethernet port `enp0s10`.
4. **Root password: leave it empty.** Your user then gets `sudo`.
5. Partitioning: **Manual**, the whole disk `sda` (this wipes the old install):
   - new empty partition table on `sda`
   - partition 1: **1 GB, ext4, mount point `/boot`**
   - partition 2: the rest, **use as: physical volume for encryption** → *Configure encrypted volumes*
   - on the `#1` line under the **Encrypted volume** heading (not the raw crypto partition):
     **btrfs, mount point `/`**
   - no swap (answer "No" to the swap warning: zram is set up later)
6. Software selection: untick everything except **standard system utilities**.
7. GRUB: install to the master boot record of `/dev/sda`.

### 2. System script (text console, twice)
Log in on the text console, mount the stick and run run 1:
```
lsblk
sudo mount /dev/sdb1 /mnt
sudo bash /mnt/debian-install/debian13-setup/hp-mini-311/m10-system.sh <your-username>
systemctl reboot
```
(`lsblk` shows which device is the stick; on the Mini it was `sdb`.) After the reboot, mount the stick
again and run the **same command** a second time. Run 2 installs everything, downloads the b43
firmware and compiles Ly; it takes a while. Then `systemctl reboot`.

### 3. First Xfce login
1. Ly comes up on tty2: pick **Xfce Session**, log in.
2. Panel question: **Use default config**.
3. Start **Firefox** once and close it (the look script needs its profile).
4. Open the terminal:
```
bash ~/debian13-setup/20-wifi.sh
bash ~/debian13-setup/hp-mini-311/m30-user.sh
```
`m30-user.sh` asks for: your sudo password, the Tailscale login (browser URL), the Seafile server
URL + login and which libraries to sync. Then it compiles Neovim and the tree-sitter CLI, which
**takes hours on the Atom**: plug in the charger and let it run.

5. Log out and back in. The p10k wizard starts in the first terminal.

### 4. Check
```
bash ~/debian13-setup/hp-mini-311/m32-check.sh
```
It prints the report and saves it as `~/m32-check-<host>-<date>.txt`; when the Ventoy stick is mounted
it also copies the file to the stick's `debian-install/` folder. Bring that file back, together with
screenshots of the desktop, the terminal and Thunar: colours are checked against the Dell by sampling
screenshots, not guessed.

## Things to try once it runs
- **Blur speed:** move the terminal around. If it stutters, `svc blur off` (see-through, no blur).
- **Firefox blur:** whether Firefox's page area goes see-through on X11 is not confirmed.
  `m32-check.sh` lists the window classes; picom's rule expects `firefox-esr`.
- **Super+Shift+1…4** (move window to workspace) and **Super+Space** (English/Thai).

## Files
| File | Run as | What |
|---|---|---|
| `m10-system.sh <user>` | `sudo`, twice | clock sync at every boot (dead CMOS battery); Btrfs subvolumes; APT; Tailscale repo; packages; b43 firmware; zram; Snapper; Ly (Zig x86); ifupdown → NetworkManager |
| `m30-user.sh` | user, in Xfce | zsh + p10k, Nerd Font, Sarabun (`../35-thai-font.sh`), fastfetch + lazygit, calls `m37`, Tailscale, Seafile, calls `m31` |
| `m31-neovim.sh` | user | builds Neovim + tree-sitter CLI, Python notebook env, LazyVim (`SKIP_TREESITTER=1` to skip Rust) |
| `m37-xfce-look.sh` | user, in Xfce | Gooey GTK3 + xfwm4 theme, Papirus, fonts, shortcuts, Thai layout, panels, wallpaper, terminal, picom, xscreensaver, Firefox, Neovim colours |
| `m32-check.sh` | user | read-only status report, saved to `~/m32-check-*.txt` (+ copy on the stick) |
| `gooey-gtk3-theme.py` | (called by m37) | recolours GTK's Adwaita-dark into Gooey |
| `dotfiles/` | | Mini-only files: zshrc, picom, cava (PulseAudio input), seafile.service, `nvim/…/i386.lua` |
| `../hw-report.sh` | any live system | hardware report used to plan this |
