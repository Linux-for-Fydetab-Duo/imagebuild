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
# sddm.service carries Alias=display-manager.service, so enabling it writes the
# same /etc/systemd/system/display-manager.service symlink the overlay ships;
# graphical.target (systemd's built-in default) pulls it in from there.
enable_unit sddm.service

# Board support (from fydetabduo-post-install)
enable_unit fydetabduo.service
enable_unit bluetooth-fydetab.service
# touchegg's daemon is enabled for parity with the GNOME profile and by the
# package's own scriptlet; its gesture client is X11-only, so it does nothing
# under Hyprland until the tablet-UX pass replaces it.
enable_unit touchegg.service
enable_unit fix-display.service

# NOT enabled here, unlike upstream's install/config/enable-services.sh:
# cups, cups-browsed, avahi-daemon, docker.socket, systemd-resolved,
# power-profiles-daemon (would fight the cpupower.service governor this profile
# enables), systemd-oomd, ufw, linux-modules-cleanup. None of them is needed to
# reach a session, and each one changes device behaviour; decide them with the
# integration pass, not by default.

# Grows the root partition to fill the medium on first boot, then disables
# itself. Correct for the live image: the image is sized to its content plus a
# small slack, so without this the user gets no free space.
enable_unit resizefs.service

# Deliberately NOT enabled: oemcleanup.service. Post-install teardown belongs
# to an installer, not to the live image -- oemcleanup runs `userdel -r -f
# arch`, which would delete the account this image logs in automatically. This
# profile ships no installer at all (v1 has no calamares), so the unit is inert
# and kept only so a later OEM flow has it to enable.
