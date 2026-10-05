#!/usr/bin/env bash
# Fingerprint for sudo, su and GNOME's password pop-ups (polkit). Optional, safe to rerun:
#   sudo bash 39-fingerprint.sh <your-username>
# The reader (Goodix 27c6:631c) is supported by Debian 13's libfprint (goodixmoc driver, match on chip).
# Ly stays PASSWORD-ONLY: a fingerprint login gives pam_gnome_keyring no password, so the login keyring
# stays locked and GNOME asks for the password again ("The login keyring did not get unlocked").
# There is no lock screen to unlock with a finger: gnome-shell only builds one when GDM is running.
# Websites can't use the reader (no Linux browser has a fingerprint platform authenticator).
set -euo pipefail
U=${1:?usage: sudo bash 39-fingerprint.sh <username>}
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
id "$U" >/dev/null
FINGER=${FINGER:-right-index-finger}   # other finger: sudo FINGER=left-index-finger bash 39-fingerprint.sh <user>
LY=/etc/pam.d/ly
BAD=0

step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }

step "Packages"
missing=()
for p in fprintd libpam-fprintd; do
  [[ $(dpkg-query -W -f='${Status}' "$p" 2>/dev/null) == *"ok installed" ]] || missing+=("$p")
done
if (( ${#missing[@]} )); then
  DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends "${missing[@]}"
else
  echo "  already installed"
fi

step "Reader"
list=$(fprintd-list "$U" 2>&1) || true
if [[ $list != *"Using device "* ]]; then
  printf '%s\n' "$list" | sed 's/^/  /'
  echo "!! no fingerprint reader found - nothing changed in PAM"; exit 1
fi
printf '%s\n' "$list" | sed -n 's/^Fingerprints for user .* on \(.*\):$/  ok  \1/p'

# Before fingerprint goes into common-auth: Ly must not use it (see the top of this file)
step "Ly login: password only ($LY)"
if [[ ! -f $LY ]]; then
  echo "  no $LY (Ly not installed) - skipped"
else
  if grep -Eq '^auth[[:space:]]+include[[:space:]]+login' "$LY"; then
    cp -a "$LY" "$LY.bak"; echo "  kept the old file as $LY.bak"
    # Same auth stack as /etc/pam.d/login + common-auth, minus pam_fprintd (10-system.sh does the same)
    awk '/^auth[ \t]+include[ \t]+login/ {
      print "# Password only (no pam_fprintd): the typed password must reach pam_gnome_keyring."
      print "# Same auth stack as /etc/pam.d/login + common-auth, minus the fingerprint line."
      print "auth       optional     pam_faildelay.so  delay=3000000"
      print "auth       requisite    pam_nologin.so"
      print "auth       [success=1 default=ignore] pam_unix.so nullok"
      print "auth       requisite    pam_deny.so"
      print "auth       required     pam_permit.so"
      print "auth       optional     pam_group.so"
      next } { print }' "$LY.bak" > "$LY.new"
    chmod 644 "$LY.new"; mv "$LY.new" "$LY"
  fi
  if awk '($1 ~ /^-?auth$/ && ($2 == "include" || $2 == "substack" || /pam_fprintd/)) || /^@include[ \t]+common-auth/ {bad=1}
          END {exit !bad}' "$LY"; then
    echo "  !!  $LY still pulls in another auth stack or pam_fprintd:"; sed -n '/auth/s/^/      /p' "$LY"; BAD=1
  elif grep -Eq '^auth[[:space:]].*pam_unix\.so' "$LY"; then
    echo "  ok  password only (pam_unix), pam_gnome_keyring gets the password"
  else
    echo "  !!  no pam_unix auth line in $LY"; BAD=1
  fi
fi
(( BAD == 0 )) || { echo "!! fix $LY first (or restore $LY.bak) - fingerprint NOT enabled"; exit 1; }

step "Enrolled fingers for $U"
list=$(fprintd-list "$U" 2>&1) || true
if [[ $list != *$'\n - #'[0-9]* ]]; then
  echo "  none yet - touch the reader repeatedly until it says enroll-completed"
  fprintd-enroll -f "$FINGER" "$U"
  echo "  now touch it once more to test:"
  fprintd-verify "$U" || { echo "!! no match - rerun to try again (fingerprint NOT enabled in PAM)"; exit 1; }
fi
fprintd-list "$U" | sed -n 's/^ - #[0-9]*: /  ok  /p'

step "PAM: fingerprint for sudo, su and polkit (common-auth)"
pam-auth-update --enable fprintd
if grep -Eq '^auth[[:space:]].*pam_fprintd\.so' /etc/pam.d/common-auth; then
  echo "  ok  $(grep -E '^auth[[:space:]].*pam_fprintd\.so' /etc/pam.d/common-auth | xargs)"
else
  echo "  !!  pam_fprintd is not in /etc/pam.d/common-auth (local edits there? see: sudo pam-auth-update)"; BAD=1
fi
(( BAD == 0 )) || exit 1

echo
echo "Done. sudo and password pop-ups now ask for a finger first (10 s, Ctrl+C or wait for the password)."
echo "Ly still wants the password, so the login keyring unlocks. Undo: sudo pam-auth-update --disable fprintd"
