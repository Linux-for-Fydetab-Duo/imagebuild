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
