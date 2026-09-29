#!/usr/bin/env bash
# Install STM32CubeIDE 1.9.1 from ST's generic Linux installer.
# Download it yourself (needs a free myST login): st.com -> STM32CubeIDE -> "Get Software"
#   -> select version 1.9.1 -> "STM32CubeIDE-Lnx" (generic Linux installer, *.sh.zip).
# Usage: bash 40-stm32cubeide.sh ~/Downloads/en.st-stm32cubeide_1.9.1_*_amd64.sh.zip
set -euo pipefail
SRC=${1:?usage: 40-stm32cubeide.sh <st-stm32cubeide_1.9.1_...amd64.sh(.zip)>}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

case "$SRC" in
  *.zip) unzip -q "$SRC" -d "$TMP"; INST=$(find "$TMP" -name 'st-stm32cubeide_*amd64.sh' | head -1) ;;
  *.sh)  INST=$SRC ;;
esac
[[ -n ${INST:-} && -f $INST ]] || { echo "installer .sh not found"; exit 1; }

# libncurses.so.5 / libtinfo.so.5 are needed by the bundled arm-none-eabi-gdb (installed by 10-system.sh)
ldconfig -p | grep -q 'libncurses.so.5' || { echo "libncurses5 missing - run 10-system.sh first"; exit 1; }

echo "The ST installer is interactive: accept the licenses, keep /opt/st/stm32cubeide_1.9.1,"
echo "and answer YES to the ST-LINK / SEGGER J-Link udev rules."
sudo sh "$INST"

DIR=$(ls -d /opt/st/stm32cubeide_1.9.1* | head -1)
# Eclipse 2021-12 is unreliable on native Wayland -> run it through Xwayland (same trick as on Ubuntu)
sudo tee "$DIR/stm32cubeide_wayland" >/dev/null <<'EOF'
#!/bin/bash
basedir=$(dirname "$BASH_SOURCE")
export GDK_BACKEND=x11
"$basedir"/stm32cubeide "$@"
EOF
sudo chmod +x "$DIR/stm32cubeide_wayland"
for d in /usr/share/applications/st-stm32cubeide*1.9.1*.desktop ~/.local/share/applications/st-stm32cubeide*1.9.1*.desktop; do
  [[ -f $d ]] && sudo sed -i -E "s|^Exec=.*/stm32cubeide( .*)?$|Exec=$DIR/stm32cubeide_wayland %F|" "$d"
done
sudo udevadm control --reload-rules && sudo udevadm trigger
echo "Installed in $DIR ($(du -sh "$DIR" | cut -f1)). Replug the ST-LINK before the first debug session."
