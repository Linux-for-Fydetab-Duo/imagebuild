# FydeTab Duo image build

Builds an Arch Linux ARM (aarch64) GNOME image for the FydeTab Duo (RK3588S),
booting through u-boot, **from an x86_64 host**. Also maintains the `fyde` pacman
repository the image installs from.

The project is self-contained: it reads nothing outside this directory. Anything
taken from elsewhere is vendored with a `PROVENANCE.md` next to it. Network
fetches are cached under `cache/`, so a second build needs no downloads.

## Requirements

- docker
- a `qemu-aarch64` binfmt handler carrying the **F** (fix-binary) flag

`build.sh` refuses to start without both. The F flag is what lets aarch64
binaries run inside the target chroot without qemu being copied into it; without
it, every emulated step fails with a confusing ENOENT. On Debian/Ubuntu install
`qemu-user-static`; in CI use `docker/setup-qemu-action`.

## Usage

```sh
./build.sh containers        # build the two build containers (~830 MB on first run)
./build.sh sync              # mirror published packages we do not build into ./repo
./build.sh pkg               # build all PKGBUILDs into ./repo
./build.sh pkg mutter        # ...or just one
./build.sh image             # bootstrap -> customize -> assemble -> publish
./build.sh all               # everything, in order
```

Output lands in `out/`: the compressed image, a `.manifest` listing every
installed package, and a `.sha256`.

## Why it can cross-build

Only four things need to execute aarch64 code: package install scriptlets,
`mkinitcpio`, `locale-gen`, and `pacman-key`. Everything else — resolving and
extracting packages, partitioning, `mke2fs`, writing the bootloader, compressing
— is architecture-neutral and runs at full native speed. `pacman` itself is the
host's x86_64 binary with `Architecture = aarch64`; only the chroot steps are
emulated, and they are confined to `profiles/*/hooks/`.

The kernel is *cross-compiled*, not emulated: its build system honours
`ARCH`/`CROSS_COMPILE` from the environment, so the PKGBUILD needs no changes.

## Layout

| Path | What it is |
|---|---|
| `build.sh` | the only entry point |
| `container/` | the x86 build container, and the ALARM aarch64 one for emulated package builds |
| `pkgbuilds/` | vendored PKGBUILDs — see `SOURCE.md` |
| `pkg/BUILDMODES` | where each package builds: `cross`, `emulated`, `noarch`, `skip` |
| `pkg/build-pkg.sh` | builds packages into `repo/` and refreshes the database |
| `pkg/sync-published.sh` | mirrors published packages this project does not build |
| `repo/fyde/aarch64/` | the pacman repo — publishable as-is |
| `stages/` | the four image stages |
| `profiles/arch-gnome/` | the image definition |
| `vendor/cros/` | reference material copied from the openFyde tree |
| `cache/`, `work/`, `out/` | generated; safe to delete |

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

`profiles/arch-gnome/pacman.conf` lists `[fyde]` **first** on purpose: pacman
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

p1  FW      64s … 65535s    no filesystem
p2  ROOTFS  65536s … end    ext4     <- boot.cmd hardcodes "setenv rootpart 2"
```

Stage 3 uses no loop device and no mount: `sgdisk` on a plain file, `dd` for the
blobs, and `mke2fs -E offset= -d` to create and populate the filesystem in
place. That is what makes it work inside a container and on a CI runner.

## GPU

The Mali G610 is driven by **panthor** (kernel) + panfrost gallium (`mesa`) +
panvk (`vulkan-panfrost`). Not the Rockchip vendor `mali_kbase` blob driver, and
not `mesa-panfork-git`, which was the pre-panthor stopgap.

Panthor requests its firmware at `arm/mali/arch<major>.<minor>/mali_csffw.bin`,
built from the live GPU id, with **no fallback** to the bare name upstream. So
`mali-G610-firmware-rkr4` installs to `/usr/lib/firmware/arm/mali/arch10.8/`,
not the flat path the vendor driver used. Stage 4 asserts the file is there.

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
