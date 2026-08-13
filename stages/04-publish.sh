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
name="$(basename "$IMG" .img)"

mkdir -p "$OUT"

echo "==> verifying partition table"
sgdisk -p "$IMG" | sed 's/^/    /'
sgdisk -p "$IMG" | grep -qE "^ +1 +${PART_FW_START} +${PART_FW_END} .*FW" \
    || { echo "!! partition 1 (FW) is not where image.conf says" >&2; exit 1; }
sgdisk -p "$IMG" | grep -qE "^ +2 +${PART_ROOT_START} .*ROOTFS" \
    || { echo "!! partition 2 (ROOTFS) is not where boot.cmd expects it" >&2; exit 1; }
# u-boot's distro scan only considers partitions with the legacy-boot GPT
# attribute; without it the SD is skipped and the device boots from eMMC.
sgdisk -A 2:show "$IMG" | grep -q "legacy BIOS bootable" \
    || { echo "!! ROOTFS lacks the legacy_boot attribute -- u-boot will skip this medium" >&2; exit 1; }

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

echo "==> verifying boot files inside the filesystem"
for f in "$KERNEL_IMAGE" "$KERNEL_INITRAMFS" "$KERNEL_DTB" /boot/boot.scr /etc/fstab; do
    if debugfs -R "stat $f" "$IMG?offset=$root_offset" 2>/dev/null | grep -q "Inode:"; then
        echo "    ok  $f"
    else
        echo "!! $f is missing from the root filesystem" >&2
        exit 1
    fi
done

echo "==> verifying GPU firmware is where panthor looks for it"
# Shipped by linux-firmware-other: arch10.8 is a symlink to ../arch10.10/.
# Upstream panthor has no fallback to the bare name, so a missing file here
# means no GPU -- reported, misleadingly, as
# "Failed to load firmware image 'mali_csffw.bin'".
for f in /usr/lib/firmware/arm/mali/arch10.8/mali_csffw.bin \
         /usr/lib/firmware/arm/mali/arch10.10/mali_csffw.bin; do
    if debugfs -R "stat $f" "$IMG?offset=$root_offset" 2>/dev/null | grep -q "Inode:"; then
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
