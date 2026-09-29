#!/usr/bin/env bash
# Sarabun as the Thai fallback font (instead of TLWG Loma/Kinnari). Per-user, no sudo:
#   bash 35-thai-font.sh        (30-user.sh calls it too)
# Sarabun is not packaged in Debian; the TTFs come from Google Fonts (OFL licence).
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "!! Run this as your normal user, WITHOUT sudo."; exit 1; }
FONTDIR=~/.local/share/fonts/Sarabun
CONF=~/.config/fontconfig/conf.d/60-thai-sarabun.conf
BASE=https://raw.githubusercontent.com/google/fonts/main/ofl/sarabun
mkdir -p "$FONTDIR" "$(dirname "$CONF")"

for w in Thin ExtraLight Light Regular Medium SemiBold Bold ExtraBold; do
  for f in "Sarabun-$w.ttf" "Sarabun-${w/Regular/}Italic.ttf"; do
    [[ -s $FONTDIR/$f ]] && continue
    curl -fsSL -o "$FONTDIR/$f.part" "$BASE/$f"
    fc-scan -f '%{family}\n' "$FONTDIR/$f.part" >/dev/null || { echo "!! $f is not a font"; exit 1; }
    mv "$FONTDIR/$f.part" "$FONTDIR/$f"
  done
done
[[ -s $FONTDIR/OFL.txt ]] || curl -fsSL -o "$FONTDIR/OFL.txt" "$BASE/OFL.txt"

# Each <prefer> list goes in front of the generic name, and the TLWG rules (64-*) add theirs later,
# so Sarabun ends up before Loma/Kinnari. The Latin fonts stay in front of it (they have no Thai
# glyphs), so English text is unchanged. Monospace keeps Tlwg Mono (Sarabun is proportional).
cat >"$CONF" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- written by 35-thai-font.sh: Thai text falls back to Sarabun -->
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Noto Sans</family><family>DejaVu Sans</family><family>Sarabun</family></prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer><family>Noto Serif</family><family>DejaVu Serif</family><family>Sarabun</family></prefer>
  </alias>
</fontconfig>
EOF
fc-cache -f "$FONTDIR"

# Glyph fallback walks the sorted list (fc-match -s) until a font has the character, so report the
# first font covering Thai (U+0E01..) - plain fc-match on a named family just returns that family.
bad=0
for p in sans-serif serif Cantarell 'gg sans' Roboto; do
  lat=$(fc-match -f '%{family[0]}' "$p")
  th=$(fc-match -s -f '%{family[0]}\t%{charset}\n' "$p" | awk -F'\t' '$2 ~ /(^| )e0[01]-e3a/ {print $1; exit}')
  printf '%-11s Latin: %-12s Thai: %s\n' "$p" "$lat" "$th"
  [[ $th == Sarabun ]] || bad=1
done
(( bad == 0 )) || { echo "!! Thai does not resolve to Sarabun"; exit 1; }
echo "OK. Restart open apps (Firefox, Discord ...) to pick it up; GNOME Shell after the next login."
