#!/bin/bash
# Runs inside the target rootfs (emulated aarch64).
#
# Enables units explicitly rather than relying on package install scriptlets.
# fydetabduo-post-install's .install runs `systemctl enable --now`, and --now is
# meaningless in a chroot with no running systemd; being explicit here makes the
# enabled set reviewable and independent of scriptlet behaviour under emulation.
set -euo pipefail

enable_unit() {
    if [ -f "/usr/lib/systemd/system/$1" ] || [ -f "/etc/systemd/system/$1" ]; then
        systemctl enable "$1"
    else
        echo "hook 70-services: unit $1 not present, skipping" >&2
    fi
}

# Base system
enable_unit NetworkManager.service
enable_unit bluetooth.service
enable_unit gdm.service

# Board support (from fydetabduo-post-install)
enable_unit fydetabduo.service
enable_unit bluetooth-fydetab.service
enable_unit touchegg.service
enable_unit fix-display.service

# Grows the root partition to fill the medium on first boot, then disables
# itself. Correct for the live image: the image is sized to its content plus a
# small slack, so without this the user gets no free space.
enable_unit resizefs.service

# Deliberately NOT enabled: oemcleanup.service and remove-calamares.service.
# Post-install teardown belongs to the installer, not to the live image --
# oemcleanup runs `userdel -r -f arch`, which would delete the live session's
# own user on first boot, and the autostarted installer runs as that user.
#
# Calamares already handles this: calamares/scripts/post_install.py writes and
# enables remove-live-user.service and its own remove-calamares.service on the
# installed system. That makes the overlay's two units dead code -- its
# remove-calamares even removes a package name that does not exist
# ('calamares-conf' rather than 'calamares-settings-fydetab'). Left in the
# overlay as-is; removing them is a separate decision.
