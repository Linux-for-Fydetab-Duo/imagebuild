#!/usr/bin/env bash
# Stage 1: pacstrap the target rootfs. Runs inside the x86_64 container.
#
# pacman itself is a native x86_64 binary here; only package install scriptlets
# execute aarch64 code, via the host's binfmt handler. That keeps the bulk of
# the work (download + extract, several GB) at native speed.
#
# Output: $WORK/rootfs, plus a cached tarball keyed on the inputs so that
# iterating on the overlay or the image layout does not re-download GNOME.
set -euo pipefail

PROFILE_DIR="$1"
WORK="$2"
CACHE="${3:-}"

ROOTFS="$WORK/rootfs"
PACCONF="$PROFILE_DIR/pacman.conf"
PKGLIST="$PROFILE_DIR/packages.list"

mapfile -t packages < <(grep -vE '^\s*(#|$)' "$PKGLIST")

# Cache key: anything that changes the package set. The repo database is
# included so a rebuilt local package invalidates the cache.
key="$(
    { cat "$PKGLIST" "$PACCONF"; cat /repo/fyde/aarch64/fyde.db 2>/dev/null; } \
    | sha256sum | cut -c1-16
)"
TARBALL="${CACHE:+$CACHE/rootfs-$key.tar.zst}"

if [ -n "$TARBALL" ] && [ -s "$TARBALL" ]; then
    echo "==> reusing cached bootstrap $key"
    rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"
    tar -I zstd -xf "$TARBALL" -C "$ROOTFS"
    exit 0
fi

echo "==> pacstrap ${#packages[@]} packages into $ROOTFS"
rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"

# -C  use our pacman.conf (Architecture = aarch64)
# -M  do not copy the host mirrorlist into the target
# -G  do not copy the host pacman keyring into the target; 50-keyring.sh builds
#     a fresh one inside the target instead
# -c  use the shared package cache rather than one inside the target
pacstrap -C "$PACCONF" -M -G -c "$ROOTFS" "${packages[@]}"

if [ -n "$TARBALL" ]; then
    echo "==> caching bootstrap as $(basename "$TARBALL")"
    mkdir -p "$(dirname "$TARBALL")"
    tar -I 'zstd -3 -T0' -cf "$TARBALL.part" -C "$ROOTFS" .
    mv "$TARBALL.part" "$TARBALL"
fi

echo "==> bootstrap complete"
