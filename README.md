# FydeTab Duo image build

Builds Arch Linux ARM (aarch64) images for the FydeTab Duo (RK3588S),
booting through u-boot, **from an x86_64 host**. Also maintains the `fyde`
pacman repository the images install from.

The project is self-contained: it reads nothing outside this directory.
Anything taken from elsewhere is vendored with a `PROVENANCE.md` next to it.
Network fetches are cached under `cache/`, so a second build needs no
downloads.

## Images

| Profile | Desktop | Release tags | Details |
|---|---|---|---|
| [`arch-gnome`](profiles/arch-gnome/README.md) | GNOME (Wayland), tablet-tuned | `prod-*` / `stag-*` | user `arch` |
| [`omarchy`](profiles/omarchy/README.md) | [Omarchy](https://omarchy.org) 4.0 (Hyprland + Quickshell) | `prod-omarchy-*` / `stag-omarchy-*` | first-boot owner setup |

Pushing a release tag makes CI build that profile and attach the image to a
GitHub Release; the workflow-dispatch `profile` input builds either one
manually. Every run also tops up the rolling
[`repo` release](https://github.com/Linux-for-Fydetab-Duo/imagebuild/releases/tag/repo),
which devices use as their `[fyde]` pacman server.

### First boot (omarchy)

The omarchy image bakes no user account. On the first boot Omarchy's own
`omarchy-provision-owner` takes tty1 before SDDM and asks for keyboard
layout, full name, username, password, hostname and timezone; it then
creates that owner — `wheel` plus the grants staged in
`/var/lib/omarchy/provisioning/groups` — gives root the same password, and
hands off to the desktop.

**The form needs a physical keyboard**: the keyboard dock or a USB one.
tty1 has no on-screen keyboard, and neither does the SDDM greeter that
follows.

### Disk encryption (omarchy, optional)

Straight after the owner form, on the same tty1, the image asks whether to
encrypt the disk. Declining costs nothing: the root filesystem is expanded
to fill the medium and the boot carries on.

Accepting stages the passphrase and reboots. The next boot converts the
root partition in place — LUKS2, `cryptsetup reencrypt --encrypt` — from
the initramfs, where nothing has the filesystem open yet, then grows it to
the medium and wipes the staged passphrase. It takes a few minutes, because
the filesystem is still image-sized at that point. If power is cut in the
middle, the following boot resumes the conversion where it stopped.

**An encrypted device asks for the passphrase at every boot**, from the
initramfs, where only a physical keyboard works — the same dock or USB
keyboard the setup form needed. Because that passphrase is then the
authentication boundary, encrypted installs keep the desktop autologin,
which is upstream Omarchy's posture. Unencrypted ones autologin for the
first boot only: a self-removing unit drops it before the next boot, so
every later boot asks for the password at the greeter.

Encryption can also be turned on later with `sudo fydetab-encrypt-setup`.
That works, but the filesystem fills the medium by then and the conversion
has to process all of it, which takes considerably longer.

## Requirements

- docker
- a `qemu-aarch64` binfmt handler carrying the **F** (fix-binary) flag

`build.sh` refuses to start without both. The F flag is what lets aarch64
binaries run inside the target chroot without qemu being copied into it;
without it, every emulated step fails with a confusing ENOENT. On
Debian/Ubuntu install `qemu-user-static`; in CI use
`docker/setup-qemu-action`.

## Usage

```sh
./build.sh containers          # build the two build containers (~830 MB on first run)
./build.sh sync                # mirror published packages we do not build into ./repo
./build.sh pkg                 # build all PKGBUILDs into ./repo
./build.sh pkg mutter          # ...or just one
./build.sh image [profile]     # bootstrap -> customize -> assemble -> publish
./build.sh all [profile]       # everything, in order
```

Output lands in `out/`: the compressed image, a `.manifest` listing every
installed package, and a `.sha256`.

## Layout

| Path | What it is |
|---|---|
| `build.sh` | the only entry point |
| `container/` | the x86 build container, and the ALARM aarch64 one for emulated package builds |
| `pkgbuilds/` | vendored PKGBUILDs — see `SOURCE.md` and `OMARCHY-VENDOR.md` |
| `pkg/BUILDMODES` | where each package builds: `cross`, `emulated`, `noarch`, `skip` |
| `pkg/build-pkg.sh` | builds packages into `repo/` and refreshes the database |
| `pkg/sync-published.sh` | mirrors published packages this project does not build |
| `repo/fyde/aarch64/` | the pacman repo — publishable as-is |
| `stages/` | the four image stages |
| `profiles/` | one image definition per profile, each with its own README |
| `docs/` | build internals, the omarchy plan and gap audits |
| `vendor/cros/` | reference material copied from the openFyde tree |
| `cache/`, `work/`, `out/` | generated; safe to delete |

## Further reading

- [`docs/build-internals.md`](docs/build-internals.md) — why cross-building
  works, the repo model, partition layout, the GPU stack, and what is
  deliberately not here.
- [`docs/omarchy-profile-plan.md`](docs/omarchy-profile-plan.md) — the
  omarchy port: plan, phase history, deferred work.
