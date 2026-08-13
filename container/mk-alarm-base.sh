#!/usr/bin/env bash
# Imports the official Arch Linux ARM aarch64 rootfs tarball as a docker image,
# to serve as the base for Dockerfile.arm64.
#
# Uses the upstream mirror: the ustc mirror serves the package repos but returns
# 403 for /os/, so it cannot supply this tarball.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$PROJECT/cache"
TARBALL="$CACHE/ArchLinuxARM-aarch64-latest.tar.gz"
URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
IMAGE="fydetab-build:alarm-base"

mkdir -p "$CACHE"

if [ ! -s "$TARBALL" ]; then
    echo "==> downloading ALARM aarch64 rootfs (~830 MB) to cache/"
    curl -fL --progress-bar -o "$TARBALL.part" "$URL"
    mv "$TARBALL.part" "$TARBALL"
else
    echo "==> using cached $(basename "$TARBALL")"
fi

echo "==> importing as $IMAGE"
# The tarball is a plain rootfs, so docker import takes it directly. Ownership
# in the tarball is numeric and preserved.
docker import \
    --platform linux/arm64 \
    --change 'CMD ["/bin/bash"]' \
    "$TARBALL" "$IMAGE"

echo "==> $IMAGE ready"
