#!/bin/bash
# Runs inside the target rootfs (emulated aarch64).
# Build-time ports of upstream's install-time config; each block names its
# upstream source, keep the content byte-equivalent for easy re-syncs.
set -euo pipefail

# install/config/theme-system.sh: omarchy-theme-set-browser skips browsers
# when this directory is missing.
mkdir -p /etc/chromium/policies/managed
chmod a+rw /etc/chromium/policies/managed

# install/config/theme-system.sh: Chromium follows the system appearance.
mkdir -p /usr/lib/chromium
echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' > \
  /usr/lib/chromium/initial_preferences

# install/config/ssh-command-path.sh: non-shell logins (ssh host cmd) get
# PATH only from PAM env, so mise tools need the shims listed here.
if ! grep -qE '^PATH[[:space:]]' /etc/security/pam_env.conf; then
  cat >>/etc/security/pam_env.conf <<'EOF'

# Omarchy: give SSH commands and other non-shell logins the user-level tool paths
PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin
EOF
fi

# install/login/sddm.sh: password-based SDDM logins must not create an
# encrypted login keyring that conflicts with Omarchy's passwordless default
# keyring.
if [[ -f /etc/pam.d/sddm ]]; then
  sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
  sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
fi

# install/hardware/set-wireless-regdom.sh: the world regdom restricts 5 GHz
# channels and TX power; derive the country from the timezone as upstream
# does, never overwriting an existing setting.
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
