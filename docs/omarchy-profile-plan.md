# Omarchy profile for the Fydetab Duo — port plan

Status: draft, 2026-08-17. **Phase 0 PASSED** — Hyprland 0.56.1 (ALARM
build) drives the panel on panthor: aquamarine DRM backend on
/dev/dri/card0, GBM allocator + EGL/GLES renderer up, DSI-1 at
1600x2560@60, alacritty tiling verified by grim screenshot. The panel
is PORTRAIT-NATIVE (1600x2560); the DRM connector carries
`panel orientation = Right Side Up` (prop 219, value 3), which mutter
honors but Hyprland/aquamarine ignores (uncompensated content appears
rotated 90° left; upstream-report candidate). CONFIRMED on device: the
profile ships `monitor = DSI-1, preferred, auto, 1, transform, 3`.
Session-launch caveat for headless testing: a logind PAM session on a
spare VT wedged/timed out repeatedly; the seatd backend
(LIBSEAT_BACKEND=seatd) worked first try. Irrelevant for the real image
(SDDM owns the seat), but useful for bench tests.
Investigation: this session, against omarchy 4.0.0.alpha
(basecamp/omarchy @ 1c1116b6) and the Arch Linux ARM aarch64 repos.

## Goal

Ship an Omarchy-flavoured image for the Fydetab Duo out of this pipeline:
Omarchy's Hyprland desktop, config layer, and first-party tools on top of
our existing boot chain (U-Boot + boot.scr), our 6.12 kernel, and the
fyde package repo. We port the *desktop*, not Omarchy's installer or
distribution infrastructure.

## Why this split

Omarchy 4.0 is package-backed and ISO-installed; all three infrastructure
pillars are x86_64-only and get bypassed here:

- `mirror.omarchy.org` mirrors upstream Arch (no aarch64 tree) → we use
  Arch Linux ARM mirrors, as the current arch-gnome profile does.
- `pkgs.omarchy.org/$arch` publishes x86_64 only (aarch64 returns 404)
  → we build the needed packages ourselves and host them in [fyde].
- `omarchy-iso` builds an x86 UEFI installer ISO → irrelevant; our
  images are flashed, not installed. Their UEFI/Limine/LUKS/Btrfs/snapper
  stack is dropped wholesale (we boot U-Boot into an ext4 rootfs).

Upstream has quietly prepared for ARM: the PKGBUILDs in
omacom-io/omarchy-pkgs (public, 114 recipes) already declare
`arch=('x86_64' 'aarch64')` with `source_aarch64` where needed
(aether, mise-bin, herdr, ttfx, omacalc, walker, elephant, localsend,
quickshell-git, ...). They prepared the recipes but do not build them —
that gap is exactly what our emulated/cross pkg pipeline covers.

## Key facts from the investigation

- Base manifest (`install/omarchy-base.packages`): 147 packages,
  **120 already available** on ALARM aarch64 (provides-aware check).
- Desktop core all present at current versions: hyprland 0.56.1,
  quickshell 0.3.0, hyprlock/hypridle, xdg-desktop-portal-hyprland,
  alacritty, chromium 151, mesa 26.1.7 + vulkan-panfrost.
- Omarchy 4 configures Hyprland through Lua executed *inside* the
  compositor (session: SDDM → `uwsm start ... Hyprland`,
  `default/wayland-sessions/omarchy.desktop`). ALARM's hyprland links
  `lua`, so the whole config layer should run unmodified on aarch64.
- The `omarchy` meta-package hard-depends on limine,
  limine-mkinitcpio-hook, limine-snapper-sync, snapper — our rebuild
  drops these four deps (bootloader/Btrfs coupling lives in the package
  graph, not just the installer).
- `install/post-install/pacman.sh` and `omarchy-refresh-pacman`
  force-overwrite pacman.conf; the sanctioned escape is a hook in
  `pre-refresh-pacman.d/` — we ship one that restores ALARM + [fyde].
- 27 base packages missing from ALARM, classified:
  - ~13 first-party, aarch64-ready PKGBUILDs → build in our pipeline:
    aether cliamp herdr omacalc omacut omawrite omarchy-nvim tensaku
    tobi-try ttfx quickshell-git ttf-ia-writer
    ttf-jetbrains-mono-nerd-basic
  - ~7 with recipes in omarchy-pkgs anyway: yay tzupdate ufw-docker
    xdg-terminal-exec yaru-icon-theme asdcontrol
    hyprland-preview-share-picker
  - mise, localsend: aarch64 recipes exist (mise-bin has arm64 source)
  - obsidian: Electron, arm64 upstream exists; low priority
  - obs-studio: heavy; drop from first image
  - pinta + dotnet-runtime: no dotnet on ALARM; drop
  - qemu-user-static-binfmt: build-host concern, not needed on target
- `omarchy-other.packages`: the 27 missing are all x86 hardware
  enablement (Intel/NVIDIA/T2/lib32/vendor kernels) — excluded by
  design; we ship linux-fydetab instead.
- Their patched `omarchy-chromium-bin` is replaced by ALARM's stock
  chromium.
- Optional x86-blob installers (1password, cursor-bin, spotify, steam,
  GeForce NOW, Battle.net, windows-vm, voxtype model, ...) are left in
  place; they fail or no-op gracefully on ARM and are not in the image.
- License: MIT — redistribution fine; keep branding clearly derivative
  (e.g. "Omarchy for Fydetab Duo, unofficial").

## Phases

Phase 0 — Hyprland-on-panthor smoke test — DONE 2026-08-17, PASSED
  hyprland/alacritty/grim from ALARM on the current GNOME image; GDM
  stopped; Hyprland run as user wei via systemd-run with seatd
  (LIBSEAT_BACKEND=seatd, after the logind-PAM route wedged); DSI-1
  1600x2560@60 with working GLES render path confirmed by hyprctl
  monitors + grim screenshot. GDM restored afterwards; test packages
  left installed on the bench device.

Phase 1 — first-party package layer — DONE 2026-08-17: all 23
  vendored packages build green into repo/fyde (three build fixes,
  recorded in pkgbuilds/OMARCHY-VENDOR.md and pkg/build-pkg.sh).
  Original scope:
  Vendor the ~20 needed PKGBUILDs from omacom-io/omarchy-pkgs into
  pkgbuilds/ (or a pkgbuilds/omarchy/ subtree), register in
  pkg/BUILDMODES (Rust/Go/C++ → emulated; fonts/configs → noarch),
  build into repo/fyde. Rebuild `omarchy` meta without the
  limine/snapper deps; `omarchy-settings` as-is (any-arch config).
  Verify: pacman -S omarchy succeeds in an aarch64 container against
  [fyde] + ALARM.

Phase 2 — profiles/omarchy in this repo — DONE 2026-08-18: first
  image (930 packages, zero GNOME) booted on device on the first try.
  SDDM autologin → Omarchy Hyprland session as the default user
  (renamed arch → omarchy on 2026-08-18); the Lua config
  layer engages ("[cfg] Using lua config"), quickshell runs Omarchy's
  shell, panel upright at transform 3 / scale 2. Verified over SSH +
  screenshot. Original scope:
  Copy arch-gnome profile as the base: same boot/, firmware/,
  image.conf, kernel. New packages.list = omarchy base manifest minus
  x86 leftovers plus our device set (linux-fydetab, ap6275p-firmware,
  fydetabduo-post-install, mali firmware fallback). Overlay:
  pacman.conf (ALARM mirrors + [fyde] first, no multilib, no [omarchy]),
  pre-refresh-pacman.d hook, SDDM enabled instead of GDM.
  Verify: image boots to SDDM → Omarchy Hyprland session on device.

Phase 3 — integration pass
  DONE 2026-08-18: committed (9698f08 + kernel e06d8f3), built into the
  v4 image and published to /dist. Kernel + ufw cold-boot verified on
  device (pkgrel-18 on the v1-era rootfs: ufw.service active at boot,
  every match autoloaded, zero failed units, SSH survives the limit
  rule); the services below were verified live on device during the
  phase; a full v4 flash-boot has not happened yet. CI builds the same
  image from the prod-omarchy-v0.1.0 tag.
  The implemented set:
  - services: hooks/70-services.sh enables upstream's
    install/config/enable-services.sh set on top of what it already had
    — systemd-resolved, systemd-oomd, avahi-daemon, cups, cups-browsed,
    docker.socket (the socket, so dockerd starts on first use),
    linux-modules-cleanup, power-profiles-daemon — and masks
    NetworkManager-wait-online and systemd-networkd-wait-online so
    network-online.target cannot hold graphical.target behind DHCP.
    cpupower stays enabled: ppd loads its placeholder driver on RK3588
    and never writes to cpufreq, so the two coexist (verified on
    device). Enablement is now one mechanism per unit — systemctl in
    the hook for anything with Also=/Alias= or a non-multi-user
    WantedBy=, an overlay .wants symlink for the rest — never both.
  - firewall: ufw enabled (ENABLED=yes + ufw.service) with upstream's
    rules baked into overlay/etc/ufw/{user,user6}.rules: default deny
    incoming / allow outgoing, 53317 udp+tcp for LocalSend, and
    `limit 22/tcp comment "omarchy-sshd"` because this image ships sshd
    enabled. The rules are files rather than `ufw` calls in the hook:
    an emulated aarch64 iptables cannot open its netlink socket under
    qemu-user, so upstream's chroot-safe recipe is not chroot-safe
    here. ufw-docker's after.rules shim and the two allow-docker-dns
    rules are deliberately skipped. See the OPEN item below — the
    shipped kernel cannot execute these rules at all.
  - lock screen: overlay/etc/pam.d/omarchy-lock-password, the file
    upstream writes from bin/omarchy-apply-lock at ISO time. Without it
    the quickshell lock screen refuses to lock (verified on device).
  - DNS: overlay/etc/resolv.conf is now the
    ../run/systemd/resolve/stub-resolv.conf symlink systemd-resolved
    expects; upstream's ISO creates it and no package does.
  Still open in this phase: suspend/resume behaviour under Hyprland
  (our vop2 fix is compositor-independent, but hypridle/hyprlock
  replace GNOME's path); wifi/BT; audio (pipewire); brightness/rotation
  basics; omarchy-update flow pointed away from omarchy.org repos (pin
  via the pre-refresh hook + [fyde]).

Phase 4 — tablet UX (open-ended)
  Omarchy is keyboard-first. Touch gestures, screen rotation
  (iio-sensor-proxy → Hyprland has no native handler; needs a helper),
  on-screen keyboard (their voxtype dictation depends on a model
  download; OSK story TBD — candidates: wvkbd, squeekboard). This
  phase decides whether the profile is a keyboard-dock companion or a
  full tablet experience.

Phase 5 — CI + release
  The existing workflow builds whatever profile it is told; add the
  profile to the matrix or a second dispatch input, publish images as
  prerelease stag tags until the UX pass settles.

## Risks / open questions

- Phase 0 unproven: wlroots/aquamarine on panthor is the single
  make-or-break item. (GNOME/mutter working proves the GPU, not the
  compositor path.)
- quickshell: ALARM ships 0.3.0 release; upstream pins a -git commit.
  If their shell QML needs git features, build quickshell-git
  (aarch64-ready recipe).
- Hyprland version drift: Omarchy stable snapshots Arch x86 versions;
  ALARM may lag or lead. Config-layer Lua API is owned by the omarchy
  package, so keep the pair (omarchy pkg ↔ hyprland version) coherent
  when bumping.
- Dropped features to document for users: snapshots/factory reset
  (snapper/Btrfs), obs-studio, pinta, all x86 proprietary installers,
  gaming stack.
- Tablet UX effort is the real unknown; everything before it is
  mostly mechanical.

### OPEN, found during Phase 3 verification (2026-08-18)

- quickshell's lock screen ignores logind's Unlock signal, so there is
  no remote or admin unlock — `loginctl unlock-session` does nothing.
- The shell never sets logind's LockedHint, so nothing outside the
  session can tell whether the screen is locked.
- RESOLVED same day: lock-on-suspend VERIFIED working end to end via
  a logind suspend (screen came back locked, user unlocked via PAM).
  The dbus-monitor eavesdrop fallback DOES deliver PrepareForSleep on
  dbus-broker; the AccessDenied warning is cosmetic. Earlier failures
  were test-methodology: `rtcwake -m mem` writes /sys/power/state
  directly and bypasses logind entirely (no PrepareForSleep, no
  inhibitors, no lock) — test logind-dependent behaviour with
  `rtcwake -m no -s N` + `systemctl suspend`, never `rtcwake -m mem`.
- Touchscreen verified working after mapping the himax digitizer to
  the rotated output (touchdevice output/transform 3 in skel
  monitors.lua, confirmed on device) — mutter did this implicitly,
  Hyprland needs it explicit; same family as the display transform
  and accelerometer mount matrix.
- power-profiles-daemon loads its placeholder driver on RK3588, so the
  power-profile UI is cosmetic — switching profiles changes nothing.
- ufw cannot work on linux-fydetab 6.12.43 pkgrel<=16, for TWO stacked
  kernel-config defects (both ChromeOS-isms in fydetabduo_defconfig,
  both fixed in the pkgrel-17 fragment, fold into the defconfig once
  the on-device verification is final):
  1. CONFIG_NF_TABLES unset (plus XT_MATCH_RECENT, XT_TARGET_LOG,
     MULTIPORT, BRIDGE_NETFILTER), so the nft-backed /usr/bin/iptables
     Arch ships cannot talk to the kernel at all. Added as modules in
     pkgrel-16 — which then exposed defect 2.
  2. CONFIG_STATIC_USERMODEHELPER=y (defconfig line 790) funnels every
     kernel usermodehelper exec through /sbin/usermode-helper, a binary
     ChromeOS ships and Arch does not have. Every request_module —
     i.e. ALL kernel module autoloading — silently fails with ENOENT.
     iptables-nft then reports "Extension conntrack is not supported,
     missing kernel module?" for any xt match not already loaded, and
     ufw-init dies AFTER setting DROP policies but BEFORE installing
     the INPUT jumps: fail-CLOSED, device unreachable (locked us out
     over SSH 2026-08-18; recovered via serial console). With modules
     preloaded by hand ufw starts and the full Omarchy rule set works,
     which isolates autoload as the one broken link; a temporary
     /usr/bin/usermode-helper -> modprobe symlink made cold autoload
     work instantly, proving the mechanism. Manual modprobe never uses
     the helper, which is why this defect stayed invisible on every
     shipped image (it also breaks on-demand fs/crypto module loads).
  Verification plan for pkgrel-17: install, enable ufw.service, reboot,
  cold boot must bring ufw up with no preloading and SSH must survive.
  Docker's iptables networking was blocked by the same pair.

## Deferred TODOs

- Remaining feature/config gaps vs official Omarchy (audited
  2026-08-18): ordered work list in docs/omarchy-feature-gaps.md.
  Tier 1 quick wins: zram-generator (image currently has NO swap while
  carrying zram-tuned sysctls) and the two chromium theming files
  (browser theming silently dead). Also records the untested-risk
  areas (screen recording/portal/nightlight on this GPU pipeline) and
  the LUKS/autologin posture note.
- Menu install-entry gaps (accepted as-is 2026-08-18): 16 buildable
  aarch64 packages and 13 permanently-x86 entries; the work list and
  per-package details live in docs/omarchy-pkgs-coverage.md.
- Filesystem feature gap (accepted as-is 2026-08-18): upstream is
  Limine+btrfs+snapper+LUKS, we are U-Boot+ext4, which forfeits
  pre-update snapshots/rollback (omarchy-update degrades gracefully:
  omarchy-snapshot exits 127, update continues), Limine boot-menu
  rollback, factory reset (needs the Quattro ISO's @factory subvolume
  and LUKS re-keying), and hibernation setup (btrfs /swap subvolume +
  Limine required). Recoverable subset if ever wanted: root-on-btrfs
  under U-Boot brings back snapshots + CLI rollback, at the cost of a
  btrfs-aware resizefs and image-assembly rework; boot-menu rollback
  and factory reset would additionally need custom U-Boot integration
  and an installer-created baseline we structurally do not have.
- UEFI/Limine route (assessed 2026-08-18, deferred): our boot chain is
  the prebuilt rockchip 2017.09 vendor blob set (firmware/PROVENANCE.md)
  with the Power+VolUp recovery inside it; it cannot host UEFI, so the
  route means replacing boot firmware -- mainline U-Boot EFI_LOADER
  (board port; recovery redoable as an env-script ADC-key check; Limine
  compatibility unvalidated) or EDK2-rk3588 (heavier port; recovery
  becomes platform code). Hardest piece either way: Limine's snapshot
  boot menu needs firmware-stage DSI panel output and USB-keyboard
  input, else rollback is serial-only. Only worth doing on top of the
  btrfs migration; bench-testable brick-free via maskrom/rkdeveloptool.
  Cheaper middle path if menu-less rollback suffices: btrfs + a script
  generating extlinux entries per snapshot on current U-Boot.

- First-boot setup via upstream deferred provisioning (assessed
  2026-08-19, feasible; supersedes the earlier first-boot password
  change TODO): official Omarchy's getting-started flow is
  omarchy-provision-owner.service — armed by
  /var/lib/omarchy/provisioning/pending, it runs the gum setup form on
  tty1 before SDDM (keyboard layout, full name, username, password,
  hostname, timezone), creates the user with the group grants recorded
  in provisioning/groups, then hands off to SDDM. Its LUKS re-key step
  self-gates (needs a staged luks-key file AND a crypto_LUKS root), so
  it no-ops cleanly on our ext4 image. Adoption plan: build the image
  with NO baked user (mirror `omarchy apply system
  --defer-provisioning`: hooks record group grants in
  provisioning/groups instead of usermod), stage the pending marker,
  install+enable the service, drop SDDM autologin. Side benefit:
  recorded group grants close the overlay /etc/group membership gap
  (docs/omarchy-feature-gaps.md Tier 3). To verify before build: our
  aarch64 omarchy package ships bin/omarchy-provision-owner +
  install/provisioning/, gum is in the image, and ordering vs our
  first-boot resizefs service. Constraint: the tty1 form needs a
  physical keyboard (no on-screen keyboard on a TTY), so the
  keyboard-dock requirement must be documented — or a fallback kept.
