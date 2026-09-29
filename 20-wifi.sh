#!/usr/bin/env bash
# Recreate the Wi-Fi profiles from the Ubuntu install with NetworkManager.
# Passwords are asked interactively and stored root-only in
# /etc/NetworkManager/system-connections (so Wi-Fi is up before login -> SeaDrive can start at boot).
set -euo pipefail

echo "== ChulaWiFi (WPA2-Enterprise: PEAP / MSCHAPv2) - same settings as your Ubuntu profile"
read -rp  "Chula ID (identity, e.g. 67xxxxxxxx): " CU_ID
read -rp  "Anonymous identity [anonymous]: " CU_ANON; CU_ANON=${CU_ANON:-anonymous}
read -rsp "CUNET password: " CU_PW; echo
sudo nmcli connection delete ChulaWiFi >/dev/null 2>&1 || true
sudo nmcli connection add type wifi con-name ChulaWiFi ifname '*' ssid ChulaWiFi \
  wifi-sec.key-mgmt wpa-eap \
  802-1x.eap peap 802-1x.phase2-auth mschapv2 \
  802-1x.identity "$CU_ID" 802-1x.anonymous-identity "$CU_ANON" \
  802-1x.password "$CU_PW" 802-1x.password-flags 0 \
  802-1x.domain-suffix-match wifi.it.chula.ac.th \
  802-1x.system-ca-certs no \
  connection.autoconnect yes
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
