#!/usr/bin/env bash
# Mirrors into ./repo the packages that the published fyde repo provides but
# this project does not build -- the ones with no PKGBUILD in ../pkgbuilds.
#
# The point is that ./repo becomes a COMPLETE replacement for the published
# repo, so the image resolves everything from one place and what you publish is
# exactly what you built the image from.
#
# Locally built packages are never overwritten: anything whose pkgbase this
# project builds is skipped, so a stale published linux-fydetab 6.1.75 cannot
# come back and shadow the local 6.12.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPODIR="$PROJECT/repo/fyde/aarch64"
CACHE="$PROJECT/cache"
MODES="$PROJECT/pkg/BUILDMODES"
UPSTREAM="https://deb-mirror.fydeos.com/pacman/repo/fyde/aarch64"

mkdir -p "$REPODIR" "$CACHE"

echo "==> fetching published database"
curl -fsSL -o "$CACHE/published-fyde.db" "$UPSTREAM/fyde.db"

# Package names this project builds locally.
#
# These must be resolved by SOURCING the PKGBUILD, not by pattern-matching it.
# Split packages name themselves through variables -- linux-fydetab-6.12 has
# `pkgbase=$_kernel` and `pkgname=("${pkgbase}-headers" $pkgbase)` -- so a regex
# extracts nothing at all, and the stale published linux-fydetab 6.1.75 would be
# synced in to shadow the locally built 6.12.43.
pkgnames_of() {
    (
        set +u
        cd "$PROJECT/pkgbuilds/$1" 2>/dev/null || exit 0
        # shellcheck disable=SC1091
        source ./PKGBUILD >/dev/null 2>&1 || exit 0
        printf '%s\n' "${pkgname[@]}" "${pkgbase:-}"
    ) | grep -v '^$'
}

locally_built=()
while read -r dir mode _; do
    [ -z "${dir:-}" ] && continue
    case "$dir" in \#*) continue ;; esac
    [ "$mode" = "skip" ] && continue
    [ -f "$PROJECT/pkgbuilds/$dir/PKGBUILD" ] || continue
    while read -r n; do locally_built+=("$n"); done < <(pkgnames_of "$dir")
done < "$MODES"

# If sourcing failed silently we would sync everything, including the stale
# kernel, and shadow the local build. Fail loudly instead.
if [ ${#locally_built[@]} -eq 0 ]; then
    echo "!! resolved no local package names from pkgbuilds/ -- refusing to sync" >&2
    exit 1
fi

is_local() {
    local candidate="$1" n
    for n in "${locally_built[@]}"; do
        [ "$candidate" = "$n" ] && return 0
    done
    return 1
}

# Published packages this image must NOT mirror:
#   grub, grub-btrfs     no UEFI here (u-boot + boot.scr boots the image);
#                        grub's epoch also breaks the CI rolling release,
#                        since GitHub sanitizes ':' in asset names.
#   mesa-panfork-git     pre-panthor stopgap, superseded by mesa/panvk.
#   python-imageforge    tool of the old imageforge flow this replaced.
#   voxtype-bin          removed 2026-08-19: does not work on the device.
dropped=(grub grub-btrfs mesa-panfork-git python-imageforge voxtype-bin)

is_dropped() {
    local candidate="$1" n
    for n in "${dropped[@]}"; do
        [ "$candidate" = "$n" ] && return 0
    done
    return 1
}

echo "==> locally built, will not sync: ${locally_built[*]}"

# Entry dirs in the db are <pkgname>-<pkgver>-<pkgrel>; %FILENAME% inside each
# desc gives the exact package file to fetch.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar xzf "$CACHE/published-fyde.db" -C "$tmp"

synced=0 skipped=0
for entry in "$tmp"/*/; do
    [ -f "$entry/desc" ] || continue
    name="$(awk '/^%NAME%$/{getline; print; exit}' "$entry/desc")"
    file="$(awk '/^%FILENAME%$/{getline; print; exit}' "$entry/desc")"
    [ -n "$name" ] && [ -n "$file" ] || continue

    if is_local "$name"; then
        echo "    skip  $name (built locally)"
        skipped=$((skipped + 1))
        continue
    fi
    if is_dropped "$name"; then
        echo "    drop  $name (obsolete for this image)"
        skipped=$((skipped + 1))
        continue
    fi
    if [ -s "$REPODIR/$file" ]; then
        echo "    have  $file"
        continue
    fi
    echo "    fetch $file"
    curl -fL --progress-bar -o "$REPODIR/$file.part" "$UPSTREAM/$file"
    mv "$REPODIR/$file.part" "$REPODIR/$file"
    synced=$((synced + 1))
done

echo "==> synced $synced, skipped $skipped locally-built"
echo "==> run pkg/build-pkg.sh (with no arguments) to refresh the database"
