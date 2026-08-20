#!/usr/bin/env bash
# Stage 4: verify the assembled image, then compress and record what it contains.
#
# The verification is deliberately part of publishing rather than optional: an
# image that fails these checks cannot boot, and none of them need a device.
set -euo pipefail

PROFILE_DIR="$1"
WORK="$2"
IMG="$3"
OUT="$4"

ROOTFS="$WORK/rootfs"
source "$PROFILE_DIR/image.conf"
SECTOR=512
root_offset=$((PART_ROOT_START * SECTOR))
esp_offset=$((PART_ESP_START * SECTOR))
name="$(basename "$IMG" .img)"

mkdir -p "$OUT"

echo "==> verifying partition table"
sgdisk -p "$IMG" | sed 's/^/    /'
sgdisk -p "$IMG" | grep -qE "^ +1 +${PART_FW_START} +${PART_FW_END} .*FW" \
    || { echo "!! partition 1 (FW) is not where image.conf says" >&2; exit 1; }
sgdisk -p "$IMG" | grep -qE "^ +2 +${PART_ESP_START} +${PART_ESP_END} .*ESP" \
    || { echo "!! partition 2 (ESP) is not where boot.cmd expects it" >&2; exit 1; }
sgdisk -p "$IMG" | grep -qE "^ +3 +${PART_ROOT_START} .*ROOTFS" \
    || { echo "!! partition 3 (ROOTFS) is not where boot.cmd expects it" >&2; exit 1; }
# u-boot's distro scan only considers partitions with the legacy-boot GPT
# attribute; without it the SD is skipped and the device boots from eMMC.
sgdisk -A 2:show "$IMG" | grep -q "legacy BIOS bootable" \
    || { echo "!! the ESP lacks the legacy_boot attribute -- u-boot will skip this medium" >&2; exit 1; }

echo "==> verifying bootloader blobs landed at their sectors"
check_blob() {
    local file="$1" lba="$2" size
    size="$(stat -c%s "$file")"
    if cmp -s -n "$size" <(dd if="$IMG" bs=$SECTOR skip="$lba" count=$(( (size + SECTOR - 1) / SECTOR )) status=none) "$file"; then
        echo "    ok  $(basename "$file") at LBA $lba"
    else
        echo "!! $(basename "$file") does not match the image at LBA $lba" >&2
        exit 1
    fi
}
check_blob "$PROFILE_DIR/firmware/idblock.bin"  "$UBOOT_IDBLOCK_LBA"
check_blob "$PROFILE_DIR/firmware/uboot.img"    "$UBOOT_IMG_LBA"
check_blob "$PROFILE_DIR/firmware/resource.img" "$UBOOT_RESOURCE_LBA"

echo "==> verifying boot files inside the ESP"
# The ESP's filesystem root is /boot once mounted, so image.conf's rootfs-tree
# paths lose that prefix here.
for f in "${KERNEL_IMAGE#/boot}" "${KERNEL_INITRAMFS#/boot}" "${KERNEL_DTB#/boot}" /boot.scr; do
    if mdir -i "$IMG@@$esp_offset" "::$f" >/dev/null 2>&1; then
        echo "    ok  $f"
    else
        echo "!! $f is missing from the ESP -- u-boot would not find it" >&2
        exit 1
    fi
done

if [ "$ROOT_FS" = "btrfs" ]; then
    echo "==> verifying the btrfs superblock landed at the root partition"
    # The primary superblock sits 64 KiB into the filesystem, its magic 64 bytes
    # in. Reading it out of the assembled image is what proves the dd landed on
    # the partition boundary rather than beside it.
    magic="$(dd if="$IMG" bs=1 skip=$(( root_offset + 65536 + 64 )) count=8 status=none)"
    [ "$magic" = "_BHRfS_M" ] \
        || { echo "!! no btrfs superblock at offset $(( root_offset + 65536 ))" >&2; exit 1; }
    echo "    ok  _BHRfS_M at offset $(( root_offset + 65536 + 64 ))"

    rootfs_img="$WORK/rootfs-btrfs.img"
    [ -s "$rootfs_img" ] \
        || { echo "!! $rootfs_img is missing -- stage 3 must keep it for the checks below" >&2; exit 1; }
fi

# btrfs restore matches --path-regex against every path it walks, parents
# included, so the expression has to accept each prefix as well as the file.
path_regex() {
    local out='' close='' part
    local IFS=/
    for part in $1; do
        [ -n "$part" ] || continue
        out="$out(|${close:+/}${part//./\\.}"
        close="$close)"
    done
    printf '^/%s%s$' "$out" "$close"
}

# One presence test for both root filesystems. debugfs reads the ext4 in place
# at its partition offset; btrfs-progs takes no offset argument, so the btrfs
# side reads the separate filesystem file stage 3 kept, where the root's files
# live under @/.
rootfs_has() {
    local path="$1"
    if [ "$ROOT_FS" = "btrfs" ]; then
        # -S because restore skips symbolic links without it, and one of the two
        # mali firmware paths is a symlink to the other. A restored symlink is
        # dangling on its own, hence the -L arm.
        local tmp rc=0
        tmp="$(mktemp -d)"
        btrfs restore -S --path-regex "$(path_regex "@$path")" "$rootfs_img" "$tmp" >/dev/null 2>&1 || true
        [ -s "$tmp/@$path" ] || [ -L "$tmp/@$path" ] || rc=1
        rm -rf "$tmp"
        return "$rc"
    fi
    debugfs -R "stat $path" "$IMG?offset=$root_offset" 2>/dev/null | grep -q "Inode:"
}

echo "==> verifying fstab inside the root filesystem"
rootfs_has /etc/fstab \
    || { echo "!! /etc/fstab is missing from the root filesystem" >&2; exit 1; }
echo "    ok  /etc/fstab"

echo "==> verifying GPU firmware is where panthor looks for it"
# Shipped by linux-firmware-other: arch10.8 is a symlink to ../arch10.10/.
# Upstream panthor has no fallback to the bare name, so a missing file here
# means no GPU -- reported, misleadingly, as
# "Failed to load firmware image 'mali_csffw.bin'".
for f in /usr/lib/firmware/arm/mali/arch10.8/mali_csffw.bin \
         /usr/lib/firmware/arm/mali/arch10.10/mali_csffw.bin; do
    if rootfs_has "$f"; then
        echo "    ok  $f"
    else
        echo "!! $f missing -- the GPU will not init" >&2
        exit 1
    fi
done

echo "==> writing package manifest"
manifest="$OUT/$name.manifest"
{
    echo "# $name"
    echo "# packages installed in this image, as recorded by the target's pacman db"
    ls "$ROOTFS/var/lib/pacman/local" | grep -v '^ALPM_DB_VERSION$' | sort
} > "$manifest"
echo "    $(grep -cv '^#' "$manifest") packages -> $(basename "$manifest")"

echo "==> compressing"
xz -T0 -9 -f -k --verbose "$IMG"
mv "$IMG.xz" "$OUT/$name.img.xz"

( cd "$OUT" && sha256sum "$name.img.xz" "$name.manifest" > "$name.sha256" )
echo "==> published:"
ls -lh "$OUT/$name".* | sed 's/^/    /'
cat "$OUT/$name.sha256" | sed 's/^/    /'
