# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

Self-contained pipeline that cross-builds aarch64 Arch Linux images for the
Fydetab Duo tablet on an x86 host (docker + qemu binfmt). Two profiles:
`arch-gnome` (GNOME/GDM) and `omarchy` (Hyprland/Omarchy, SDDM autologin).
Directory map: README.md. Design rationale: docs/build-internals.md.

## Commands

- `./build.sh containers` — build x86 + emulated arm64 containers (first run
  pulls ~830 MB ALARM base)
- `./build.sh sync` — mirror published packages into repo/fyde/aarch64
  (image builds hard-require fyde.db)
- `./build.sh pkg [name...]` — build vendored PKGBUILDs (skips existing
  outputs; FORCE=1 rebuilds)
- `./build.sh image [arch-gnome|omarchy]` — stages 01→04 (default arch-gnome)
- `./build.sh all [profile]`, `./build.sh shell [x86|arm64]`

Host prerequisites: docker + qemu-aarch64 binfmt with the F flag (preflight
enforces). Image builds are heavy (CI allots 350 min).

## Boot chain — do not "simplify"

- boot.scr is compiled by stages/mk-rk-script.py, NOT mkimage: the device's
  rockchip 2017.09 u-boot needs the 0xffffffff size-table terminator; plain
  mkimage output makes it silently fall back to eMMC boot. (The mkimage line
  in boot.cmd's header comment is stale.)
- The ROOTFS partition must carry the GPT legacy_boot attribute and be
  partition 2; the DTB is rk3588s-fydetab_duo.dtb (underscore, not hyphen).
  stages/04-publish.sh asserts these.
- Mali CSF firmware must ride in the initramfs (DRM_PANTHOR=y probes before
  root mounts), listed under BOTH arch10.8 and arch10.10 paths — mkinitcpio
  does not follow the symlink (profiles/*/overlay/etc/mkinitcpio.conf).

## Packaging rules

- Every dir in pkgbuilds/ needs an entry in pkg/BUILDMODES (unlisted = hard
  error). --syncdeps and sudo cannot work inside the containers (no binfmt C
  flag); build-pkg.sh pre-installs deps as container root + makepkg --nodeps.
- [fyde] is deliberately FIRST in profiles/*/pacman.conf — pacman resolves by
  repo order; that is how local builds beat published packages.
- The rolling pacman repo holds exactly ONE generation per package (two break
  repo-add --new --remove); CI prunes at seed and publish. No epoch versions —
  GitHub strips ':' from release asset names.
- Vendored omarchy PKGBUILD deltas are recorded in pkgbuilds/OMARCHY-VENDOR.md;
  update it when re-syncing.

## Kernel changes (linux-fydetab)

- Never push a kernel-repo change before it is verified on the device: the
  PKGBUILD clones the branch, so an unverified push is exactly what the next
  build picks up. Iterate as a local patch file in pkgbuilds/linux-fydetab-6.12/
  (source=() + prepare()); fold into the kernel repo, delete the patch, and
  bump pkgrel only after repeated on-device success.
- The config fragments undo ChromeOS-isms via ./scripts/config, each backed by
  a grep guard later in the PKGBUILD — keep fragment and guard in sync.
  CONFIG_VT_CONSOLE_SLEEP is a promptless def_bool: scripts/config -d cannot
  stick; the PKGBUILD seds the Kconfig default instead.

## Profile gotchas

- Hooks run inside arch-chroot from /.imagebuild-hook.sh — never stage files
  via /tmp or /run (arch-chroot mounts fresh tmpfs over both).
- Services: one mechanism per unit — overlay .wants symlink OR systemctl
  enable in 70-services.sh, never both (iio-sensor-proxy has no [Install];
  only a symlink works).
- omarchy: the x86-only mkinitcpio drop-ins from omarchy-settings must stay
  NoExtract'ed in BOTH the build-time and shipped pacman.conf; `omarchy
  refresh pacman` clobbers /etc/pacman.conf — mitigated by
  hooks/90-pacman-snapshot.sh + the pre-refresh-pacman.d skel hook.
- arch-gnome: the oemcleanup/remove-calamares overlay units are deliberately
  NOT enabled (oemcleanup would userdel the live session's own user).

## CI (.github/workflows/build.yml)

- One profile per run: prod-omarchy-*/stag-omarchy-* tags → omarchy; other
  prod-*/stag-* → arch-gnome; workflow_dispatch input otherwise. Runs are
  serialized (concurrency group) — the rolling repo release is mutable shared
  state.

## Docs

- docs/build-internals.md — cross-build design, [fyde] repo model, partitions, GPU stack
- docs/omarchy-profile-plan.md — omarchy port plan, phase history, deferred TODOs
- docs/omarchy-feature-gaps.md — parity audit vs the official Omarchy installer
- docs/omarchy-pkgs-coverage.md — upstream omarchy-pkgs vs aarch64 availability
