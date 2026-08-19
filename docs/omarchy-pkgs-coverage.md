# omarchy-pkgs coverage on aarch64

2026-08-19 re-audit (supersedes the 2026-08-18 audit). Method: collect
every package name every `omarchy-pkg-add` call site can install (menu
actions incl. line-continued and variable-fed lists, bin/ scripts,
install/ hardware scripts), group them by install transaction, and
check each NAME against ALARM aarch64 (core/extra/alarm/aur), our
[fyde] repo, and omarchy-pkgs PKGBUILDs (arch= / source_aarch64).
Companion: `pkgbuilds/OMARCHY-VENDOR.md`.

Upstream binary status: pkgs.omarchy.org publishes NO usable aarch64 —
the channel repos (stable/edge) 404 for aarch64; a channel-less
/aarch64/ db exists but contains only omarchy-keyring (checked
2026-08-19; re-check occasionally, it looks like infrastructure being
prepared).

## The lesson that forced the re-audit

The 2026-08-18 audit classified by functional substitution ("ALARM has
zed, the Zed entry is covered"). Wrong layer: `omarchy-pkg-add` is
`pacman -S` on EXACT names and one unresolvable name aborts the whole
transaction. `omarchy-install-editor-zed` runs `omarchy-pkg-add zed
omazed` — zed resolved, omazed did not, entry dead (fixed by vendoring
omazed, 2026-08-19). Audit by name resolution per transaction, never by
substitute availability. The same pass found more misses: four
"mainline" libretro cores are NOT in ALARM, and the ollama, ghostty,
and bitwarden entries were never checked at all.

## Closeable now — buildable from omarchy-pkgs as-is

One vendored PKGBUILD each (the omazed treatment), entry fully fixed
by building:

- `sublime-text-4` (bin repack) — Editor > Sublime, also default-editor
- `visual-studio-code-bin` (bin repack) — Editor > VSCode
- `openai-codex-desktop` (bin repack) — AI > ChatGPT/Codex desktop
- `nordvpn-bin` (bin repack) — Service > NordVPN
- `once-bin` (bin repack) — Service > Once
- `sunshine` (source build) — Service > Sunshine
- `omarchy-emacs` (source build) — Editor > Emacs
- `omarchy-dev` + `omarchy-settings-dev` — Dev update channel (needs
  the same limine/snapper-dep strip as our vendored `omarchy`)

Note: sublime/vscode/nordvpn repackage proprietary binaries; serving
them from the public fyde repo means redistributing those blobs
(upstream does the same for x86; decision recorded when acted on).

## Closeable with extra work

- Ollama (AI menu): plain `ollama` is in NEITHER ALARM nor
  omarchy-pkgs. Vendor Arch's ollama PKGBUILD (Go, builds on aarch64).
- Ghostty (Terminal menu): not in ALARM (zig toolchain); vendor from
  Arch's PKGBUILD if wanted — medium effort.
- Xbox controllers: `omarchy-pkg-add linux-headers xpadneo-dkms` —
  xpadneo-dkms is buildable (arch=any), but `linux-headers` does not
  exist on ALARM (kernel is linux-aarch64) and is wrong for our kernel
  anyway. Fix requires linux-fydetab-headers with
  `provides=(linux-headers)` (pacman resolves virtual -S targets via
  provider) — verify linux-fydetab builds a headers subpackage first.
- RetroArch (Gaming menu): ONE transaction of ~40 names. Missing:
  - from omarchy-pkgs, buildable: `libretro-cap32-git`,
    `libretro-fbneo-git`, `libretro-vice-git` (10 split pkgs),
    `libretro-database-git`, `retroarch-joypad-autoconfig-git`;
    `libretro-uae-git` needs aarch64 added to arch=()
  - in NEITHER ALARM nor omarchy-pkgs: `libretro-blastem`,
    `libretro-desmume`, `libretro-kronos`, `libretro-ppsspp` — need
    AUR-sourced vendoring; blastem is an x86 JIT and likely impossible
    on aarch64, which would keep the entry broken unless the script's
    list is patched. Building the easy 6 alone does NOT fix the entry.

## Permanently broken entries (hide-list for omarchy-menu.jsonc)

No aarch64 artifact exists upstream; these menu entries fail hard until
hidden (we ship the menu unmodified so far):

1password (1password-cli alone IS buildable but shares the failing
transaction), bitwarden, cursor, dropbox (same pair situation with
dropbox-cli), grok-bot, LM Studio, Minecraft, Spotify, Steam, Heroic,
Battle.net + Lutris (umu-launcher/wine-staging absent), symfony-cli
(upstream publishes arm64; only the omarchy-pkgs PKGBUILD is
x86-limited — self-vendor if ever wanted), and Preinstalls (pinta is
x86-only; obsidian/obs-studio also unresolvable — entry needs a script
patch regardless). Dictation too: our aarch64 voxtype-bin rewrite was
tested on the device 2026-08-19 and does not work, so it was removed
from the repo and the entry rejoins this list (see
pkgbuilds/OMARCHY-VENDOR.md).

## Excluded: hardware-gated paths

asusctl, dell/tuxedo/framework/apple-t2 drivers, intel
ipu7/lpmd/ptl/thermald/video-acceleration, supergfxctl, broadcom-wl —
reached only from hardware-detect paths that never match this device.
Not counted as breakage.

## Open flags

- `omarchy-chromium-bin` has a real aarch64 prebuilt upstream (version
  lags ALARM chromium). Decision point: Omarchy patches/branding vs
  newer base.
- Vendored `mise-bin` trails upstream by one release.
- ALARM dbs move; a name absent today may appear — re-run the check
  before acting on any single entry.
