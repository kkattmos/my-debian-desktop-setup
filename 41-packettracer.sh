#!/usr/bin/env bash
# Install Cisco Packet Tracer 9 from the Ubuntu .deb (the same file you used on Ubuntu:
# CiscoPacketTracer_901_Ubuntu_64bit.deb, from netacad.com -> Resources -> Packet Tracer).
# On Debian 13 its 'libfuse2' dependency is satisfied by libfuse2t64.
set -euo pipefail
DEB=${1:?usage: 41-packettracer.sh <CiscoPacketTracer_*_Ubuntu_64bit.deb>}
sudo apt-get install -y "$(realpath "$DEB")"   # shows Cisco's EULA dialog
echo "Start it from the app grid ('Cisco Packet Tracer'); first launch asks for a NetAcad login."
