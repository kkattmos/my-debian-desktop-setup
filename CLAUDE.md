# Debian 13 laptop setup kit

Scripts + guide that turn a fresh **Debian 13.7 "trixie"** netinst install into a lean GNOME 48
desktop with tiling and the "Gooey" frosted-glass look, dual-booting the existing Ubuntu on the same laptop.
`README.md` is the public showcase + install guide; the published guide is `guide.html` →
https://claude.ai/artifact/F62ZrkQMFMyFxCmGKEMHXu (republish with the Artifact tool, passing that `url`).

## Where things are
- **Git repo (main copy):** `~/Documents/debian13-setup` on the laptop, remote
  `github.com/kkattmos/my-debian-desktop-setup` (will be **public**; the user pushes, Claude only commits).
  `commands.txt` is an old pasted chat reply: keep it out of commits.
- **Ventoy USB stick** (exFAT, `/dev/sda1`), folder `debian-install/debian13-setup`; may be older than the repo.
  Mount point differs per machine:
  - on the Debian laptop: `/media/kkattmos/Ventoy/debian-install`
  - on the other machine: `/run/media/kkattmos/Ventoy/debian-install`
- exFAT has no Unix permissions: always run scripts as `bash script.sh`, never `./script.sh`.
- After editing files on the stick, run `sync` before telling the user to unplug it.
- Claude sessions usually run **on the laptop itself** (hostname `420pc`, the Claude desktop app, inside the
  user's GNOME session). There Claude can read state and run non-sudo commands directly; sudo needs the
  user's password, so sudo steps and interactive prompts (Seafile login etc.) are still run by the user.

## Target machine
- Laptop "420pc" (Dell Inspiron 14 5440): Intel Core 7 150U + NVIDIA GeForce MX570 A (not set up; runs on Intel), 32+ GB RAM, UEFI + Secure Boot, Realtek RTL8852BE Wi-Fi
  (rtw89 driver, needs `firmware-realtek`), Intel SOF audio, 1 TB NVMe `nvme0n1`, screen 2240×1400 (16:10), battery ~42 Wh (80% health).
- User `kkattmos` (uid 1000). Chulalongkorn student: ChulaWiFi is WPA2-Enterprise PEAP/MSCHAPv2,
  domain match `wifi.it.chula.ac.th`, no CA cert (copied from the Ubuntu NetworkManager profile).
- The Seafile server is reached over **Tailscale** (tailnet address), so Tailscale must be up before SeaDrive.

## Disk layout (as installed)
```
p1  1 GB   EFI (shared with Ubuntu, not formatted)
p2  466 GB Ubuntu ext4 (still in use; later absorbed by 90-absorb-ubuntu.sh)
p3  185 GB LUKS2 -> nvme0n1p3_crypt -> Btrfs  (Debian /)
p7  1 GB   ext4 /boot (placed at the END of the old p3 space on purpose)
p4, p5     150 GB ext4 each, unknown data - never touch
p6  763 MB Ubuntu swap (unencrypted - Debian must NOT use it; zram instead)
```
Btrfs subvolumes: `@rootfs` → `/` (installer's name, kept), `@home`, `@snapshots` → `/.snapshots`,
`@var_log`, `@var_cache`, `@docker` → `/var/lib/docker`. Mount options `noatime,compress=zstd:1`,
fstab uses `UUID=<btrfs fs uuid>`. Snapper snapshots only `/` (apt pre/post, keep 10).

## Decisions (agreed with the user - don't re-litigate)
- Normal graphical installer (user rejected Expert mode). Manual partitioning, LUKS kept.
- Minimal GNOME 48 from individual packages (no `gnome-core`, no GDM), APT with no recommends.
- Tiling: **Tiling Shell** extension (Forge unmaintained, Pop Shell not packaged).
- Login manager: **Ly 1.4.1** built from source with **Zig 0.16.0**, `-Denable_x11_support=false`
  (Ly is not packaged in Debian). Runs on tty2 (`ly@tty2.service`).
- Firefox ESR, no Chrome. ONLYOFFICE, Docker CE, Tailscale from their official APT repos.
- Docker and PhotoPrism are installed but OFF at boot; toggled with the `svc` zsh function.
- PhotoPrism: native `.deb` (not Docker), SQLite, user service.
- SeaDrive: **CLI** AppImage as a systemd **user** service + `loginctl enable-linger` (starts at boot).
- Neovim: upstream release tarball (Debian's 0.10 is too old) + LazyVim; `.ipynb` via
  jupytext.nvim + molten-nvim (python venv `~/.local/share/nvim-py`).
- Shell: plain zsh + **Powerlevel10k** (git clone to `~/.local/share/powerlevel10k`, no oh-my-zsh; user wanted the
  `p10k configure` wizard, 2026-09-28 - replaced Starship) + Debian-packaged plugins, one `~/.zshrc`.
  `~/.p10k.zsh` holds the wizard's answers and is never overwritten.
- STM32CubeIDE **1.9.1** (course requirement) needs `libncurses5`/`libtinfo5` from Debian 12
  (sha256-pinned in 10-system.sh) and a `GDK_BACKEND=x11` wrapper. NOTE: the laptop actually has
  `st-stm32cubeide-1.19.0` (ST's .deb bundle, installed by hand); 40-stm32cubeide.sh still targets 1.9.1 -
  ask the user before changing either.
- Thai fallback font: **Sarabun** (not packaged; per-user). Its `<prefer>` lists Noto Sans/DejaVu first so Latin is
  unchanged; monospace keeps TLWG. Test fallback with `fc-match -s` + first font whose charset has `e01-e3a`
  (plain `fc-match Family:lang=th` just returns the named family).
- Packet Tracer 9.0.1 from the Ubuntu .deb (libfuse2 is satisfied by libfuse2t64).
- Terminal: **Ptyxis 48.5** replaces GNOME Console (Console 48 has no palette UI). Per-user dconf profile:
  palette **`'Gooey'`** (built-in; replaced Tokyo Night 2026-09-29), opacity **0.70**, font
  `JetBrainsMono Nerd Font 12`, dark. fastfetch runs from ~/.zshrc above the p10k instant prompt only when
  `$PTYXIS_VERSION` is set and `SHLVL==1` (desktop SHLVL is 0). cava uses pipewire input.
- **"Gooey everywhere" look** (2026-09-29, 37-desktop-look.sh). Palette: navy `#0D101B`, raised `#1F222D`,
  hover `#2A2E3C`, blue `#6488C4`, bright blue `#97BBF7`, off-white `#EBEEF9`; the 16 ANSI colours are in
  `dotfiles/nvim/lua/plugins/colorscheme.lua`.
  - **Blur my Shell** live blur ONLY on `org.gnome.Ptyxis`, `org.gnome.Nautilus`, `firefox-esr` (sigma 22,
    `dynamic-opacity=false`, `opacity=255`). User chose live blur over static+vivid (colour boost only works in
    static mode). Top bar: **static** (wallpaper-only) blur, pipeline `pipeline_gooey_panel`, brightness 0.30.
    Settings live in `dotfiles/dconf/blur-my-shell.ini` (from `dconf dump`, applied with `dconf load`).
  - Battery (measured 2026-09-29): live blur on every app + top bar = +3.7-4.2 W. Current set: +0.03 W idle,
    +1.2 W terminal scrolling, +1.4-2.0 W while blurred Firefox is visible (user kept Firefox blurred).
  - Every other libadwaita app: SOLID Gooey navy via `~/.config/gtk-4.0/gtk.css` (not blurred, so must be opaque);
    Files keeps 70% navy (`window.view`); Ptyxis excluded (`:not(.ptyxis-window)`).
  - Shell (dock, quick settings, calendar, menus, notifications, dialogs, OSD, Alt+Tab): own stylesheet-only
    extension **`gooey-dock@kkattmos`** (display name "Gooey Shell" - the uuid stays, see lessons).
  - Own extension **`workspace-label@kkattmos`** (workspace name in the top bar, click to rename).
  - Also enabled: **Switch Workspace** (`switchWorkSpace@sun.wxg@gmail.com`, `Ctrl+Above_Tab`).
    `System_Monitor@bghome.gmail.com` is a stale enabled-list entry with no files; 31 drops it.
  - Firefox ESR: `user.js` + `chrome/userChrome.css` (solid navy header, `#browser` 70% navy) + `userContent.css`.
    The user's Kanagawa Wave True theme stays installed; overrides need `!important`.
  - ONLYOFFICE: `~/.local/share/onlyoffice/Gooey.json` (imported once by hand; the imported copy is
    `desktopeditors/uithemes/Gooey.json`). Last key injects a CSS rule forcing Cantarell (workaround).
  - Papirus-Dark icons, Cantarell 12, 24h clock, battery %, wallpaper `wallhaven-72mrmv.jpg` (sha256-pinned,
    downloaded at install time - never commit the image).
  - GRUB: **Space Isolation** theme (2026-10-01, 38-grub-theme.sh), 1920x1080 build with `GRUB_GFXMODE=1920x1080,auto`
    (the screen is 2240x1400; no matching build exists).
  - NOT themed, on purpose: Claude desktop and Discord (Electron; would need app.asar patching / a ToS-breaking
    client mod - user declined), GTK3 apps (Disks). STM32CubeIDE colours are per-workspace prefs, done by hand in
    `~/Documents/2026a-repo/embedded-sys-lab-workspace` (keys include `org.eclipse.ui.r30.`); panels stay #2F2F2F.

## Script order
| Script | Run as | Notes |
|---|---|---|
| `00-ubuntu-prep.sh` | user, on Ubuntu | ISO download/verify, stash, write USB |
| `10-system.sh <user>` | `sudo`, twice | run 1: Btrfs subvolumes + compression + disable Ubuntu swap, reboot; run 2: everything else |
| `20-wifi.sh` | user | ChulaWiFi + home Wi-Fi via nmcli (system-owned secrets); no SSIDs in the file |
| `30-user.sh` | **user, no sudo** | zsh, Nerd Font, Neovim/LazyVim, calls 35/31/36/37, Tailscale, SeaDrive (URL asked, no default), PhotoPrism |
| `31-gnome-settings.sh` | **user, no sudo** | installs 3 e.g.o extensions (Tiling Shell, Blur my Shell, Switch Workspace) + 2 own ones from `dotfiles/gnome-shell/extensions`; GNOME settings as dconf system defaults |
| `32-check.sh` | user | read-only status report - ask the user for its output first when debugging |
| `33-clean-root-leftovers.sh` | `sudo` | one-off: removes what an accidental `sudo bash 30-user.sh` put in /root |
| `34-no-ubuntu-swap.sh` | `sudo` | one-off: masks systemd-gpt-auto-generator (/dev/null symlink), swapoff p6; 10-system.sh now does this too |
| `35-thai-font.sh` | **user, no sudo** | Sarabun TTFs (Google Fonts) + `~/.config/fontconfig/conf.d/60-thai-sarabun.conf`; called by 30 |
| `36-terminal-look.sh` | **user** (sudo only for missing pkgs) | ptyxis/fastfetch/cava, Ptyxis profile via `dconf write` + read-back, `~/.config/xdg-terminals.list`, installs fastfetch/cava configs + zshrc (.bak if different); called by 30 |
| `37-desktop-look.sh` | **user** (sudo only if no Papirus icons) | `dconf load` Blur my Shell + Tiling Shell layouts (verified key by key), interface keys, wallpaper, gtk.css, nvim colorscheme, Firefox profile files, ONLYOFFICE theme; called by 30. Needs a Firefox ESR profile (start Firefox once) |
| `38-grub-theme.sh` | `sudo`, optional | Space Isolation GRUB theme v0.2.0 (1920x1080 release tarball, sha256-pinned) → `/boot/grub/themes/space-isolation`; sets GRUB_THEME/BACKGROUND/TERMINAL_OUTPUT/GFXMODE (by sourced value, so quoting differences don't count), update-grub, checks grub.cfg |
| `40-stm32cubeide.sh`, `41-packettracer.sh` | user | need the user's own downloads (st.com / NetAcad logins) |
| `90-absorb-ubuntu.sh` | `sudo`, later | moves Debian onto p2 (btrfs device add/remove), deletes p3, grows p2; resumable |

`dotfiles/` mirrors the live files: `zshrc`, `fastfetch/`, `cava/`, `nvim/lua/plugins/` (colorscheme, notebook,
web), `gnome-shell/extensions/`, `dconf/`, `gtk-4.0/`, `firefox/`, `onlyoffice/`, `systemd/`.
When the user tweaks the look by hand, copy the live file back into `dotfiles/` (`dconf dump` for dconf dirs;
drop internal keys like `rounded-blur-found`, and for Tiling Shell keep only `layouts-json`/`selected-layouts`,
never `overridden-settings`).

## Status (2026-09-30)
- Install done; 10-system.sh runs 1+2 done; Ly works (PAM `class=user`); 30-user.sh done as the user
  (GNOME ok, SeaDrive active + mounted, PhotoPrism env written); 33 cleanup done; Ptyxis + Gooey look done by hand
  in sessions on 2026-09-28/29, now captured in 36/37 + dotfiles.
- 37-desktop-look.sh was run on the laptop 2026-09-30: all keys read back ok (no visible change, same values).
- 31 (new extension list) has NOT been rerun on the laptop yet (needs sudo): the system default still lists only
  Tiling Shell; the user's own enabled-extensions value holds all of them, so nothing is broken.
- **Ubuntu's p6 swap is still active** (32-check `!!`): the user must run `sudo bash 34-no-ubuntu-swap.sh` + reboot.
- Also installed by hand, not scripted: claude-desktop (apt repo), discord, zoom, postman (snap), pysolfc.
- GRUB theme installed by hand 2026-10-01 (same files/values as 38; running 38 changes nothing).
- **`GRUB_DISABLE_OS_PROBER=false` is missing** from the laptop's `/etc/default/grub` (10-system.sh adds it;
  how it got lost is unknown, no backup), so Ubuntu has no GRUB entry. 32-check shows `GRUB os-prober off`.
- Not yet done: 20-wifi.sh (unknown), 40/41 course tools via the scripts, 90 (Ubuntu still kept).
  guide.html has NOT been updated for 37 / Gooey yet (still says Tokyo Night, 88%).

## Second machine: HP Mini 311 (`hp-mini-311/`, branch `hp-mini-311`)
- HP Mini 311-1000: Atom N280 (**32-bit only**, no AES-NI), legacy BIOS, 2.7 GiB RAM, 320 GB HDD `sda`,
  NVIDIA ION (nouveau), Ethernet `forcedeth`, Broadcom BCM4312 `14e4:4315` (b43 → `firmware-b43-installer`,
  contrib, downloads at install), Ralink RT3070 USB dongle (`rt2870.bin` in firmware-misc-nonfree).
  CMOS clock was months behind. Hardware facts come from `hw-report.sh` output - ask for a new one rather than assume.
- Agreed (2026-10-01): **Debian 12 bookworm i386** (Debian 13 has no i386 kernel/installer; bookworm LTS to
  2028-06-30), wipe whole disk, LUKS + Btrfs + Snapper kept, **Xfce 4.18** (X11), Ly kept (Zig `x86-linux`,
  X11 support on), xfwm4 built-in tiling, picom 9.1 `--experimental-backends` dual_kawase blur (terminal,
  panels, Firefox), LibreOffice instead of ONLYOFFICE, `seaf-cli` sync instead of SeaDrive, Neovim **built on the
  Mini** + tree-sitter CLI via rustup. Skipped (64-bit only): Docker, PhotoPrism, STM32CubeIDE, Packet Tracer.
- Scripts: `m10-system.sh` (sudo, twice), `m30-user.sh` (calls m37 + m31), `m31-neovim.sh`, `m37-xfce-look.sh`,
  `m32-check.sh`, `gooey-gtk3-theme.py`. Shared with the Dell: `35-thai-font.sh`, `20-wifi.sh`,
  `dotfiles/{fastfetch,nvim,firefox}`. Mini-only files in `hp-mini-311/dotfiles/`.
- NOT yet run on the Mini (written 2026-10-01). Unverified until then: Ly + Xorg start, picom speed on ION,
  Firefox see-through on X11 (`widget.transparent-windows`), xfwm4 themerc colour keys, `<Super><Shift>N`
  bindings, power-manager `show-panel-label=1` = percentage, the GTK3 colour mapping (check screenshots).
- Lessons from writing it:
  - Verify i386 package names against `dists/bookworm/*/binary-i386/Packages.xz`; inspect real .debs
    (`dpkg-deb -x`) for xfconf property names instead of guessing.
  - All official 32-bit tree-sitter CLI builds need glibc 2.39 (bookworm: 2.36) → build with cargo.
  - A user `~/.config/gtk-3.0/gtk.css` outranks the Xfce panel's and terminal's own backgrounds (USER >
    APPLICATION priority) → recolour a whole theme instead (gooey-gtk3-theme.py, assets via `resource:///`).
  - xfwm4 ignores `/xfwm4/custom/*` shortcuts unless `/xfwm4/custom/override=true` with a full copy of the defaults.
  - PyPI has no i686 wheels for psutil/tornado/debugpy → Debian's python3-* packages + `venv --system-site-packages`.

## Hard-won lessons (bugs already hit - don't reintroduce)
- **`gsettings set` exits 0 even when it cannot save** (no session bus) - it only warns.
  `gsettings get` reads the dconf file directly, so it does NOT prove the bus works. GNOME settings
  are therefore written as dconf system defaults (`/etc/dconf/profile/user` + `/etc/dconf/db/local.d/`
  + `sudo dconf update`) and verified by reading back. Per-user values override these defaults.
- GNOME (g-s-d) writes a **per-user** `input-sources sources` at the first login, which hides the system
  default. 31 compares `dconf read` with `dconf read -d` and `dconf reset`s only differing managed keys
  (needs the session bus). `dconf dump /` also prints system-db values, so it is useless for finding overrides.
- `dconf read` prints doubles with 17 digits (0.70 → `0.69999999999999996`): 36/37 compare numbers as numbers.
- **User scripts must refuse `EUID 0`.** `systemctl --user` printing "consider using
  --machine=<user>@.host" is the tell-tale sign a script ran as root.
- **`set -euo pipefail` + a `grep` that matches nothing kills the script silently.** Never use grep
  for display-only output; avoid `| head -1` under pipefail (use `sed -n 1p` or `grep -m1`). For globs that may
  match nothing use `shopt -s nullglob` + an array, not `ls | ...`.
- Ly's upstream PAM file registers the desktop as `pam_systemd.so class=greeter` → wrong session
  class; 10-system.sh rewrites it to `class=user`.
- **systemd-gpt-auto-generator activates any "Linux swap" GPT partition** (p6) with no fstab entry at all.
  Fix = mask the generator: `/etc/systemd/system-generators/systemd-gpt-auto-generator -> /dev/null`
  (no GRUB/cmdline change; everything else gpt-auto could mount is already in fstab). Never alter p6
  itself (type, attributes, format): Ubuntu still uses it.
- The Debian installer activated Ubuntu's unencrypted swap even when set to "do not use";
  10-system.sh run 1 comments it out of fstab and removes `/etc/initramfs-tools/conf.d/resume`.
- journald files are NOCOW: `cp --reflink=always` fails on them - use `--reflink=auto`.
- Installer Wi-Fi lands in `/etc/network/interfaces` (ifupdown); 10-system.sh converts it to NetworkManager.
- `swapon` etc. are in `/usr/sbin`, not on a normal user's PATH - read `/proc/swaps` instead.
- The installer can't join WPA-Enterprise networks: install over home WPA2-PSK Wi-Fi.
- In the partitioner, the filesystem goes on the `#1` line under the "Encrypted volume" heading,
  not on the raw `crypto` partition (that gives "in use as physical volume for encrypted volume").
- In Claude's Bash tool on the laptop, `grep` is a wrapper function (ugrep); test regexes with `/usr/bin/grep`.
- The auto-mode classifier blocks Claude from launching `sudo` commands in the Terminal panel: give the user
  the command to run instead. Non-sudo interactive scripts can be started there (`run_in_terminal`).
  It also flakes ("no verdict") in bursts: fall back to Read/Write for file work instead of retrying Bash 10×.
- Ly starts the session from tty2, so **`TERM=linux` leaks into the whole GNOME session** (user manager, gnome-shell,
  kgx) and GNOME Console passes it to the shell. p10k then assumes 8 colours + no Unicode: the wizard doesn't
  auto-start and `p10k configure` skips the style/icon questions (writes `ascii, lean_8colors`). The zshrc resets
  TERM to xterm-256color when on a pts inside a graphical session. The Claude Terminal panel already has xterm-256color.
- zsh (Claude's local shell) treats an unquoted `==` word as an error: use `echo '----'` in Bash tool calls.
- **Theming (Gooey):**
  - Never set `GTK_THEME` for libadwaita apps: libadwaita then skips its own stylesheet (no switches, cards,
    rounded corners). Use `~/.config/gtk-4.0/gtk.css` with `:not(...)` selectors to win on specificity.
  - GNOME on Wayland loads a NEW extension folder only at the next login; renaming the folder of a running
    extension breaks it until then. Hence the uuid `gooey-dock@kkattmos` is kept despite the "Gooey Shell" name.
  - Blur my Shell `dynamic-opacity` un-blurs the focused window - keep it false. Its app blur can't boost
    saturation; only static blur can. Shell popovers (quick settings, calendar) can't be blurred (square corners).
  - Apps not on the blur list must be opaque, or sharp windows behind show through.
  - Firefox: `--toolbox-bgcolor` also paints the page area; paint `#browser` directly. Check colours by sampling
    the user's screenshots, not by assuming ("Do not guess" - the user's words).
  - ONLYOFFICE's start page reads a different set of theme variables than the editors.
  - Electron apps (Claude desktop, Discord) ignore GTK CSS and create opaque windows.
- GRUB theme: `GRUB_THEME` must point at a `theme.txt` that exists - Debian's `00_header` silently drops the theme
  otherwise (no error; look for `Found theme:` in the update-grub output). The space-isolation repo keeps `theme.txt`
  in per-resolution subfolders, so cloning the repo into `/boot/grub/themes` doesn't work. After a menu entry is
  picked, the theme is gone and `05_debian_theme`'s background shows (desktop-base's blue one unless
  `GRUB_BACKGROUND` is set). `/boot/grub/grub.cfg` is root-only (0600): Claude can't read it, ask the user.
- `run 37 on the laptop` = safe verification: every value equals the live state, put() only writes `.bak` when a file differs.

## Working conventions
- Scripts must be **idempotent / resumable**: check state before each step, keep `.bak`/`.installer-bak` copies.
- Every change that can brick boot (fstab, crypttab, initramfs, GRUB) is verified before the script
  says it's safe to reboot (`findmnt --verify`, unpacking the initramfs, grepping grub.cfg).
- Verify package names against the real Debian 13 index before adding them
  (`https://deb.debian.org/debian/dists/trixie/main/binary-amd64/Packages.xz`).
- After editing scripts: `bash -n` every file, test any sed/awk on a realistic sample, `sync` (stick),
  and give the user the sha256 prefix so they can confirm the copy on the laptop.
- Keep **README.md**, the guide page and CLAUDE.md in sync with the scripts; republish the guide to the same artifact URL.
- Privacy (the repo is public): never put the student ID, Wi-Fi SSIDs, passwords/tokens or the Tailscale/Seafile
  address into any committed file or the guide. Grep for `100\.[0-9]+\.` and SSIDs before committing.
- Commands the user types on the laptop go in plain (untagged) code fences - they can't be run here.
- Commit locally with the user's git identity; the user pushes to GitHub.
