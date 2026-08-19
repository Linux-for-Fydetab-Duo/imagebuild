# Omarchy package vendoring

24 PKGBUILDs copied from https://github.com/omacom-io/omarchy-pkgs at
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
- voxtype-bin: REMOVED 2026-08-19 (was added 2026-08-18 as an
  aarch64-only rewrite of the AUR PKGBUILD packaging upstream's aarch64
  binaries). Tested on the device and it does not work, so the vendored
  copy, its BUILDMODES entry, and the repo package were dropped. Known
  consequence: the dictation menu entry (`omarchy-pkg-add wtype
  voxtype-bin`) fails on an unresolvable name again -- it moves to the
  broken-entry list in docs/omarchy-pkgs-coverage.md.
- omazed (added 2026-08-19, verbatim -- no local changes): sole blocker
  of the Zed menu entry, whose installer runs `omarchy-pkg-add zed
  omazed` and aborted on that one unresolvable name (`zed` itself is in
  ALARM extra). arch=any and three bash scripts, so it builds noarch.
  Kept out of packages.list on purpose: the entry stays menu-driven
  opt-in, and `zed omazed` resolves to ~1.5 GB installed because zed's
  Vulkan chain drags in nvidia-utils -- dead weight in a base image for
  a Mali G610 device.

- omarchy-dev + omarchy-settings-dev (added 2026-08-19 from upstream
  @12b322d): the Dev update channel pair. omarchy-dev gets the same
  bootloader-stack dep strip as our omarchy; omarchy-settings-dev is
  verbatim (its x86 mkinitcpio drop-ins are already covered by the
  NoExtract path rules). Menu-driven opt-in, not in packages.list.

- omarchy-emacs (added 2026-08-19 from upstream @12b322d, verbatim):
  unblocks the Editor > Emacs menu entry; arch=any config scripts over
  ALARM's emacs-wayland, builds noarch.

- sunshine (added 2026-08-19 from upstream @12b322d): unblocks the
  Service > Sunshine menu entry. Dropped libmfx from depends -- Intel
  QSV, absent from ALARM aarch64 and meaningless on RK3588; sunshine
  builds without it (software encoding). Heavy C++/CMake, builds
  emulated.

Deliberately NOT vendored (and why):

- walker + elephant stack: only referenced by the legacy 3.x→4.0
  migrator; Omarchy 4 replaced them with the quickshell launcher.
- quickshell-git: ALARM's quickshell release is used instead; revisit
  if the shell QML needs post-release features.
- asdcontrol: Apple Studio Display control — pointless on this device.
- obsidian, obs-studio, pinta (+dotnet-runtime): absent from ALARM,
  heavy or dead-end on aarch64; dropped from the first image. Known
  consequence: the menu's Preinstalls entry runs one omarchy-pkg-add
  including all three, so that whole entry fails on this image (see
  docs/omarchy-pkgs-coverage.md).
- 1password/cursor/spotify/steam and the other proprietary x86 blobs:
  optional installers, never in the base image.

Re-syncing against upstream: diff pkgbuilds/<name>/ against
omarchy-pkgs and re-apply the changes above; keep this file current.
