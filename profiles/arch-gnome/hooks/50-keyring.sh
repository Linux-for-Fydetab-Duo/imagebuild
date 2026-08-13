#!/bin/bash
# Runs inside the target rootfs (emulated aarch64).
#
# Populates the pacman keyring at build time. The previous image did this on
# first boot via a script that drove `pacman-key --edit-key` with expect to
# ultimately-trust the ALARM builder key -- a first-boot failure mode, and
# pointless anyway since the shipped pacman.conf uses SigLevel = Never.
# Doing it here means the image boots with a working keyring and no expect.
set -euo pipefail

pacman-key --init
pacman-key --populate archlinux archlinuxarm

# --populate only trusts keys whose keyring package is installed. fyde-keyring
# ships the repo key; if it is present, trust it too.
if [ -f /usr/share/pacman/keyrings/fyde.gpg ]; then
    pacman-key --populate fyde
fi
