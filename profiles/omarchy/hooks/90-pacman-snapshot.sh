#!/bin/bash
# Runs inside the target rootfs (emulated aarch64).
#
# Snapshots the shipped pacman configuration so the device can put it back.
# `omarchy refresh pacman` (and install/post-install/pacman.sh) force-overwrite
# /etc/pacman.conf and /etc/pacman.d/mirrorlist with Omarchy's channel
# templates, which point at x86_64-only mirrors and drop [fyde]. The escape
# upstream sanctions is a hook in ~/.config/omarchy/hooks/pre-refresh-pacman.d/,
# and this profile ships one (overlay/etc/skel/.config/omarchy/hooks/
# pre-refresh-pacman.d/restore-fydetab-repos) that copies these two files back.
#
# Taking the snapshot here rather than shipping a second copy in the overlay
# keeps overlay/etc/pacman.conf the single source of truth, and captures the
# mirrorlist as pacman-mirrorlist actually installed it.
set -euo pipefail

install -Dm644 /etc/pacman.conf          /usr/share/fydetab/pacman.conf
install -Dm644 /etc/pacman.d/mirrorlist  /usr/share/fydetab/mirrorlist
