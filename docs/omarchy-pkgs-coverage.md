# omarchy-pkgs coverage on aarch64

2026-08-18. Audit of upstream https://github.com/omacom-io/omarchy-pkgs
(114 PKGBUILDs at c2b3796) against what this tree vendors and what ALARM
provides. Availability verified in the aarch64 build container and
cross-checked against the live device's repos. Companion to
`pkgbuilds/OMARCHY-VENDOR.md` (the per-package vendoring rationale).

Status: current state accepted as-is (2026-08-18) -- nothing here blocks
the image. The "Closeable gaps" section below is the deferred work list
for whenever we want the affected menu entries working.

## Verdict

Of the 90 upstream packages we do not vendor, 84 are correctly excluded:
x86-only proprietary blobs, x86 hardware drivers, the legacy 3.x
walker/elephant stack, repo-internal tooling, or packages ALARM already
carries under another name. The real cost is 16 packages that Omarchy's
menus can install on x86 but that silently fail here despite being
buildable for aarch64, plus 13 menu entries that can never work (no
aarch64 upstream exists) and one broken composite entry (Preinstalls).

Nothing in the base image is missing: `profiles/omarchy/packages.list`
references none of the 90, and zero of them exist in ALARM under the
same name (omarchy-pkgs exists precisely to carry what Arch does not).

## Why menu entries fail hard

`omarchy-pkg-add` is `pacman -S --noconfirm --needed` with no AUR
fallback and a hard per-package check, so one unresolvable name aborts
the whole menu action. Every package below that a menu references is a
user-visible breakage until vendored (or the entry is hidden).

## Closeable gaps (buildable for aarch64, menu-reachable)

Cheapest first; "vendor" means the same treatment voxtype-bin got.

- `omazed` (arch=any) -- sole blocker of the Zed entry; `zed` itself is
  in ALARM extra.
- RetroArch core set: `libretro-cap32-git`, `libretro-fbneo-git`,
  `libretro-vice-git` (10 split pkgs), `libretro-database-git`,
  `retroarch-joypad-autoconfig-git`, plus `libretro-uae-git` (needs
  aarch64 added to arch=(), the usual never-widened field). Mainline
  cores and retroarch itself are all in ALARM -- these six PKGBUILDs
  unblock the whole Gaming > RetroArch entry.
- `visual-studio-code-bin`, `sublime-text-4`, `openai-codex-desktop`,
  `nordvpn-bin`, `once-bin`: all have real source_aarch64 artifacts.
- `xpadneo-dkms` (arch=any, DKMS): Xbox-controller entry.
- `omarchy-dev` + `omarchy-settings-dev` (Dev update channel): needs the
  same limine/snapper-dep strip our vendored `omarchy` PKGBUILD does.

## Permanently broken menu entries (no aarch64 upstream)

1password (+cli), cursor-bin, dropbox (+nautilus-dropbox, dropbox-cli),
grok-bot, heroic-games-launcher-bin, lmstudio-bin, minecraft-launcher,
spotify, symfony-cli, umu-launcher (Lutris also needs wine-staging,
absent from ALARM -- dead end regardless). These entries should be
hidden on this image rather than left to error out; that means patching
`default/omarchy/omarchy-menu.jsonc`, which we so far ship unmodified.
Note: symfony-cli and 1password-cli DO publish arm64 artifacts upstream;
only the omarchy-pkgs PKGBUILDs are x86-limited.

- The Preinstalls entry (install.preinstalls / remove.preinstalls) is
  broken by our documented pinta/obsidian/obs-studio drops: one
  `omarchy-pkg-add` call includes them, so the whole entry fails.

## Correctly excluded, for the record

- Hardware-gated x86 drivers (12): asusctl, intel-ipu7-camera,
  intel-lpmd, linux-ptl, nvidia bits, tuxedo/dell/macbook/qmk/yt6801
  drivers -- reached only from hardware-detect paths that never match
  this device.
- Legacy 3.x-to-4.0 migrator removals (21): walker, the elephant stack,
  claude-code, makima-bin, wayfreeze, etc. -- referenced only inside
  remove_retired_default_packages().
- Unreferenced by the OS repo (16): bun-bin, crush-bin, cursor-cli,
  typora, hyprshade, omarchy-fish/zsh, omasnap, omatrack, ... Several
  ship aarch64 binaries and are cheap to add if ever wanted.
- ALARM-substituted names already in use: quickshell (vs quickshell-git,
  ~20 commits behind upstream's pin), localsend-bin, libfprint, ttfx,
  chromium (vs omarchy-chromium-bin -- but see below), emacs, zed.

## Open flags

- `omarchy-chromium-bin` HAS a real aarch64 prebuilt (Omarchy publishes
  omarchy-chromium aarch64 release packages, version 148 vs ALARM
  chromium 151). Decision point: Omarchy patches/branding vs newer base.
- `omarchy-emacs` installs via yay/AUR, not pacman -- untested whether
  on-device AUR building works; the Emacs menu entry may or may not work.
- Vendored `mise-bin` is one release behind upstream (2026.8.6 vs .8).
- ALARM DBs used for the check were a few days stale; a package added
  to ALARM this week would not have shown.
