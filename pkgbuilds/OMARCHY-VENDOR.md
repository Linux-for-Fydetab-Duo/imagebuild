# Omarchy package vendoring

23 PKGBUILDs copied from https://github.com/omacom-io/omarchy-pkgs at
commit 045740e (2026-08-17) for the omarchy profile (see
docs/omarchy-profile-plan.md). Upstream declares aarch64 in nearly all
of them but publishes no aarch64 packages (pkgs.omarchy.org has no
aarch64 tree), so they are built here into the [fyde] repo.

Local changes, kept deliberately minimal:

- omarchy/PKGBUILD: dropped the bootloader-stack deps (limine,
  limine-mkinitcpio-hook, limine-snapper-sync, snapper) — this device
  boots U-Boot into ext4; UEFI/Limine/Btrfs snapshots cannot work.
- tensaku, tzupdate, hyprland-preview-share-picker: added aarch64 to
  arch=() — all three are plain Rust source builds with no
  arch-specific code; upstream just never widened the field.
- omarchy-nvim: added neovim to makedepends. build() runs
  `nvim --headless "+Lazy! sync"`, so neovim is genuinely a build tool;
  upstream's `makepkg -s` flow installs depends too and masks the
  omission, our noarch builds install makedepends only (see
  pkg/build-pkg.sh).

Deliberately NOT vendored (and why):

- walker + elephant stack: only referenced by the legacy 3.x→4.0
  migrator; Omarchy 4 replaced them with the quickshell launcher.
- quickshell-git: ALARM's quickshell release is used instead; revisit
  if the shell QML needs post-release features.
- asdcontrol: Apple Studio Display control — pointless on this device.
- obsidian, obs-studio, pinta (+dotnet-runtime): absent from ALARM,
  heavy or dead-end on aarch64; dropped from the first image.
- 1password/cursor/spotify/steam and the other proprietary x86 blobs:
  optional installers, never in the base image.

Re-syncing against upstream: diff pkgbuilds/<name>/ against
omarchy-pkgs and re-apply the changes above; keep this file current.
