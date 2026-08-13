#!/usr/bin/env bash
# Stage 2: apply the overlay, fix permissions, run the chroot hooks.
# Runs inside the x86_64 container; the hooks themselves execute aarch64
# binaries through binfmt.
set -euo pipefail

PROFILE_DIR="$1"
WORK="$2"

ROOTFS="$WORK/rootfs"
source "$PROFILE_DIR/image.conf"

echo "==> applying overlay"
cp -a "$PROFILE_DIR/overlay/." "$ROOTFS/"

echo "==> applying perms.list"
while read -r path uid gid mode; do
    [ -z "${path:-}" ] && continue
    case "$path" in \#*) continue ;; esac

    target="$ROOTFS${path%/}"
    if [ ! -e "$target" ]; then
        echo "!! perms.list: $path does not exist in the rootfs" >&2
        exit 1
    fi
    # Refuse to follow a symlink out of the rootfs.
    real="$(realpath -m "$target")"
    case "$real" in
        "$(realpath -m "$ROOTFS")"*) ;;
        *) echo "!! perms.list: $path escapes the rootfs" >&2; exit 1 ;;
    esac

    if [ "${path: -1}" = "/" ]; then
        chown -Rh "$uid:$gid" "$target"
    else
        chown -h "$uid:$gid" "$target"
    fi
    chmod "$mode" "$target"
done < "$PROFILE_DIR/perms.list"

echo "==> seeding user homes from /etc/skel"
while IFS=: read -r user _ uid gid _ home _; do
    [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ] || continue
    [ -n "$home" ] || continue
    mkdir -p "$ROOTFS$home"
    cp -rT "$ROOTFS/etc/skel" "$ROOTFS$home" 2>/dev/null || true
    chown -R "$uid:$gid" "$ROOTFS$home"
done < "$ROOTFS/etc/passwd"

echo "==> running chroot hooks (emulated aarch64)"
for hook in "$PROFILE_DIR"/hooks/*.sh; do
    [ -f "$hook" ] || continue
    name="$(basename "$hook")"
    echo "    --- $name"
    # NOT under /tmp or /run: arch-chroot mounts fresh tmpfs over both, which
    # hides anything installed there first ("No such file or directory" from
    # chroot for a file that plainly exists).
    install -Dm755 "$hook" "$ROOTFS/.imagebuild-hook.sh"
    arch-chroot "$ROOTFS" /.imagebuild-hook.sh
    rm -f "$ROOTFS/.imagebuild-hook.sh"
done

# A machine-id baked into an image makes every device identical on the network.
# systemd regenerates it on first boot when the file is absent.
echo "==> clearing machine-id"
rm -f "$ROOTFS/etc/machine-id" "$ROOTFS/var/lib/dbus/machine-id"

echo "==> verifying boot artifacts"
for f in "$KERNEL_IMAGE" "$KERNEL_INITRAMFS" "$KERNEL_DTB"; do
    if [ ! -s "$ROOTFS$f" ]; then
        echo "!! missing $f -- boot.cmd loads it, the image would not boot" >&2
        exit 1
    fi
    echo "    ok  $f  ($(stat -c%s "$ROOTFS$f") bytes)"
done

echo "==> customize complete"
