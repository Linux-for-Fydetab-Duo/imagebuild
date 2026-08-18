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

mask_unit() {
    if [ -f "/usr/lib/systemd/system/$1" ] || [ -f "/etc/systemd/system/$1" ]; then
        systemctl mask "$1"
    else
        echo "hook 70-services: unit $1 not present, not masking" >&2
    fi
}

# One mechanism per unit, never both. The overlay's
# etc/systemd/system/multi-user.target.wants/ symlinks own cpupower,
# iio-sensor-proxy, resizefs, sshd and systemd-timesyncd, and its
# display-manager.service symlink owns sddm; every other unit is enabled here,
# because systemctl is the only mechanism that also follows [Install] Also= and
# Alias= (NetworkManager pulls in its dispatcher, avahi/cups/oomd/resolved pull
# in their sockets) and WantedBy= targets other than multi-user.target
# (bluetooth.target, sysinit.target, sockets.target, graphical.target).

# Enabled by the overlay, not here:
#   resizefs.service   grows the root partition to fill the medium on first
#                      boot, then disables itself. Correct for the live image:
#                      the image is sized to its content plus a small slack, so
#                      without it the user gets no free space.
#   sddm.service       its whole [Install] is Alias=display-manager.service, and
#                      the overlay ships that symlink; graphical.target
#                      (systemd's built-in default) has Wants= on it.
#   iio-sensor-proxy   has no [Install] section at all -- systemctl cannot
#                      enable it, a .wants symlink is the only way to force it.

# Base system
enable_unit NetworkManager.service
enable_unit bluetooth.service

# Don't let network-online.target (pulled in by cups-browsed) hold up
# graphical.target waiting for DHCP/Wi-Fi association; nothing in the session
# needs to block on the network. Upstream does the same in
# install/config/enable-services.sh:14 and install/hardware/network.sh:17-18.
# Has to follow the NetworkManager enable above, whose [Install] carries
# Also=NetworkManager-wait-online.service.
mask_unit NetworkManager-wait-online.service
mask_unit systemd-networkd-wait-online.service

# Upstream's install/config/enable-services.sh set: printing and its discovery
# (avahi-daemon is also what nss-mdns resolves through), DNS via resolved (the
# overlay ships the matching /etc/resolv.conf stub symlink -- resolved does not
# create it), one runaway app scope killed instead of the whole session, and
# docker's socket rather than docker.service so the daemon starts on first use.
enable_unit systemd-resolved.service
enable_unit systemd-oomd.service
enable_unit avahi-daemon.service
enable_unit cups.service
enable_unit cups-browsed.service
enable_unit docker.socket
# Keeps the running kernel's modules loadable after a pacman kernel upgrade.
enable_unit linux-modules-cleanup.service
# Coexists with the cpupower.service the overlay enables: on RK3588 ppd finds no
# cpufreq driver it recognises and loads its placeholder driver, which never
# writes to cpufreq. Verified on device 2026-08-18.
enable_unit power-profiles-daemon.service

# Board support (from fydetabduo-post-install)
enable_unit fydetabduo.service
enable_unit bluetooth-fydetab.service
# touchegg's daemon is enabled for parity with the GNOME profile and by the
# package's own scriptlet; its gesture client is X11-only, so it does nothing
# under Hyprland until the tablet-UX pass replaces it.
enable_unit touchegg.service
enable_unit fix-display.service

# Firewall. The rules live in the overlay (etc/ufw/user.rules, user6.rules)
# rather than being produced by `ufw` calls here the way upstream's
# install/config/firewall.sh does them: ufw shells out to /usr/bin/iptables, and
# an emulated aarch64 iptables-nft cannot open its netlink socket under
# qemu-user ("Failed to initialize nft: Protocol not supported"), so every ufw
# invocation in this chroot dies with "Couldn't determine iptables version"
# before writing anything. The overlay files are the byte-for-byte output of
# ufw 0.36.2-7 -- an any-arch package, so the identical version generated them
# natively -- for upstream's rule set plus the `limit 22/tcp` rule from
# bin/omarchy-setup-security-sshd, which this image needs because it ships sshd
# enabled and the default-deny policy would otherwise cut SSH off.
#
# Deliberately NOT ported: the ufw-docker after.rules block and the two
# allow-docker-dns rules. ufw-docker's installer preflights against a live
# firewall, which no chroot has, and the DNS rules only matter once containers
# run.
#
# Needs linux-fydetab >= 6.12.43-18: older kernels lack nftables and, worse,
# carry CONFIG_STATIC_USERMODEHELPER pointing at a binary Arch does not ship,
# which silently breaks all kernel module autoloading -- ufw-init then dies
# fail-CLOSED (DROP policies set, allow chains never installed) and the device
# drops off the network. Verified on device 2026-08-18: with the pkgrel-18
# kernel a cold boot brings ufw up clean with every match autoloaded.
if [ -f /etc/ufw/ufw.conf ]; then
    sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf
    grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf || {
        echo "hook 70-services: /etc/ufw/ufw.conf has no ENABLED= line" >&2
        exit 1
    }
fi
enable_unit ufw.service

# Deliberately NOT enabled: oemcleanup.service. Post-install teardown belongs
# to an installer, not to the live image -- oemcleanup runs `userdel -r -f
# omarchy`, which would delete the account this image logs in automatically.
# This profile ships no installer at all (v1 has no calamares), so the unit is
# inert and kept only so a later OEM flow has it to enable.
