# Omarchy feature gaps beyond packages/btrfs/UEFI

2026-08-18. Audit of everything else the official Omarchy install
configures that our image does not, ordered by importance x feasibility.
Sources: omarchy @1c1116b6, omarchy-iso @0c133383, omarchy-pkgs, and the
built rootfs (work/rootfs) -- every "verified" below was checked against
the rootfs, not inferred. Companions: docs/omarchy-pkgs-coverage.md
(packages/menus), the btrfs and UEFI notes in omarchy-profile-plan.md.

Status: recorded as deferred work; nothing here blocks the image.

## Tier 1 -- FIXED 2026-08-18 (v5 image; verified in built rootfs)

1. No swap at all: `zram-generator` is not installed (verified), while
   omarchy-settings ships its zram config AND our live sysctl carries
   vm.swappiness=150 / page-cluster=0 -- tuning written for zram, applied
   with no swap behind it. Fix: one packages.list line; the config is
   already in place. (omarchy-other.packages:48)
2. Browser theming is silently dead: /etc/chromium/policies/managed does
   not exist (verified), and omarchy-theme-set-browser returns early
   when it's absent -- every theme switch skips the browser. Also missing:
   /usr/lib/chromium/initial_preferences (color_scheme=follow-system).
   Fix: two overlay files. (install/config/theme-system.sh:10-16)

## Tier 2 -- FIXED 2026-08-18 (v5 image; verified in built rootfs)

Fixes: hooks/65-omarchy-config.sh (chromium theming files, pam_env PATH,
regdom GB from the image timezone), packages.list (zram-generator --
kernel has ZRAM=m with the zstd backend, and module autoload works since
the pkgrel-17 usermodehelper fix -- and tailscale), overlay (SSH
keepalive drop-in, locale en_US.UTF-8, hostname omarchy, SDDM
RememberLastUser/Session). One sub-item deliberately skipped:
/var/lib/sddm/state.conf seeding needs the sddm user at build time,
blocked by the /etc/passwd overlay override (Tier 3 item 8) --
omarchy-provision-owner writes it at first boot instead.

3. Wireless regulatory domain never set (world/00): fewer 5 GHz channels,
   lower TX power. Upstream derives it from timezone.
   (install/hardware/set-wireless-regdom.sh)
4. pam_env PATH (mise shims) missing -- `ssh device <cmd>` can't find
   mise-managed tools; more relevant for us than upstream since we ship
   sshd enabled. (install/config/ssh-command-path.sh)
5. `tailscale` not preinstalled -- the official ISO installs it into every
   target; our image ships its (inert) receive unit. In ALARM extra.
6. SSH keepalive drop-in missing. (install/config/ssh-keepalive.sh)
7. Locale C.UTF-8 vs upstream en_US.UTF-8; hostname `archlinux` vs
   `omarchy`; SDDM RememberLastUser/state.conf not seeded. Cosmetic
   identity polish, all trivial.

## Tier 3 -- real work, decide when needed

8. CLOSED by first-boot provisioning (storage-stack-plan Phase 2): there
   is no baked user any more, and the overlay stages
   /var/lib/omarchy/provisioning/groups the way `omarchy apply system
   --defer-provisioning` records it, so omarchy-provision-owner's
   `useradd -G` grants `docker` and `input` (plus the device set) to the
   owner it creates. Was: the `omarchy` user was in neither group --
   our overlay replaces /etc/group wholesale, and systemd-sysusers
   recreates the GROUPS at boot but never a MEMBERSHIP -- so docker
   needed sudo (lazydocker, install-docker-dbs broken) and /dev/input
   was unreadable (voxtype push-to-talk, controllers).
9. User provisioning is network-fragile: install/user/all.sh runs under
   bash -eE, and mise's `node@latest` network step aborting kills the
   later steps (app refresh, default browser, mailto handler, keyring
   seed). Since Phase 2 it runs twice over: omarchy-provision-owner
   calls omarchy-provision-user --force --first-install on tty1 (failure
   is non-fatal, the form prints a retry hint), and the hyprland
   autostart's omarchy-provision-first-run retries it at first login.
   Upstream runs all of it ISO-side against an offline mirror. Fix
   direction: run omarchy-provision-user --first-install in a build hook
   under emulation with the network steps stubbed.
   (omarchy-provision-user:108)
10. Plymouth splash never runs: package + theme shipped, but our
    mkinitcpio HOOKS lack `plymouth` and boot.cmd lacks `splash`
    (verified). Whether plymouthd renders this early on the VOP2/DSI
    pipeline is untested -- branding-only cost either way.
11. ufw-docker + docker-DNS rules (deliberate drop, documented in
    hooks/70-services.sh): containers get no host DNS and no ufw-docker
    protection. Revisit when container workloads matter.

## Tier 4 -- polish

12. faillock unlock_time 600s vs upstream 120s (deny=10 IS replicated);
    pam_faillock authsucc missing from sddm-autologin.
13. CLOSED with Phase 2: pam_gnome_keyring is now stripped from
    /etc/pam.d/sddm at build (hooks/65-omarchy-config.sh, ported from
    upstream's install/login/sddm.sh) — required once Phase 2 put a
    real password login in front of the desktop, which would otherwise
    create an encrypted login keyring fighting the passwordless
    Default_keyring install/user/default-keyring.sh seeds.
14. powerprofilesctl shebang not pinned to /bin/python3 (breaks only
    after a mise-installed python shadows it).
15. hid_apple fnmode=2 modprobe conf (Apple-layout BT keyboards).
16. updatedb not run at build -- locate is empty until the first timer.

## Untested-risk (needs on-device testing, not config work)

- Screen recording: gpu-screen-recorder has no VAAPI driver on RK3588
  (panfrost exposes no video engine); the CPU-encode fallback is the
  only path and is unproven. Highest-risk feature area.
- Screencast portal (xdg-desktop-portal-hyprland): DMA-BUF/modifier
  behavior on panthor unverified.
- hyprsunset nightlight: needs DRM CTM on the DSI pipeline; unverified.
- Moonlight streaming: no HW video decode; likely unusable at 1080p60.
- mpv/Chromium video: software decode -- matches upstream's own config
  (no VAAPI flags shipped), so not a regression, just slower here.

## Informational (checked, not gaps)

- Power profiles: chain degrades cleanly to `balanced` on the RK3588
  placeholder driver -- no errors, switching is cosmetic (verified in
  omarchy-powerprofiles-set logic).
- LUKS: official Omarchy is passphrase-LUKS2-by-default and nothing
  more (no TPM/FIDO2/recovery-key machinery to lose). Upstream grants
  SDDM autologin only BECAUSE the LUKS prompt is the auth boundary.
  Since Phase 2 we take upstream's unencrypted posture instead:
  omarchy-provision-owner autologs the owner in for the boot it just
  authenticated them on, then its self-removing
  omarchy-provision-autologin-once.service drops the drop-in, so every
  later boot goes through the SDDM greeter. What is still missing is
  the encryption itself (storage-stack-plan Phase 3).
- Verified faithful: omarchy PKGBUILD deps (limine/snapper-only diff),
  the 147-entry base package list (documented drops only), os-release
  branding, service enable set, ufw base rules, omarchy-settings /etc
  drop-ins, resolv.conf stub, faillock deny=10, skel dotfiles.
