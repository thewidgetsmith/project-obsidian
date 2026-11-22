# tools/lib/env.sh — shared setup for the tools/ shell scripts. Source it; don't run it.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
#   toolbox_reexec "$@"      # re-run this script inside the toolbox if needed
#
# The checks need the tools baked into the toolbox image
# (tools/container/Containerfile). Agents and editors usually run on the host,
# so a script started on the host re-executes itself inside the
# `obsidian-dev` distrobox. Inside the image (distrobox or CI) it runs
# directly.
#
# Environment:
#   OBSIDIAN_BOX=<name>     distrobox to use (default: obsidian-dev)
#   OBSIDIAN_HOST_TOOLS=1   run on the host, taking every tool from PATH
#   PLATFORMIO_CORE_DIR     PlatformIO packages and toolchains (default:
#                           ~/.cache/obsidian/platformio, shared by all
#                           worktrees and kept across container rebuilds)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OBSIDIAN_BOX="${OBSIDIAN_BOX:-obsidian-dev}"

export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-$HOME/.cache/obsidian/platformio}"
export PLATFORMIO_SETTING_ENABLE_TELEMETRY=no
export PLATFORMIO_DISABLE_PROGRESSBAR=true

in_toolbox() { [ -f /etc/obsidian-toolbox ]; }

# distrobox shares $HOME, so host installs (~/.local/bin/pio, nvm) could
# shadow the pinned toolbox versions. Put the image's tools first.
if in_toolbox; then
    export PATH="/opt/platformio/bin:/usr/local/bin:/usr/bin:$PATH"
fi

# toolbox_reexec ARGS... — if not in the toolbox, exec the calling script
# inside it with the same arguments. Returns normally when already inside.
toolbox_reexec() {
    in_toolbox && return 0
    [ "${OBSIDIAN_HOST_TOOLS:-0}" = 1 ] && return 0
    local self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    if ! command -v distrobox >/dev/null 2>&1; then
        echo "$(basename "$0"): not in the toolbox and distrobox is not installed." >&2
        echo "  Set up: tools/container.sh create   (or OBSIDIAN_HOST_TOOLS=1 to use host tools)" >&2
        exit 127
    fi
    if ! distrobox list --no-color 2>/dev/null | grep -qE "\|\s*${OBSIDIAN_BOX}\s*\|"; then
        echo "$(basename "$0"): distrobox '${OBSIDIAN_BOX}' not found. Run: tools/container.sh create" >&2
        exit 127
    fi
    local tty=()
    [ -t 0 ] && [ -t 1 ] || tty=(--no-tty)
    exec distrobox enter "${tty[@]}" --name "$OBSIDIAN_BOX" -- \
        env OBSIDIAN_BOX="$OBSIDIAN_BOX" PLATFORMIO_CORE_DIR="$PLATFORMIO_CORE_DIR" \
        bash -c 'cd "$1" && shift && exec "$@"' _ "$PWD" "$self" "$@"
}
