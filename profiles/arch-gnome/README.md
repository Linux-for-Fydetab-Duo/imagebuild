# arch-gnome profile

The original Arch Linux ARM GNOME image for the Fydetab Duo: a stock GNOME
(Wayland) desktop with the board support set — panthor GPU stack, AP6275P
Wi-Fi/Bluetooth, touch, sensors and rotation, deep suspend/resume — released
from `prod-*` tags (latest: `prod-v0.1.4`).

- Default identity: user `arch`, password `arch`. Change it on first boot.
- GNOME is tablet-tuned: mutter honours the panel-orientation DRM property,
  touchegg gestures, and the gjs on-screen keyboard is available as an
  optional package.
- Firmware is trimmed to what the board needs (`linux-firmware-other` for
  the Mali GPU plus `ap6275p-firmware` for Wi-Fi/BT), like the omarchy
  profile.

## Building and releasing

```sh
./build.sh image arch-gnome     # or plain `./build.sh image` (default)
```

CI builds this profile from any `prod-*` / `stag-*` tag that does not carry
the `omarchy` infix, or from the workflow-dispatch `profile` dropdown.

## Profile structure

| Path | What it is |
|---|---|
| `packages.list` | ALARM base + GNOME + the Fydetab device set |
| `hooks/` | build-time chroot configuration |
| `overlay/` | files shipped verbatim: identity, GDM config, GNOME defaults |
| `firmware/`, `boot/` | Rockchip boot chain blobs and boot script (see `firmware/PROVENANCE.md`) |
