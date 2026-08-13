#!/usr/bin/env bash
# Stage 3: assemble the disk image.
#
# No loop device and no mount anywhere: the GPT is written to a plain file with
# sgdisk, the bootloader blobs are dd'd to fixed sectors, and the root
# filesystem is created directly inside the file with `mke2fs -E offset=`,
# populated from the rootfs tree with -d. That is what makes this stage work
# reliably inside a container and on a CI runner.
set -euo pipefail

PROFILE_DIR="$1"
WORK="$2"
IMG="$3"

ROOTFS="$WORK/rootfs"
source "$PROFILE_DIR/image.conf"

SECTOR=512
root_offset=$((PART_ROOT_START * SECTOR))

echo "==> compiling boot.cmd -> /boot/boot.scr (rockchip script dialect)"
# NOT plain mkimage: this device's u-boot expects Rockchip's 0xffffffff size
# table terminator; upstream mkimage's zero terminator makes it execute garbage.
# See the header of mk-rk-script.py for the full story.
python3 "$(dirname "${BASH_SOURCE[0]}")/mk-rk-script.py" \
        "$PROFILE_DIR/boot/boot.cmd" "$ROOTFS/boot/boot.scr" "FydeTab Duo boot"

# Size the filesystem from the populated tree plus the configured slack.
# resizefs.service grows it to the medium on first boot.
used_kib="$(du -sk --exclude=proc "$ROOTFS" | cut -f1)"
root_mib=$(( used_kib / 1024 + SLACK_MIB ))
total_mib=$(( root_mib + PART_ROOT_START * SECTOR / 1024 / 1024 + 2 ))
echo "==> rootfs ${used_kib} KiB + ${SLACK_MIB} MiB slack -> ${root_mib} MiB root, ${total_mib} MiB image"

rm -f "$IMG"
truncate -s "${total_mib}M" "$IMG"

echo "==> writing GPT"
# p1 reserves the bootloader region so nothing else claims those sectors.
# p2 must be partition 2 -- boot.cmd hardcodes 'setenv rootpart 2'.
#
# -A 2:set:2 sets GPT attribute bit 2 (legacy BIOS bootable) on ROOTFS. The
# device's rockchip u-boot picks boot partitions with `part list -bootable`;
# without this flag its scan falls back to partition 1 -- the raw FW region --
# fails with "Unrecognized filesystem type", skips the SD entirely and boots
# whatever is on the eMMC instead. Verified against a serial log of exactly
# that failure (2026-08-13).
sgdisk -a 1 \
    -n "1:${PART_FW_START}:${PART_FW_END}" -c 1:FW     -t 1:8300 \
    -n "2:${PART_ROOT_START}:0"            -c 2:ROOTFS -t 2:8300 \
    -A 2:set:2 \
    "$IMG" > /dev/null
sgdisk -p "$IMG" | sed 's/^/    /'

echo "==> writing bootloader blobs"
write_blob() {
    local file="$1" lba="$2"
    [ -s "$file" ] || { echo "!! missing blob $file" >&2; exit 1; }
    dd if="$file" of="$IMG" bs=$SECTOR seek="$lba" conv=notrunc,fdatasync status=none
    echo "    $(basename "$file") -> LBA $lba ($(stat -c%s "$file") bytes)"
}
write_blob "$PROFILE_DIR/firmware/idblock.bin"  "$UBOOT_IDBLOCK_LBA"
write_blob "$PROFILE_DIR/firmware/uboot.img"    "$UBOOT_IMG_LBA"
write_blob "$PROFILE_DIR/firmware/resource.img" "$UBOOT_RESOURCE_LBA"

# The blobs must not reach into the root partition.
res_end=$(( UBOOT_RESOURCE_LBA + ($(stat -c%s "$PROFILE_DIR/firmware/resource.img") + SECTOR - 1) / SECTOR ))
if [ "$res_end" -ge "$PART_ROOT_START" ]; then
    echo "!! bootloader region ends at LBA $res_end, overlapping root at $PART_ROOT_START" >&2
    exit 1
fi

# Choose the filesystem UUID up front so fstab can be written into the tree
# before mke2fs copies it in -- otherwise the UUID only exists after the
# filesystem does, and fstab would have to be patched in afterwards.
uuid="$(uuidgen)"
echo "==> writing fstab (root UUID=$uuid)"
# boot.cmd passes root=PARTUUID from u-boot, so this line governs mount options
# and fsck ordering rather than finding the device.
printf 'UUID=%s  /  ext4  rw,relatime  0  1\n' "$uuid" > "$ROOTFS/etc/fstab"

echo "==> creating ext4 at offset $root_offset and populating from rootfs"
mke2fs -q -t ext4 -L ROOTFS -U "$uuid" \
    -E "offset=$root_offset" \
    -d "$ROOTFS" \
    -F "$IMG" "${root_mib}M"

echo "==> image assembled: $IMG"
