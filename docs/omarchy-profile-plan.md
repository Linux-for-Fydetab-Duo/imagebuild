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
  Suspend/resume behaviour under Hyprland (our vop2 fix is
  compositor-independent, but hypridle/hyprlock replace GNOME's path);
  wifi/BT; audio (pipewire); brightness/rotation basics; omarchy-update
  flow pointed away from omarchy.org repos (pin via the pre-refresh
  hook + [fyde]).

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

## Deferred TODOs

- First-boot password change (user-requested 2026-08-18, deferred to
  a later round): the image ships a known password (user and root:
  omarchy) with passwordless-sudo wheel and SDDM autologin — fine on
  the bench, unacceptable to hand out. Design needed: plain
  chage -d 0 expiry is invisible under autologin (auth is skipped),
  so the change must hook the first session instead — candidates: a
  first-run omarchy provisioning step (upstream has one we dropped),
  a session-side oneshot prompt, or disabling autologin until the
  password is rotated.
