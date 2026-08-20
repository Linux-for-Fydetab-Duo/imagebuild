# Omarchy profile

An [Omarchy](https://omarchy.org) 4.0.0 image for the FydeTab Duo: Hyprland
0.56 with the Quickshell-based Omarchy shell.
First released as
[Omarchy for FydeTab Duo v0.1.5](https://github.com/Linux-for-Fydetab-Duo/imagebuild/releases/tag/prod-omarchy-v0.1.5).

- Identity: none baked. `omarchy-provision-owner` asks for it on tty1 at
  first boot and creates the owner with the groups staged in
  `overlay/var/lib/omarchy/provisioning/groups`; root gets the same
  password. Passwordless sudo via `wheel`. Needs a physical keyboard —
  see the root README's "First boot".
- Display: 2x HiDPI scale plus the portrait-panel rotation and touchscreen
  mapping Hyprland does not do by itself (`overlay/etc/skel/.config/hypr/`).
- Omarchy parity: the upstream service set, ufw with Omarchy's rules,
  zram swap, lock-screen PAM, first-run user provisioning, and a package
  repo carrying aarch64 builds of the omarchy packages (including
  `voxtype-bin` for dictation) that upstream publishes only for x86_64.

## Building and releasing

```sh
./build.sh image omarchy
```

CI builds this profile from `prod-omarchy-*` / `stag-omarchy-*` tags, or
from the workflow-dispatch `profile` dropdown.

## Where the details live

| Concern | Document |
|---|---|
| Plan, phase history, deferred TODOs | `../../docs/omarchy-profile-plan.md` |
| Feature/config gaps vs official Omarchy | `../../docs/omarchy-feature-gaps.md` |
| omarchy-pkgs package coverage on aarch64 | `../../docs/omarchy-pkgs-coverage.md` |
| Vendored omarchy PKGBUILDs and local changes | `../../pkgbuilds/OMARCHY-VENDOR.md` |

## Profile structure

| Path | What it is |
|---|---|
| `packages.list` | upstream's base manifest plus the FydeTab device set; header documents every substitution and drop |
| `hooks/` | build-time chroot configuration: services, locale, Omarchy config ports, pacman snapshot |
| `overlay/` | files shipped verbatim: provisioning state, sddm/ufw/pam config, Hyprland defaults |
| `firmware/`, `boot/` | Rockchip boot chain blobs and boot script (see `firmware/PROVENANCE.md`) |
