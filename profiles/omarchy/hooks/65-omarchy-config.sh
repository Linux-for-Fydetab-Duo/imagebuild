#!/bin/bash
# Runs inside the target rootfs (emulated aarch64).
#
# Ports of upstream Omarchy's install-time configuration that the official
# ISO applies via omarchy-apply-system (install/config/*.sh,
# install/hardware/*.sh) and that fit build time. Each block names its
# upstream source; keep the applied content byte-equivalent to upstream so
# re-syncs stay a diff away.
set -euo pipefail

# install/config/theme-system.sh: omarchy-theme-set-browser refuses to write
# theme policies unless this directory exists, so browser theming silently
# never applies without it.
mkdir -p /etc/chromium/policies/managed
chmod a+rw /etc/chromium/policies/managed

# install/config/theme-system.sh: default Chromium to following the system
# appearance ("device") instead of its own dark scheme.
mkdir -p /usr/lib/chromium
echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' > \
  /usr/lib/chromium/initial_preferences

# install/config/ssh-command-path.sh: SSH commands (ssh host cmd) run without
# a login shell, so PAM env is the only place they inherit PATH from; without
# the mise shims there, remote commands cannot find mise-managed tools. This
# matters more here than upstream: this image ships sshd enabled.
if ! grep -qE '^PATH[[:space:]]' /etc/security/pam_env.conf; then
  cat >>/etc/security/pam_env.conf <<'EOF'

# Omarchy: give SSH commands and other non-shell logins the user-level tool paths
PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin
EOF
fi

# install/hardware/set-wireless-regdom.sh: persist the wireless regulatory
# domain implied by the image's timezone (upstream derives it the same way at
# install time). Without it the regdom stays world/00: fewer 5 GHz channels
# and reduced TX power. Users who change timezone can change the regdom the
# same way; the guard keeps an existing setting untouched.
regdom_file=/etc/conf.d/wireless-regdom
if [ -f "$regdom_file" ] && ! grep -q '^WIRELESS_REGDOM=' "$regdom_file"; then
    timezone=$(readlink -f /etc/localtime || true)
    timezone=${timezone#/usr/share/zoneinfo/}
    country="${timezone%%/*}"
    zone_tab=/usr/share/zoneinfo/zone.tab
    if [[ ! $country =~ ^[A-Z]{2}$ && -n $timezone && -f $zone_tab ]]; then
        country=$(awk -v tz="$timezone" '$3 == tz {print $1; exit}' "$zone_tab")
    fi
    if [[ $country =~ ^[A-Z]{2}$ ]]; then
        echo "WIRELESS_REGDOM=\"$country\"" >> "$regdom_file"
    else
        echo "hook 65-omarchy-config: no country for timezone '$timezone', regdom left unset" >&2
    fi
fi
