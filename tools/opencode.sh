#!/usr/bin/env bash
#
# tools/opencode.sh — start OpenCode with the LiteLLM secrets loaded.
#
# Usage: tools/opencode.sh [opencode arguments...]
#
# opencode.json reads the LiteLLM endpoint and key as {env:LITELLM_BASE_URL}
# and {env:LITELLM_API_KEY}, so no secret is in the repo. This script loads
# them from OBSIDIAN_ENV_FILE (default
# ~/.config/litellm/obsidian.env; template:
# tools/obsidian.env.example) and starts OpenCode with --standalone, because
# OpenCode's background service would not see this shell's environment.

set -euo pipefail
env_file="${OBSIDIAN_ENV_FILE:-$HOME/.config/litellm/obsidian.env}"
if [ ! -f "$env_file" ]; then
    echo "opencode.sh: $env_file not found. Create it from tools/obsidian.env.example" >&2
    exit 2
fi
if [ -n "$(find "$env_file" -perm /077)" ]; then
    echo "opencode.sh: warning: $env_file is readable by others; run: chmod 600 $env_file" >&2
fi
set -a
# shellcheck disable=SC1090
source "$env_file"
set +a
for var in LITELLM_BASE_URL LITELLM_API_KEY; do
    [ -n "${!var:-}" ] || { echo "opencode.sh: $var is not set in $env_file" >&2; exit 2; }
done
exec opencode --standalone "$@"
