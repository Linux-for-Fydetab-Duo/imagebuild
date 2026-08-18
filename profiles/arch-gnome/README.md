# arch-gnome profile

The original Arch Linux ARM GNOME image for the FydeTab Duo: a stock GNOME
(Wayland) desktop with the board support set — panthor GPU stack, AP6275P
Wi-Fi/Bluetooth, touch, sensors and rotation, deep suspend/resume — released
from `prod-*` tags (latest: `prod-v0.1.4`).

- Default identity: user `arch`, password `arch`. Change it on first boot.
- GNOME is tablet-tuned: mutter honours the panel-orientation DRM property,
  touchegg gestures, and the gjs on-screen keyboard is available as an
  optional package.
- Ships the full `linux-firmware` meta package (the omarchy profile trims
  it to what the board needs; this profile has not adopted that yet).

## Building and releasing

```sh
./build.sh image arch-gnome     # or plain `./build.sh image` (default)
```

CI builds this profile from any `prod-*` / `stag-*` tag that does not carry
the `omarchy` infix, or from the workflow-dispatch `profile` dropdown.

## Profile structure

| Path | What it is |
|---|---|
| `packages.list` | ALARM base + GNOME + the FydeTab device set |
| `hooks/` | build-time chroot configuration |
| `overlay/` | files shipped verbatim: identity, GDM config, GNOME defaults |
| `firmware/`, `boot/` | Rockchip boot chain blobs and boot script (see `firmware/PROVENANCE.md`) |
