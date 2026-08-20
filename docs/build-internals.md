# Build internals

Deep dives moved out of the top-level README. Everything here applies to
all profiles.

## Why it can cross-build

Only four things need to execute aarch64 code: package install scriptlets,
`mkinitcpio`, `locale-gen`, and `pacman-key`. Everything else — resolving and
extracting packages, partitioning, `mke2fs`, writing the bootloader, compressing
— is architecture-neutral and runs at full native speed. `pacman` itself is the
host's x86_64 binary with `Architecture = aarch64`; only the chroot steps are
emulated, and they are confined to `profiles/*/hooks/`.

The kernel is *cross-compiled*, not emulated: its build system honours
`ARCH`/`CROSS_COMPILE` from the environment, so the PKGBUILD needs no changes.

## The repo

`repo/fyde/aarch64/` mirrors the published layout exactly
(`Server = .../pacman/repo/$repo/$arch`), so publishing is a plain rsync:

```sh
rsync -av --delete repo/fyde/aarch64/ <host>:/…/pacman/repo/fyde/aarch64/
```

It is meant to be a *complete* replacement: `sync` pulls in the packages that
exist upstream but have no PKGBUILD here (`fyde-keyring`, `fyde-mirrorlist`,
`fydeos-wallpapers`, …), while never overwriting a locally built one. So the
image resolves everything from one repo, and what you publish is exactly what
the image was built from.

CI publishes the same directory as the rolling `repo` GitHub release, which
devices can use directly as a pacman server. The release must hold exactly
one generation of every package; the workflow prunes it on both the seed and
publish sides.

`profiles/*/pacman.conf` lists `[fyde]` **first** on purpose: pacman
resolves a package name to the first repo in file order regardless of version.
That is what makes the locally built `linux-fydetab` 6.12.43 win over the
published 6.1.75-3.

## Partition layout

Fixed by the Rockchip boot ROM and by `boot.cmd`; `image.conf` is the single
source of truth and the stages derive everything from it.

```
LBA 64      idblock.bin    ┐
LBA 16384   uboot.img      ├ inside partition 1, which reserves the region
LBA 24580   resource.img   ┘

p1  FW      64s … 65535s       no filesystem
p2  ESP     65536s … 1114111s  FAT32   <- 512 MiB, legacy_boot, type ef00;
                                          boot.cmd hardcodes "setenv bootpart 2"
p3  ROOTFS  1114112s … end     ext4    <- boot.cmd hardcodes "setenv rootpart 3"
```

The ESP is mounted at `/boot`: kernel, initramfs, dtb and `boot.scr` sit at its
filesystem root, and the root filesystem carries `/boot` as an empty mountpoint.
FAT32 with type `ef00` is what lets a later UEFI firmware boot the same layout
without repartitioning.

Stage 3 uses no loop device and no mount: `sgdisk` on a plain file, `dd` for the
blobs, `mkfs.vfat` plus mtools `mcopy` for the ESP, and `mke2fs -E offset= -d`
to create and populate the root filesystem in place. That is what makes it work
inside a container and on a CI runner.

## GPU

The Mali G610 is driven by **panthor** (kernel) + panfrost gallium (`mesa`) +
panvk (`vulkan-panfrost`). Not the Rockchip vendor `mali_kbase` blob driver, and
not `mesa-panfork-git`, which was the pre-panthor stopgap.

Panthor requests its firmware at `arm/mali/arch<major>.<minor>/mali_csffw.bin`,
built from the live GPU id, with **no fallback** to the bare name upstream. The
CSF firmware ships at `/usr/lib/firmware/arm/mali/arch10.8/`, not the flat
path the vendor driver used. Stage 4 asserts the file is there.

If the GPU fails to come up, note that the driver's error prints the bare
filename rather than the path it looked up, so a wrong arch directory is
indistinguishable from a missing file. Confirm the arch from the probe line:

```sh
dmesg | grep 'mali-.* id '      # "mali-g610 id 0xa867 major .. minor .."
```

The arch is the **top two nibbles of that id** (`0xa867` → 10.8). The `major`
and `minor` printed on the same line are `GPU_VER_*`, not the arch numbers.

See `vendor/cros/PROVENANCE.md` for why FydeOS gets away with the flat path and
this image cannot.

## What is deliberately not here

- **No UEFI, no grub.** The board boots u-boot → `boot.scr` → kernel.
- **No u-boot build.** The three blobs are prebuilt inputs with recorded
  provenance; building them reproducibly is a separate recipe.
- **No first-boot keyring hack.** The keyring is populated at build time, which
  removed the `expect` script the old image shipped.
