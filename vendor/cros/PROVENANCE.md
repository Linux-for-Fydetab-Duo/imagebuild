# Vendored from the FydeOS / openFyde cros tree

Everything here is a **copy**. The build never reads outside `imagebuild/`.
Source tree at the time of copying: `~/workspace/cros/r150` (release r150).

| File | Copied from | Why it is here |
|---|---|---|
| `kconfigs/fydetab_duo-6_12-def-r2` | `src/overlays/overlay-fydetab_duo-openfyde/kconfigs/fydetab_duo-6_12-def-r2` | Known-good 6.12 kernel config for this exact board. Reference twin for the panthor GPU options when validating `fydetabduo_defconfig`. |
| `fydetab_duo-openfyde-make.conf` | `src/overlays/overlay-fydetab_duo-openfyde/make.conf` | Records the board's USE flags / DTS name, i.e. which drivers FydeOS actually ships. |

## What the reference config says about the GPU

```
CONFIG_DRM_PANTHOR=y
# CONFIG_DRM_PANFROST is not set
# CONFIG_MALI is not set
# CONFIG_DRM_MALI_DISPLAY is not set
CONFIG_DRM_ROCKCHIP=y
```

So FydeOS r150 drives the Mali G610 with **panthor**, not with panfrost and not
with the Rockchip vendor `mali_kbase` blob driver. That is the configuration this
Arch image targets.

`make.conf` also carries `USE="-mali panfrost vulkan"` and `ROCKCHIP_DTS=rk3588s-fydetab_duo`.
Note the cros DTS name uses an underscore; the Arch kernel's device tree is
`rk3588s-fydetab-duo.dtb` (hyphen). They are different trees — do not mix them up.

## How FydeOS feeds the Mali CSF firmware to panthor, and why we differ

Worth recording, because the cros tree looks like it contradicts upstream panthor
and it does not. On FydeOS the blob is installed **flat** at
`/lib/firmware/mali_csffw.bin` (by `chromeos-base/inaugural-firmware`, which globs
its `files/firmware/` directory) and no `arm/mali/` directory exists anywhere in
the sysroot or the image. That works there because of two things we do not have:

1. The rk3588 chipset bashrc overrides the kernel eclass default
   (`builtin_fw_mali_g57_files=( mali_csffw.bin )`), and the board enables
   `builtin_fw_mali_g57`, so the blob is compiled into `vmlinux` via
   `CONFIG_EXTRA_FIRMWARE="mali_csffw.bin"`. `request_firmware()` resolves it from
   the builtin table under the bare name, never touching the filesystem.
2. The chipset overlay applies `031-fix-panthor-firmware-patch.patch` at emerge
   time, which retries `request_firmware()` with the bare `CSF_FW_NAME` after the
   arch-versioned path fails. (Patches are applied into `${WORKDIR}`, so the
   checked-out kernel tree stays pristine — the in-tree source being unpatched is
   not evidence that the shipped kernel is.)

This image carries stock panthor with neither the builtin firmware nor that
fallback patch, so it must place the blob at
`/usr/lib/firmware/arm/mali/arch10.8/mali_csffw.bin`. That is what
`pkgbuilds/mali-G610-firmware-rkr4` now does.

The two blobs are different builds — FydeOS ships 274432 bytes
(`cef54db88334fd3e5f432324a683dc1d`), this project ships the rkr4 blob at 266240
bytes (`8cacdb33ddb8ccaa2281d318e60c1376`). Both are valid: magic `0xc3f13a6e`,
header version `0.3` (panthor requires major 0), same `version_hash 0x01010000`.
The rkr4 blob is therefore kept and the FydeOS one is deliberately **not**
vendored. If the GPU ever fails to come up, that blob is the first thing to try.

## Not vendored: u-boot

`sys-boot/rk-uboot-5.10.0-r8.ebuild` builds the bootloader from
`rockchip-linux/u-boot` commit `63c55618fbdc36333db4cf12f7d6a28f0a178017` plus the
14 patches in `sys-boot/rk-uboot/files/rk8/`, via `./make.sh rk3588s_fydetab_duo`,
`./make.sh --spl` and `./make.sh --idblock`, using rkbin tools.
`sys-boot/rk-uboot-resource` produces `resource.img` by running rkbin's
`resource_tool` over the fydetab bmp logos.

The blobs this project ships in `profiles/arch-gnome/firmware/` are **not** from
that r150 build — see `profiles/arch-gnome/firmware/PROVENANCE.md`. Building
u-boot reproducibly is a separate recipe and is deliberately out of scope here.
