#!/usr/bin/env bash
# Builds PKGBUILDs from ../pkgbuilds into ../repo/fyde/aarch64 and updates the
# repo database. Runs on the host; dispatches each package into the container
# its BUILDMODES entry calls for.
#
#   pkg/build-pkg.sh                  build every package that is not 'skip'
#   pkg/build-pkg.sh mutter ckbcomp   build just these
#   FORCE=1 pkg/build-pkg.sh mutter   rebuild even if the version is in the repo
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGBUILDS="$PROJECT/pkgbuilds"
REPODIR="$PROJECT/repo/fyde/aarch64"
DBNAME="fyde"
CACHE="$PROJECT/cache"
MODES="$PROJECT/pkg/BUILDMODES"

IMG_X86="fydetab-build:x86"
IMG_ARM="fydetab-build:arm64"

mkdir -p "$REPODIR" "$CACHE/srcdest" "$CACHE/pkgbuild-work"

mode_of() {
    local name="$1" dir m
    while read -r dir m _; do
        [ -z "${dir:-}" ] && continue
        case "$dir" in \#*) continue ;; esac
        [ "$dir" = "$name" ] && { echo "$m"; return 0; }
    done < "$MODES"
    return 1
}

# makepkg.conf fragment forcing aarch64 output regardless of the build host.
#
# Delivered as a drop-in to /etc/makepkg.conf.d/, NOT via `makepkg --config`:
# --config replaces the distro makepkg.conf outright, which would silently drop
# DLAGENTS, the COMPRESS* commands, CPPFLAGS and everything else. Drop-ins are
# sourced after the main config (see source_makepkg_config), so these override
# cleanly and nothing is lost.
write_makepkg_conf() {
    local out="$1" mode="$2"
    cat > "$out" <<'EOF'
CARCH="aarch64"
CHOST="aarch64-unknown-linux-gnu"
CFLAGS="-O2 -pipe -fno-plt"
CXXFLAGS="$CFLAGS"
BUILDENV=(!distcc color !ccache check !sign)
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug)
PKGEXT='.pkg.tar.zst'
SRCEXT='.src.tar.gz'
EOF
    echo "MAKEFLAGS=\"-j$(nproc)\"" >> "$out"
    if [ "$mode" = "cross" ]; then
        # The kernel Makefile reads these from the environment, so the PKGBUILD
        # needs no modification to cross-compile.
        cat >> "$out" <<'EOF'
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
EOF
    fi
}

build_one() {
    local name="$1" mode="$2"
    local src="$PKGBUILDS/$name"
    [ -d "$src" ] || { echo "!! no such PKGBUILD dir: $name" >&2; return 1; }

    local work="$CACHE/pkgbuild-work/$name"
    rm -rf "$work"; mkdir -p "$work"
    cp -a "$src/." "$work/"
    write_makepkg_conf "$CACHE/pkgbuild-work/$name.makepkg.conf" "$mode"

    local image run_as
    case "$mode" in
        cross|noarch) image="$IMG_X86"; run_as="builder" ;;
        emulated)     image="$IMG_ARM"; run_as="alarm"   ;;
        *) echo "!! unknown mode '$mode' for $name" >&2; return 1 ;;
    esac

    # makepkg --syncdeps cannot be used in any of our containers:
    #  - noarch builds on x86 name RUNTIME deps that only exist as aarch64
    #    packages (calamares), which x86 pacman cannot install -- and nothing
    #    is compiled, so they are not needed at build time anyway.
    #  - emulated builds cannot elevate: setuid sudo gains no privileges under
    #    qemu-user unless the binfmt registration carries the C (credentials)
    #    flag, and neither this host (POF) nor CI's setup-qemu-action sets it.
    #    "sudo: effective uid is not 0" from makepkg is this, not a sudoers
    #    problem.
    # So dependencies are installed by container ROOT before makepkg runs, and
    # makepkg itself runs with --nodeps. noarch installs only makedepends
    # (host tools); emulated installs depends+makedepends+checkdepends, which
    # are all real aarch64 packages the ALARM container can hold.
    local dep_flags="--syncdeps" pre_deps="" dep_arrays
    case "$mode" in
        noarch)   dep_arrays='"${makedepends[@]}"' ;;
        emulated) dep_arrays='"${depends[@]}" "${makedepends[@]}" "${checkdepends[@]}"' ;;
        *)        dep_arrays='' ;;
    esac
    if [ -n "$dep_arrays" ]; then
        dep_flags="--nodeps"
        # sed strips version constraints (pacman -S targets are plain names);
        # '|| true': a package with no makedepends makes grep exit 1, and under
        # set -e a failing substitution in an assignment kills the script
        # silently before it has printed anything.
        pre_deps="$(
            { cd "$work" && bash -c "set +u; source ./PKGBUILD >/dev/null 2>&1; printf '%s\n' $dep_arrays" \
                | sed 's/[<>=].*//' | grep -v '^$' | sort -u | tr '\n' ' '; } || true
        )"
    fi

    echo "==> building $name  (mode=$mode, image=$image)"
    docker run --rm \
        -v "$work:/build" \
        -v "$CACHE/pkgbuild-work/$name.makepkg.conf:/etc/makepkg.conf.d/99-fydetab.conf:ro" \
        -v "$CACHE/srcdest:/srcdest" \
        -v "$REPODIR:/out" \
        -e "SRCDEST=/srcdest" \
        -e "PKGDEST=/out" \
        -e "HOST_UID=$(id -u)" \
        -e "HOST_GID=$(id -g)" \
        -e "BUILD_MODE=$mode" \
        -w /build \
        "$image" \
        bash -c "
            set -euo pipefail
            # Emulated builds may depend on packages this project builds itself
            # (calamares -> ckbcomp), so the local repo must be resolvable
            # inside the container too. /out IS the bind-mounted repo dir.
            if [ \"\$BUILD_MODE\" = emulated ] && ! grep -q '^\[fyde\]' /etc/pacman.conf; then
                printf '\n[fyde]\nSigLevel = Never\nServer = file:///out\n' >> /etc/pacman.conf
            fi
            # Give the in-container build user the HOST's uid/gid before it
            # touches anything. /out is a bind mount of the project's repo/, so
            # chowning it to a container-local uid rewrites ownership of real
            # files in the user's tree -- on a multi-user host that hands the
            # directory to whoever happens to own that uid, and locks the actual
            # owner out of their own repo. Match the uid instead, and never
            # chown the bind-mounted output.
            groupmod -o -g \"\$HOST_GID\" $run_as 2>/dev/null || true
            usermod  -o -u \"\$HOST_UID\" -g \"\$HOST_GID\" $run_as
            chown -R $run_as /build /srcdest
            if [ -n '$pre_deps' ]; then
                pacman -Sy --noconfirm --needed $pre_deps
            fi
            runuser -u $run_as -- env HOME=/home/$run_as makepkg \
                ${FORCE:+--force} \
                $dep_flags --noconfirm --needed --ignorearch --clean
        "
}

repo_add_all() {
    echo '==> updating repo database'
    docker run --rm -v "$REPODIR:/out" -w /out \
        -e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)" \
        "$IMG_X86" bash -c "
        set -euo pipefail
        shopt -s nullglob
        pkgs=(*.pkg.tar.zst)
        [ \${#pkgs[@]} -gt 0 ] || { echo 'no packages in repo'; exit 0; }
        repo-add --quiet --new --remove '$DBNAME.db.tar.gz' \"\${pkgs[@]}\"
        # repo-add ran as root; hand its outputs to the host user so nothing
        # in the bind-mounted repo is owned by a foreign uid.
        chown -h \"\$HOST_UID:\$HOST_GID\" '$DBNAME'.db* '$DBNAME'.files*
    "
    # repo-add writes .db.tar.gz / .files.tar.gz and the bare symlinks; pacman
    # fetches the bare names, so both must be present when this is published.
    ls -la "$REPODIR" | sed 's/^/    /'
}

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
    mapfile -t targets < <(
        awk '$1 !~ /^#/ && NF >= 2 && $2 != "skip" { print $1 }' "$MODES"
    )
fi

for name in "${targets[@]}"; do
    mode="$(mode_of "$name")" || {
        echo "!! $name has no entry in pkg/BUILDMODES -- add one" >&2
        exit 1
    }
    [ "$mode" = "skip" ] && { echo "==> skipping $name (BUILDMODES: skip)"; continue; }
    build_one "$name" "$mode"
done

repo_add_all
