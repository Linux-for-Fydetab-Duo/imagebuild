#!/usr/bin/env bash
# Stage 3: assemble the disk image.
#
# No loop device and no mount anywhere: the GPT is written to a plain file with
# sgdisk, the bootloader blobs are dd'd to fixed sectors, the ESP is built as a
# separate file with `mkfs.vfat` and filled with mtools, and the root filesystem
# is populated straight from the rootfs tree -- ext4 in place with
# `mke2fs -E offset= -d`, btrfs as a separate file with `mkfs.btrfs --rootdir`
# that is then dd'd to the partition offset. That is what makes this stage work
# reliably inside a container and on a CI runner.
set -euo pipefail

PROFILE_DIR="$1"
WORK="$2"
IMG="$3"

ROOTFS="$WORK/rootfs"
source "$PROFILE_DIR/image.conf"

SECTOR=512
root_offset=$((PART_ROOT_START * SECTOR))
esp_mib=$(( (PART_ESP_END - PART_ESP_START + 1) * SECTOR / 1024 / 1024 ))

echo "==> compiling boot.cmd -> /boot/boot.scr (rockchip script dialect)"
# NOT plain mkimage: this device's u-boot expects Rockchip's 0xffffffff size
# table terminator; upstream mkimage's zero terminator makes it execute garbage.
# See the header of mk-rk-script.py for the full story.
python3 "$(dirname "${BASH_SOURCE[0]}")/mk-rk-script.py" \
        "$PROFILE_DIR/boot/boot.cmd" "$ROOTFS/boot/boot.scr" "FydeTab Duo boot"

# /boot belongs to the ESP, so it is moved out of the tree the mkfs copies and
# only the empty mountpoint stays behind. The trap puts it back on any exit:
# stage 4 reads the tree afterwards, and a re-run must see it whole. The btrfs
# path below moves the whole tree once more, into staging/@, so the trap undoes
# both, innermost first.
bootfs="$WORK/bootfs"
staging="$WORK/btrfs-staging"
mv -T "$ROOTFS/boot" "$bootfs"
mkdir "$ROOTFS/boot"
restore_tree() {
    if [ -d "$staging/@" ]; then
        # Tolerant of a half-done restructure: only the mountpoints that were
        # actually emptied exist, and only the subvolume dirs that were filled.
        rmdir "$staging/@/.snapshots" "$staging/@/home" "$staging/@/var/log" \
              "$staging/@/var/cache/pacman/pkg" 2>/dev/null || true
        [ -d "$staging/@home" ] && mv -T "$staging/@home" "$staging/@/home"
        [ -d "$staging/@log" ] && mv -T "$staging/@log" "$staging/@/var/log"
        [ -d "$staging/@pkg" ] && mv -T "$staging/@pkg" "$staging/@/var/cache/pacman/pkg"
        mv -T "$staging/@" "$ROOTFS"
        rmdir "$staging"
    fi
    rmdir "$ROOTFS/boot" && mv -T "$bootfs" "$ROOTFS/boot"
}
trap restore_tree EXIT

boot_mib="$(du -sm "$bootfs" | cut -f1)"
# Margin covers the FAT32 metadata (two FATs, directory entries, cluster
# rounding) that shares the partition with the files.
if [ "$boot_mib" -gt $(( esp_mib - 16 )) ]; then
    echo "!! /boot is ${boot_mib} MiB, too big for the ${esp_mib} MiB ESP" >&2
    exit 1
fi

# Choose both filesystem identifiers up front so fstab can be written into the
# tree before the filesystems are populated from it -- otherwise they only
# exist after the filesystems do, and fstab would have to be patched in
# afterwards. mkfs.vfat takes the FAT volume id as eight hex digits; the
# kernel reports it, and fstab spells it, as two four-digit halves.
uuid="$(uuidgen)"
vol_id="$(uuidgen | tr -d '-' | cut -c1-8 | tr '[:lower:]' '[:upper:]')"
esp_uuid="${vol_id:0:4}-${vol_id:4:4}"

echo "==> writing fstab (root UUID=$uuid, ESP UUID=$esp_uuid)"
# boot.cmd passes root=PARTUUID from u-boot, so the root line governs mount
# options and fsck ordering rather than finding the device. FAT has no POSIX
# permissions: the umask is what keeps the files under /boot root-only.
# btrfs has no fsck to order (pass 0 everywhere) and its subvolumes are reached
# by mount option, not by device, so /home and /var/log get their own lines
# against the same UUID. Nested subvolumes -- .snapshots inside @ -- need none.
{
    if [ "$ROOT_FS" = "btrfs" ]; then
        # noatime,compress=zstd is the official Omarchy installer's option set
        # for every btrfs mount; the kernel mounts / with only rootflags from
        # boot.cmd and systemd applies these on the fstab remount.
        printf 'UUID=%s  /  btrfs  rw,noatime,compress=zstd,subvol=/@  0  0\n' "$uuid"
        printf 'UUID=%s  /boot  vfat  rw,relatime,fmask=0077,dmask=0077  0  2\n' "$esp_uuid"
        printf 'UUID=%s  /home  btrfs  rw,noatime,compress=zstd,subvol=/@home  0  0\n' "$uuid"
        printf 'UUID=%s  /var/log  btrfs  rw,noatime,compress=zstd,subvol=/@log  0  0\n' "$uuid"
        printf 'UUID=%s  /var/cache/pacman/pkg  btrfs  rw,noatime,compress=zstd,subvol=/@pkg  0  0\n' "$uuid"
    else
        printf 'UUID=%s  /  ext4  rw,relatime  0  1\n' "$uuid"
        printf 'UUID=%s  /boot  vfat  rw,relatime,fmask=0077,dmask=0077  0  2\n' "$esp_uuid"
    fi
} > "$ROOTFS/etc/fstab"

used_kib="$(du -sk --exclude=proc "$ROOTFS" | cut -f1)"
if [ "$ROOT_FS" = "btrfs" ]; then
    echo "==> restructuring the rootfs tree into btrfs subvolumes"
    # mkfs.btrfs --subvol takes directories of the --rootdir tree and turns them
    # into subvolumes, so the tree has to be shaped like the mounted system:
    # @ is the root with @home, @log and @pkg beside it (the official Omarchy
    # installer's set), and the emptied directories stay behind inside @ as the
    # mountpoints fstab needs.
    mkdir "$staging"
    mv -T "$ROOTFS" "$staging/@"
    mv -T "$staging/@/home" "$staging/@home"
    mv -T "$staging/@/var/log" "$staging/@log"
    mv -T "$staging/@/var/cache/pacman/pkg" "$staging/@pkg"
    install -d -o 0 -g 0 -m 755 "$staging/@/home" "$staging/@/var/log" \
                                "$staging/@/var/cache/pacman/pkg"
    # snapper's own convention for the snapshot store.
    install -d -o 0 -g 0 -m 750 "$staging/@/.snapshots"

    echo "==> creating btrfs from the tree (mkfs sizes itself, then shrinks)"
    # mkfs.btrfs cannot write at an offset the way mke2fs can, so the filesystem
    # is built as its own file and dd'd into place once the GPT exists. The file
    # is KEPT: btrfs-progs takes no offset argument either, so stage 4 verifies
    # its contents here. The size is mkfs's, not ours: its --rootdir estimator
    # over-reserves and it GROWS the file rather than fail when the given size
    # disagrees, so the file starts at a du-based estimate, --shrink trims it to
    # minimal, and the partition below is sized from what actually came out.
    # resizefs.service grows partition and filesystem to the medium on first
    # boot -- ordered into early boot, because a shrunk btrfs has only its
    # chunk tails free until then.
    rootfs_img="$WORK/rootfs-btrfs.img"
    rm -f "$rootfs_img"
    truncate -s "$(( used_kib / 1024 + SLACK_MIB ))M" "$rootfs_img"
    mkfs.btrfs --rootdir "$staging" --shrink \
        --subvol rw:@ --subvol rw:@home --subvol rw:@log --subvol rw:@pkg \
        --subvol rw:@/.snapshots \
        -L ROOTFS -U "$uuid" "$rootfs_img" | sed 's/^/    /'
    root_mib=$(( ($(stat -c%s "$rootfs_img") + 1024*1024 - 1) / 1024 / 1024 ))
    echo "==> rootfs ${used_kib} KiB -> ${root_mib} MiB shrunk btrfs"
else
    # Sized from the populated tree plus the configured slack; created in place
    # once the GPT exists. resizefs.service grows it to the medium on first boot.
    root_mib=$(( used_kib / 1024 + SLACK_MIB ))
    echo "==> rootfs ${used_kib} KiB + ${SLACK_MIB} MiB slack -> ${root_mib} MiB root"
fi
total_mib=$(( root_mib + PART_ROOT_START * SECTOR / 1024 / 1024 + 2 ))
echo "==> image size: ${total_mib} MiB"

rm -f "$IMG"
truncate -s "${total_mib}M" "$IMG"

echo "==> writing GPT"
# p1 reserves the bootloader region so nothing else claims those sectors. The
# ESP must be partition 2 and the root partition 3 -- boot.cmd hardcodes
# 'setenv bootpart 2' and 'setenv rootpart 3'.
#
# -A 2:set:2 sets GPT attribute bit 2 (legacy BIOS bootable) on the ESP. The
# device's rockchip u-boot picks boot partitions with `part list -bootable`;
# without this flag its scan falls back to partition 1 -- the raw FW region --
# fails with "Unrecognized filesystem type", skips the SD entirely and boots
# whatever is on the eMMC instead. Verified against a serial log of exactly
# that failure (2026-08-13).
sgdisk -a 1 \
    -n "1:${PART_FW_START}:${PART_FW_END}"   -c 1:FW     -t 1:8300 \
    -n "2:${PART_ESP_START}:${PART_ESP_END}" -c 2:ESP    -t 2:ef00 \
    -n "3:${PART_ROOT_START}:0"              -c 3:ROOTFS -t 3:8300 \
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

# The blobs must not reach into the ESP.
res_end=$(( UBOOT_RESOURCE_LBA + ($(stat -c%s "$PROFILE_DIR/firmware/resource.img") + SECTOR - 1) / SECTOR ))
if [ "$res_end" -ge "$PART_ESP_START" ]; then
    echo "!! bootloader region ends at LBA $res_end, overlapping the ESP at $PART_ESP_START" >&2
    exit 1
fi

echo "==> creating the ${esp_mib} MiB ESP and populating it from /boot"
esp="$WORK/esp.img"
rm -f "$esp"
truncate -s "${esp_mib}M" "$esp"
mkfs.vfat -F 32 -n ESP -i "$vol_id" "$esp" > /dev/null
mcopy -i "$esp" -s "$bootfs"/* ::/
dd if="$esp" of="$IMG" bs=$SECTOR seek="$PART_ESP_START" conv=notrunc,fdatasync status=none

if [ "$ROOT_FS" = "btrfs" ]; then
    echo "==> copying btrfs to offset $root_offset"
    dd if="$rootfs_img" of="$IMG" bs=$SECTOR seek="$PART_ROOT_START" \
        conv=notrunc,fdatasync status=none
else
    echo "==> creating ext4 at offset $root_offset and populating from rootfs"
    mke2fs -q -t ext4 -L ROOTFS -U "$uuid" \
        -E "offset=$root_offset" \
        -d "$ROOTFS" \
        -F "$IMG" "${root_mib}M"
fi

echo "==> image assembled: $IMG"
