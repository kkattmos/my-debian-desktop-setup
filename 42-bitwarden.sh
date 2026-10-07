#!/usr/bin/env bash
# Bitwarden desktop (official .deb, sha256-pinned) + the polkit policy its "Unlock with system authentication"
# needs. Optional, safe to rerun:
#   sudo bash 42-bitwarden.sh
# With 39-fingerprint.sh done, the unlock prompt takes a finger (polkit -> PAM common-auth -> pam_fprintd), and
# the Firefox extension can unlock through the desktop app. Logging in and importing passwords is done by hand.
# - .deb, not snap/flatpak: the snap can't reach polkit, and neither sandbox can install the policy itself.
#   The .deb updates itself (electron-updater from artifacts.bitwarden.com, installs via pkexec), so the pin
#   below only matters for the first install; a newer installed version is left alone.
# - The app's own policy setup button runs `chcon` (SELinux) after writing the file; Debian has no SELinux, so it
#   reports "Failed to set up polkit policy". This script installs the same file instead
#   (dotfiles/polkit/com.bitwarden.Bitwarden.policy, copied verbatim from the app's code).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
KIT="$(cd "$(dirname "$0")" && pwd)"
VER=2026.9.1
URL=https://github.com/bitwarden/clients/releases/download/desktop-v$VER/Bitwarden-$VER-amd64.deb
SHA256=da5e0177da10805152268ee9d29cbaf278c4ea10650b0ebcd03c5697537fab82
ACTION=com.bitwarden.Bitwarden.unlock
POLICY_SRC=$KIT/dotfiles/polkit/com.bitwarden.Bitwarden.policy
POLICY=/usr/share/polkit-1/actions/com.bitwarden.Bitwarden.policy
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BAD=0

step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }

step "Bitwarden desktop"
have=$(dpkg-query -W -f='${Status} ${Version}' bitwarden 2>/dev/null || true)
if [[ $have == "install ok installed "* ]] && dpkg --compare-versions "${have##* }" ge "$VER"; then
  echo "  already installed: ${have##* } (it updates itself)"
else
  curl -fL --progress-bar -o "$TMP/bitwarden.deb" "$URL"
  echo "$SHA256  $TMP/bitwarden.deb" | sha256sum -c --quiet
  chmod 644 "$TMP/bitwarden.deb"; chmod 755 "$TMP"   # apt's _apt user must be able to read it
  DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends "$TMP/bitwarden.deb"
fi
v=$(dpkg-query -W -f='${Version}' bitwarden 2>/dev/null || true)
[[ -n $v && -x /opt/Bitwarden/bitwarden ]] && echo "  ok  bitwarden $v" || { echo "  !!  bitwarden is not installed"; BAD=1; }

step "polkit policy ($ACTION)"
if cmp -s "$POLICY_SRC" "$POLICY"; then
  echo "  already installed"
else
  if [[ -f $POLICY ]]; then cp -a "$POLICY" "$POLICY.bak"; echo "  kept the old file as $POLICY.bak"; fi
  install -m 644 -o root -g root "$POLICY_SRC" "$POLICY"
fi
# polkitd notices new action files by itself; give it a moment
for _ in 1 2 3 4 5; do
  out=$(pkaction --verbose --action-id "$ACTION" 2>/dev/null || true)
  [[ $out == *"implicit active:"*auth_self* ]] && break
  sleep 1
done
if [[ $out == *"implicit active:"*auth_self* ]]; then
  echo "  ok  polkit knows $ACTION (active session: auth_self)"
else
  echo "  !!  polkit does not list $ACTION - try: sudo systemctl restart polkit"; BAD=1
fi

step "What the unlock prompt will ask for"
if grep -Eq '^auth[[:space:]].*pam_fprintd\.so' /etc/pam.d/common-auth; then
  echo "  ok  fingerprint first, password as fallback (pam_fprintd in common-auth)"
else
  echo "  password only - run sudo bash 39-fingerprint.sh <user> for the fingerprint"
fi
(( BAD == 0 )) || exit 1

cat <<'EOF'

Done. As your user, in this order:
  1. Open Bitwarden and log in with your master password (once; it can't start from a fingerprint).
  2. File -> Settings -> Security: tick "Unlock with system authentication".
     Same page, App settings: tick "Allow browser integration" (writes ~/.mozilla/native-messaging-hosts/).
  3. Lock the vault (menu -> Lock) and unlock it: GNOME's dialog asks for your finger.
  4. Firefox: install the Bitwarden extension from addons.mozilla.org, log in, then its Settings ->
     Account security -> "Unlock with biometrics". Keep the desktop app running; it does the unlock.
Test the polkit + fingerprint part alone (no Bitwarden needed):
  pkcheck --action-id com.bitwarden.Bitwarden.unlock --process $$ --allow-user-interaction && echo ok
EOF
