# Bootloader blobs

These three files are the Rockchip boot chain, written to fixed sector offsets of
the image by `stages/03-image.sh`. They are prebuilt binaries with no build recipe
in this project.

| File | Written at | Size |
|---|---|---|
| `idblock.bin` | LBA 64 | 239616 |
| `uboot.img` | LBA 16384 | 4194304 |
| `resource.img` | LBA 24580 | 12964352 |

## Where they came from

Copied verbatim from `Linux-for-Fydetab-Duo/releases`, path
`fydetab-arch/uboot/`, at commit `f01b868b7191392723f5f000fe165b17c7383bbb`
(2026-02-25). These are the blobs the previous image build shipped, so they are
the known-working set for this board.

## How blobs like these are produced

The recipe lives in the openFyde cros tree (see `vendor/cros/PROVENANCE.md`):
`rockchip-linux/u-boot` @ `63c55618` + `sys-boot/rk-uboot/files/rk8/*.patch`,
built with `./make.sh rk3588s_fydetab_duo` / `--spl` / `--idblock`; `resource.img`
comes from rkbin's `resource_tool` over the fydetab bmp logos.

**The cros artifacts are a different build from these.** The `idblock.bin` in
cros r150 has md5 `471b4c819407c51c5f4dba24f43a1546`; the one here has
`cd7a3d34a1f3070d254be4a16076ffca`. Swapping in the cros blobs is a change of
bootloader, not a refactor, and cannot be validated without booting the device.
If you want reproducible u-boot, add a separate build recipe — do not silently
substitute.

## Not here: boot.scr

The boot script is **not** a vendored blob. It is generated at image build time
from `profiles/arch-gnome/boot/boot.cmd` with `mkimage`, so the kernel filenames
and the root partition number stay consistent with the partition layout.

## uboot.img replaced 2026-08-13 (deep-suspend capable chain)

`uboot.img` is now the FIT extracted from the FydeOS eMMC install of the
reference Fydetab Duo (LBA 16384..24575, sha256
2b3e5e613ed0f7bfc982e4110c8a48642d01237326944b5fd08e4134fcffcd96), built
Jul 23 2024 from the same u-boot base (rockchip-linux/u-boot 63c55618)
per the openFyde rk-uboot-5.10.0-r8 ebuild. It differs from the previous
blob (kept as `uboot.img.pre-deep`, sha256 4fe30889...) in the bundled
ARM Trusted Firmware: the newer BL31 resumes from DEEP suspend, the old
one reboots the board on wake from deep (verified on hardware
2026-08-13). Cold boot behaviour is identical (same legacy boot.scr
flow); verified booting this image's SD layout on hardware. Raw dumps of
both chains: `cache/bootchain/`.

## idblock.bin replaced 2026-08-13 (same round as uboot.img)

`idblock.bin` is now the DDR/SPL idblock dumped from the FydeOS eMMC of the
reference device (LBA 64 region, trailing zeros trimmed to 3702784 bytes,
sha256 75b45f19...), SPL banner "U-Boot SPL 2017.09-231221-dirty #yang
(Sep 06 2024)" — the field-updated loader FydeOS itself boots. The boot
ROM prefers the eMMC idblock when one exists, so on the reference device
this blob is bypassed; it matters for SD-only/blank-eMMC boots. Old blob
kept as `idblock.bin.pre-deep`.
