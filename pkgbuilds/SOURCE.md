# Vendored PKGBUILDs

Copied from `Linux-for-Fydetab-Duo/pkgbuilds` at commit
`e347e7383e7f52f52cf8bd65125d85b43b48ec4c` (2026-02-25), git metadata stripped.

This project is self-contained, so these are **the** PKGBUILDs it builds — edit
them here. To pull upstream changes later, diff against a fresh checkout of that
repository at the commit above.

Build modes are assigned in `pkg/BUILDMODES`; see that file for why each package
builds where it does.

`grub` and `grub-btrfs` are carried along but not built: nothing in
`profiles/arch-gnome/packages.list` needs them, and the image has no UEFI stage
for grub to install into.
