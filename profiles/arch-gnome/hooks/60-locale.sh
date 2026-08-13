#!/bin/bash
# Runs inside the target rootfs (emulated aarch64).
# The overlay supplies /etc/locale.gen and /etc/locale.conf; generate the
# locales here so the image does not have to do it on first boot.
set -euo pipefail

locale-gen
