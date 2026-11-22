#!/usr/bin/env bash
#
# tools/diff.sh — a review-sized diff for agents.
#
# Usage: tools/diff.sh [RANGE] [PATH]
#   RANGE  git range, e.g. HEAD (uncommitted work, the default), HEAD~1,
#          origin/main...HEAD
#   PATH   limit to one file or directory
#
# Skips generated files (sdkconfig*, compile_commands.json, .pio/). For RANGE
# HEAD, new untracked files are included. If the diff is longer than
# DIFF_MAX_LINES (default 400) and no PATH is given, prints only the file list
# with line counts: then read one file at a time with `tools/diff.sh RANGE PATH`.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

range="${1:-HEAD}"
path="${2:-.}"
max="${DIFF_MAX_LINES:-400}"
exclude=(':(exclude,glob)**/sdkconfig*' ':(exclude,glob)**/compile_commands.json'
         ':(exclude,glob)**/.pio/**' ':(exclude)reference')

untracked=()
if [ "$range" = HEAD ]; then
    while IFS= read -r f; do
        [ -f "$f" ] && [ ! -L "$f" ] && untracked+=("$f")
    done < <(git ls-files --others --exclude-standard -- "$path" "${exclude[@]}")
fi

full() {
    git diff --no-color "$range" -- "$path" "${exclude[@]}"
    local f
    for f in "${untracked[@]}"; do
        git diff --no-color --no-index /dev/null "$f"
    done
}

lines=$(full | wc -l)
if [ "$lines" -eq 0 ]; then
    echo "diff: no changes in $range${2:+ for $path}"
    exit 0
fi
if [ "$lines" -le "$max" ] || [ -n "${2:-}" ]; then
    full | cut -c 1-240
    exit 0
fi
echo "diff: $lines lines in $range; read one file at a time: tools/diff.sh $range <path>"
git diff --numstat "$range" -- "$path" "${exclude[@]}" | awk '{printf "  +%-5s -%-5s %s\n", $1, $2, $3}'
for f in "${untracked[@]}"; do
    printf '  +%-5s -%-5s %s (new)\n' "$(wc -l <"$f")" 0 "$f"
done
