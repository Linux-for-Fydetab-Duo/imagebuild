#!/bin/bash
# Runs inside the target rootfs (emulated aarch64).
#
# The heaviest emulated step, and the most likely to misbehave under qemu-user:
# mkinitcpio spawns a lot of target processes and threaded compressors. It is
# isolated in its own hook so it can be swapped for a lighter compression or
# moved to a native step without touching the rest of the pipeline.
#
# boot.cmd loads /boot/initramfs-linux-fydetab.img, which is what the
# linux-fydetab.preset generates. 02-customize.sh asserts the file exists
# afterwards, so a silent mkinitcpio failure cannot reach the image.
set -euo pipefail

mkinitcpio -P
