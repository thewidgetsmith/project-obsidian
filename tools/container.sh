#!/usr/bin/env bash
#
# tools/container.sh — build and manage the toolbox (the image every check runs in).
#
# Usage: tools/container.sh COMMAND
#   build     build the image localhost/obsidian-dev:latest with podman
#   create    build, then create the `obsidian-dev` distrobox from it and
#             prefetch the PlatformIO platforms (first run: several minutes)
#   recreate  remove the distrobox, then `create` (after a Containerfile change)
#   prefetch  install the PlatformIO platforms/toolchains into PLATFORMIO_CORE_DIR
#   enter     open a shell in the toolbox
#   status    show the image, the distrobox and the pinned tool versions
#   remove    remove the distrobox (the image and PLATFORMIO_CORE_DIR stay)
#
# The tools/ scripts enter the toolbox on their own; you only need this for
# setup. Environment: OBSIDIAN_BOX (default obsidian-dev), CONTAINER_ENGINE
# (default podman).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"

IMAGE="localhost/obsidian-dev:latest"
ENGINE="${CONTAINER_ENGINE:-podman}"

usage() { sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; }

have_box() { distrobox list --no-color 2>/dev/null | grep -qE "\|\s*${OBSIDIAN_BOX}\s*\|"; }

build() {
    echo "== Building $IMAGE"
    local log="$ROOT/.verify/container-build.log"
    mkdir -p "$ROOT/.verify"
    if ! "$ENGINE" build -t "$IMAGE" -f "$ROOT/tools/container/Containerfile" \
        "$ROOT/tools/container" >"$log" 2>&1; then
        tail -n 30 "$log"
        echo "build FAILED (full log: ${log#"$ROOT"/})"
        exit 1
    fi
    echo "image OK"
}

prefetch() {
    if ! in_toolbox; then
        exec distrobox enter --name "$OBSIDIAN_BOX" -- \
            env PLATFORMIO_CORE_DIR="$PLATFORMIO_CORE_DIR" "$ROOT/tools/container.sh" prefetch
    fi
    echo "== Prefetching PlatformIO packages into $PLATFORMIO_CORE_DIR"
    mkdir -p "$PLATFORMIO_CORE_DIR"
    local found=0 ini
    for ini in "$ROOT"/firmware/*/platformio.ini; do
        [ -f "$ini" ] || continue
        found=1
        pio pkg install -d "$(dirname "$ini")" >/dev/null ||
            echo "warning: package install failed for $(dirname "$ini")"
    done
    if [ "$found" -eq 0 ]; then
        # shellcheck source=container/versions.env
        source "$ROOT/tools/container/versions.env"
        pio pkg install -g --platform "espressif32@$ESPRESSIF32_VERSION" \
            --platform "atmelavr@$ATMELAVR_VERSION" --platform "native@$NATIVE_VERSION" >/dev/null ||
            echo "warning: platform install failed (retry: tools/container.sh prefetch)"
    fi
    echo "prefetch done"
}

create() {
    build
    if have_box; then
        echo "distrobox '$OBSIDIAN_BOX' already exists (use 'recreate' after an image change)"
    else
        echo "== Creating distrobox $OBSIDIAN_BOX"
        distrobox create --yes --name "$OBSIDIAN_BOX" --image "$IMAGE" \
            --additional-flags "--env PLATFORMIO_CORE_DIR=$PLATFORMIO_CORE_DIR"
        echo "== First start (distrobox installs its integration packages)"
        distrobox enter --name "$OBSIDIAN_BOX" -- true
    fi
    prefetch
    echo "Toolbox ready. Try: tools/verify.sh all --all-files"
}

case "${1:-}" in
    build) build ;;
    create) create ;;
    recreate)
        have_box && distrobox rm --force "$OBSIDIAN_BOX"
        create
        ;;
    prefetch) prefetch ;;
    enter) exec distrobox enter --name "$OBSIDIAN_BOX" ;;
    status)
        "$ENGINE" image inspect --format '{{.Id}} created {{.Created}}' "$IMAGE" 2>/dev/null |
            sed "s|^|image $IMAGE: |" || echo "image $IMAGE: missing (tools/container.sh build)"
        have_box && echo "distrobox $OBSIDIAN_BOX: present" ||
            echo "distrobox $OBSIDIAN_BOX: missing (tools/container.sh create)"
        echo "PLATFORMIO_CORE_DIR=$PLATFORMIO_CORE_DIR"
        have_box && distrobox enter --no-tty --name "$OBSIDIAN_BOX" -- cat /etc/obsidian-toolbox
        ;;
    remove) distrobox rm --force "$OBSIDIAN_BOX" ;;
    -h | --help | "") usage ;;
    *)
        echo "container.sh: unknown command '$1'" >&2
        usage >&2
        exit 2
        ;;
esac
