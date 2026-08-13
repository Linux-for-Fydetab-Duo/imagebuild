#!/usr/bin/env bash
# FydeTab Duo image build -- single entry point.
#
#   ./build.sh containers            build/refresh the build containers
#   ./build.sh sync                  mirror not-locally-built packages into ./repo
#   ./build.sh pkg [name...]         build PKGBUILDs into ./repo
#   ./build.sh image [profile]       bootstrap -> customize -> assemble -> publish
#   ./build.sh all [profile]         containers, sync, pkg, image
#   ./build.sh shell [x86|arm64]     debug shell in a build container
#
# Everything runs in containers; the host needs only docker and a qemu-aarch64
# binfmt handler carrying the F flag.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG_X86="fydetab-build:x86"
IMG_ARM="fydetab-build:arm64"
DEFAULT_PROFILE="arch-gnome"

WORK="$PROJECT/work"
OUT="$PROJECT/out"
CACHE="$PROJECT/cache"
REPODIR="$PROJECT/repo/fyde/aarch64"

die() { echo "!! $*" >&2; exit 1; }

preflight() {
    command -v docker >/dev/null || die "docker not found"
    local bf=/proc/sys/fs/binfmt_misc/qemu-aarch64
    [ -r "$bf" ] || die "no qemu-aarch64 binfmt handler; install qemu-user-static (or run docker/setup-qemu-action in CI)"
    grep -q '^enabled' "$bf" || die "qemu-aarch64 binfmt handler is registered but disabled"
    grep -q '^flags:.*F' "$bf" || die \
"qemu-aarch64 binfmt handler lacks the F (fix-binary) flag.
Without it the interpreter is resolved inside the chroot, where it does not
exist, and every emulated hook fails with ENOENT. Re-register with F."
}

# Runs a command in the x86 container with the project bind-mounted.
# --privileged is needed for arch-chroot's bind mounts in stage 2.
in_x86() {
    docker run --rm --privileged \
        -v "$PROJECT:/work" \
        -v "$REPODIR:/repo/fyde/aarch64" \
        -v "$CACHE/pacman-pkg:/var/cache/pacman/pkg" \
        -w /work \
        "$IMG_X86" "$@"
}

cmd_containers() {
    preflight
    echo "==> building $IMG_X86"
    docker build -t "$IMG_X86" -f "$PROJECT/container/Dockerfile.x86" "$PROJECT/container"

    if ! docker image inspect fydetab-build:alarm-base >/dev/null 2>&1; then
        echo "==> creating the ALARM base (downloads ~830 MB on first run)"
        "$PROJECT/container/mk-alarm-base.sh"
    fi
    echo "==> building $IMG_ARM (emulated)"
    docker build --platform linux/arm64 -t "$IMG_ARM" \
        -f "$PROJECT/container/Dockerfile.arm64" "$PROJECT/container"
}

cmd_sync() { "$PROJECT/pkg/sync-published.sh"; }
cmd_pkg()  { preflight; "$PROJECT/pkg/build-pkg.sh" "$@"; }

cmd_image() {
    preflight
    local profile="${1:-$DEFAULT_PROFILE}"
    local pdir="/work/profiles/$profile"
    [ -d "$PROJECT/profiles/$profile" ] || die "no such profile: $profile"
    [ -s "$REPODIR/fyde.db" ] || die \
"./repo has no database. Run './build.sh sync' and './build.sh pkg' first --
the image needs the locally built linux-fydetab, and pacstrap cannot resolve
[fyde] without fyde.db."

    # shellcheck disable=SC1090
    source "$PROJECT/profiles/$profile/image.conf"
    local stamp name
    stamp="$(date +%Y-%m-%d)"
    # shellcheck disable=SC2059
    name="$(printf "$IMG_NAME_FMT" "$stamp")"

    mkdir -p "$WORK" "$OUT" "$CACHE/bootstrap" "$CACHE/pacman-pkg"

    in_x86 bash -c "
        set -euo pipefail
        stages/01-bootstrap.sh '$pdir' /work/work /work/cache/bootstrap
        stages/02-customize.sh '$pdir' /work/work
        stages/03-image.sh     '$pdir' /work/work '/work/work/$name.img'
        stages/04-publish.sh   '$pdir' /work/work '/work/work/$name.img' /work/out
    "
    echo "==> done: $OUT/$name.img.xz"
}

cmd_all() {
    cmd_containers
    cmd_sync
    cmd_pkg
    cmd_image "${1:-$DEFAULT_PROFILE}"
}

cmd_shell() {
    case "${1:-x86}" in
        x86)   in_x86 bash ;;
        arm64) docker run --rm -it --platform linux/arm64 -v "$PROJECT:/work" -w /work "$IMG_ARM" bash ;;
        *) die "usage: build.sh shell [x86|arm64]" ;;
    esac
}

case "${1:-}" in
    containers) shift; cmd_containers "$@" ;;
    sync)       shift; cmd_sync       "$@" ;;
    pkg)        shift; cmd_pkg        "$@" ;;
    image)      shift; cmd_image      "$@" ;;
    all)        shift; cmd_all        "$@" ;;
    shell)      shift; cmd_shell      "$@" ;;
    *) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 1 ;;
esac
