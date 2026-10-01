#!/usr/bin/env bash
# GRUB theme "Space Isolation" (github.com/callmenoodles/space-isolation, MIT), its 1920x1080 build,
# downloaded from the release and sha256-pinned. Optional; safe to rerun:
#   sudo bash 38-grub-theme.sh
# The screen is 2240x1400 and the theme only comes in 1920x1080 / 2560x1440: GRUB_GFXMODE=1920x1080,auto
# falls back to the native mode if the firmware has no 1920x1080 (the menu is placed in percentages).
# GRUB_BACKGROUND is the theme's own picture: without it Debian's /etc/grub.d/05_debian_theme puts
# desktop-base's blue wallpaper behind the "Loading Linux ..." lines once the menu is gone.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
VER=v0.2.0
URL=https://github.com/callmenoodles/space-isolation/releases/download/$VER/space-isolation-1920x1080.tar.gz
SHA256=02dddc62324bfc03b77311d7c39029ef42e0a0a75b0e05a8cfb81269ce3fbb8c
DIR=/boot/grub/themes/space-isolation
CONF=/etc/default/grub
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BAD=0

step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
value() {  # KEY - what update-grub will see (the file is sourced, so quoting doesn't matter)
  bash -c '. "$1" >/dev/null 2>&1; printf %s "${!2-}"' _ "$CONF" "$1"
}
BACKED_UP=0
want() {  # KEY VALUE - sets KEY="VALUE" in place (or uncomments it, or appends it), then reads it back
  if [[ $(value "$1") != "$2" ]]; then
    (( BACKED_UP )) || { cp "$CONF" "$CONF.bak"; BACKED_UP=1; echo "  kept the old file as $CONF.bak"; }
    if grep -q "^$1=" "$CONF"; then sed -i "s|^$1=.*|$1=\"$2\"|" "$CONF"
    elif grep -Eq "^#[[:space:]]*$1=" "$CONF"; then sed -i -E "0,/^#[[:space:]]*$1=.*/s||$1=\"$2\"|" "$CONF"
    else echo "$1=\"$2\"" >>"$CONF"; fi
  fi
  if [[ $(value "$1") == "$2" ]]; then echo "  ok  $1=$2"
  else echo "  !!  $1=$(value "$1") (expected $2)"; BAD=1; fi
}

step "Theme files -> $DIR"
[[ ! -d /boot/grub/themes/.git ]] || echo "  !! /boot/grub/themes is itself a git clone - GRUB_THEME can't point into it; move it away"
curl -fsSL -o "$TMP/theme.tar.gz" "$URL"
echo "$SHA256  $TMP/theme.tar.gz" | sha256sum -c --quiet
tar xzf "$TMP/theme.tar.gz" --no-same-owner -C "$TMP"
[[ -f $TMP/1920x1080/theme.txt ]] || { echo "!! no 1920x1080/theme.txt in the release tarball"; exit 1; }
if diff -rq "$TMP/1920x1080" "$DIR" >/dev/null 2>&1; then
  echo "  already installed ($VER)"
else
  if [[ -d $DIR ]]; then rm -rf "$DIR.bak"; mv "$DIR" "$DIR.bak"; echo "  kept the old theme as $DIR.bak"; fi
  mkdir -p "$(dirname "$DIR")"
  cp -r "$TMP/1920x1080" "$DIR"
  echo "  installed $VER"
fi

step "$CONF"
want GRUB_THEME "$DIR/theme.txt"
want GRUB_BACKGROUND "$DIR/background.jpg"
want GRUB_TERMINAL_OUTPUT gfxterm
want GRUB_GFXMODE 1920x1080,auto
t=$(value GRUB_TERMINAL)
[[ -z $t || $t == gfxterm ]] || { echo "  !!  GRUB_TERMINAL=$t overrides GRUB_TERMINAL_OUTPUT - comment it out"; BAD=1; }
(( BAD == 0 )) || { echo "!! $CONF is not as expected - fix it, then rerun"; exit 1; }

step "update-grub"
if ! out=$(update-grub 2>&1); then printf '%s\n' "$out"; echo "!! update-grub failed - the old grub.cfg is still in place"; exit 1; fi
printf '%s\n' "$out" | sed 's/^/  /'
[[ $out == *"Found theme: $DIR/theme.txt"* ]] || { echo "  !!  update-grub did not pick up the theme"; BAD=1; }
[[ $out == *"Found background image: $DIR/background.jpg"* ]] || { echo "  !!  update-grub did not pick up the background"; BAD=1; }

step "Checking /boot/grub/grub.cfg before you reboot"
CFG=/boot/grub/grub.cfg
grub-script-check "$CFG" && echo "  ok  grub-script-check"
grep -q '^set theme=.*/space-isolation/theme\.txt' "$CFG" && echo "  ok  set theme" || { echo "  !!  no 'set theme' line"; BAD=1; }
grep -q 'background_image .*/space-isolation/background\.jpg' "$CFG" && echo "  ok  background_image" || { echo "  !!  no background_image line"; BAD=1; }
grep -q "^menuentry '.*gnulinux-simple-" "$CFG" && echo "  ok  Debian menu entry" || { echo "  !!  no Debian menu entry - do NOT reboot, ask for help"; BAD=1; }
if (( BAD )); then echo "!! something is off (see !! above)"; exit 1; fi
echo
echo "Done - the theme shows at the next boot."
