#!/usr/bin/env python3
"""Build the "Gooey" GTK3 theme: Adwaita-dark (from the GTK3 library) recoloured with the Gooey palette.
Usage: python3 gooey-gtk3-theme.py <gtk-contained-dark.css> <output gtk.css>
m37-xfce-look.sh extracts the input with:
  gresource extract <libgtk-3.so.0> /org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css
Recolouring the whole theme (instead of a ~/.config/gtk-3.0/gtk.css on top) keeps the panel's and
the terminal's own see-through backgrounds working: a user gtk.css outranks them, a theme doesn't.
Greys are mapped by role (Adwaita-dark 3.24.38, Debian 12); colours not in the map stay as they are.
"""
import re
import sys

NAVY, RAISED, HOVER = "#0D101B", "#1F222D", "#2A2E3C"
DARK, DARKER = "#090B13", "#06080F"
HEX = {
    # backgrounds
    "#353535": NAVY,      # window background
    "#2d2d2d": NAVY,      # views (lists, text, Thunar's file area)
    "#303030": RAISED, "#323232": RAISED, "#313131": RAISED, "#2e2e2e": RAISED,  # header bars, buttons
    "#2b2b2b": RAISED, "#2a2a2a": RAISED,
    "#373737": HOVER,     # hovered buttons
    "#282828": DARK, "#262626": DARK, "#232323": DARK, "#202020": DARK, "#1e1e1e": DARK,  # sunken / backdrop
    "#1b1b1b": HOVER,     # borders (darker than the window in Adwaita; visible on navy this way)
    # text
    "#eeeeec": "#EBEEF9",
    "#919190": "#858893", "#8a8a89": "#858893", "#8e8e8d": "#858893",  # dim / insensitive text
    "#5b5b5b": "#4A4E5C",
    # accent (Adwaita blue -> Gooey blue)
    "#15539e": "#6488C4",  # selection, suggested buttons, switches
    "#1b6acb": "#6488C4",
    "#1f76e1": "#6488C4",
    "#155099": "#5A7AB2",
    "#0f3b71": "#34466B",  # unfocused selection
    "#16447c": "#34466B",
    "#092444": "#2E3F5E",
    "#030c17": DARKER,
    "#3584e4": "#97BBF7",  # links
}
RGBA = {
    (238, 238, 236): (235, 238, 249),  # text with alpha
    (38, 38, 38): (31, 34, 45),        # tooltips / OSD
    (58, 58, 57): (42, 46, 60),
}


def main(src, dst):
    css = open(src, encoding="utf-8").read()
    counts = {}

    def hex_sub(m):
        new = HEX.get(m.group(0).lower())
        if new is None:
            return m.group(0)
        counts[m.group(0).lower()] = counts.get(m.group(0).lower(), 0) + 1
        return new

    css = re.sub(r"#[0-9a-fA-F]{6}\b", hex_sub, css)

    def rgba_sub(m):
        rgb = tuple(int(x) for x in m.group(1, 2, 3))
        if rgb not in RGBA:
            return m.group(0)
        counts[str(rgb)] = counts.get(str(rgb), 0) + 1
        return "rgba(%d, %d, %d, %s)" % (*RGBA[rgb], m.group(4))

    css = re.sub(r"rgba\(\s*(\d+),\s*(\d+),\s*(\d+),\s*([0-9.]+)\s*\)", rgba_sub, css)
    # the theme's images live inside the GTK library, not next to the extracted file
    css, n_assets = re.subn(r'url\("assets/', 'url("resource:///org/gtk/libgtk/theme/Adwaita/assets/', css)
    header = "/* Gooey: Adwaita-dark recoloured by gooey-gtk3-theme.py (debian13-setup/hp-mini-311) */\n"
    open(dst, "w", encoding="utf-8").write(header + css)
    total = sum(counts.values())
    missing = sorted(set(HEX) - set(counts))
    print(f"  {total} colours replaced ({len(counts)} kinds), {n_assets} image paths fixed")
    if missing:
        print("  not found in this GTK version (fine if few): " + " ".join(missing))
    return 0 if total > 300 and n_assets > 0 else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
