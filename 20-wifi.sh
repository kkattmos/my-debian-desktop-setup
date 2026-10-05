#!/usr/bin/env bash
# Recreate the Wi-Fi profiles from the Ubuntu install with NetworkManager.
# Passwords are asked interactively and stored root-only in
# /etc/NetworkManager/system-connections (so Wi-Fi is up before login -> SeaDrive can start at boot).
set -euo pipefail

echo "== ChulaWiFi + eduroam (WPA2-Enterprise: PEAP / MSCHAPv2) - same settings as your Ubuntu profile"
read -rp  "Chula ID (identity, e.g. 67xxxxxxxx): " CU_ID
read -rp  "Anonymous identity [anonymous]: " CU_ANON; CU_ANON=${CU_ANON:-anonymous}
read -rsp "CUNET password: " CU_PW; echo
# Chula's RADIUS servers only speak TLS 1.0/1.1. Debian's OpenSSL 3 refuses that
# ("local TLS alert: protocol version" in wpa_cli, NetworkManager keeps re-asking the password),
# so allow old TLS for these two profiles only: tls-1-0-enable + tls-1-1-enable, SECLEVEL 0.
# The two networks use different server certs (wifi.it.chula.ac.th vs it.chula.ac.th).
add_chula() { # <con-name/ssid> <identity> <anonymous identity> <domain suffix> <priority>
  sudo nmcli connection delete "$1" >/dev/null 2>&1 || true
  sudo nmcli connection add type wifi con-name "$1" ifname '*' ssid "$1" \
    wifi-sec.key-mgmt wpa-eap \
    802-1x.eap peap 802-1x.phase2-auth mschapv2 \
    802-1x.identity "$2" 802-1x.anonymous-identity "$3" \
    802-1x.password "$CU_PW" 802-1x.password-flags 0 \
    802-1x.domain-suffix-match "$4" \
    802-1x.system-ca-certs no \
    802-1x.phase1-auth-flags 0x60 802-1x.openssl-ciphers 'DEFAULT@SECLEVEL=0' \
    connection.autoconnect yes connection.autoconnect-priority "$5"
}
add_chula ChulaWiFi "$CU_ID" "$CU_ANON" wifi.it.chula.ac.th 10
add_chula eduroam "$CU_ID@eduroam.chula.ac.th" "$CU_ANON@eduroam.chula.ac.th" it.chula.ac.th 5
unset CU_PW

echo
echo "== Home Wi-Fi (WPA2-PSK). Add as many SSIDs as you like; empty SSID to finish."
echo "   Type each name exactly as Ubuntu showed it (Settings -> Wi-Fi), including double spaces."
while :; do
  read -rp "SSID (exactly, with spaces): " SSID
  [[ -z $SSID ]] && break
  read -rsp "Password for '$SSID': " PSK; echo
  sudo nmcli connection delete "$SSID" >/dev/null 2>&1 || true
  sudo nmcli connection add type wifi con-name "$SSID" ifname '*' ssid "$SSID" \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PSK" ipv4.method auto connection.autoconnect yes
  unset PSK
done

nmcli -f NAME,TYPE,AUTOCONNECT connection show
echo "Tip: prefer 5 GHz at home ->  sudo nmcli connection modify '<your 5 GHz SSID>' connection.autoconnect-priority 10"
