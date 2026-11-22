#!/usr/bin/env bash
#
# tools/outline.sh — the shape of a file with line numbers, so agents can read
# only the range they need.
#
# Usage: tools/outline.sh FILE
#   C/C++: section rulers, #define, types, and function definitions/declarations
#   Markdown: headings     Other: line count and the first 20 lines
# At most OUTLINE_MAX_LINES (default 80) lines.

set -uo pipefail
f="${1:?usage: tools/outline.sh FILE}"
[ -f "$f" ] || { echo "outline: no such file: $f"; exit 1; }
max="${OUTLINE_MAX_LINES:-80}"
echo "$f: $(wc -l <"$f") lines"
case "$f" in
    *.c | *.cpp | *.h | *.hpp | *.ino)
        grep -nE '^// ─── |^#define [A-Z_]+|^(typedef |struct |enum |class |namespace )|^[A-Za-z_][A-Za-z0-9_:<>*& ,]*[ *&]+[A-Za-z_][A-Za-z0-9_:]*\([^;]*$|^[A-Za-z_][A-Za-z0-9_:<>*& ,]*[ *&]+[A-Za-z_][A-Za-z0-9_:]*\(.*\);' "$f" |
            grep -vE '^[0-9]+:\s*(return|if|else|for|while|switch)\b' | cut -c 1-160 | head -n "$max"
        ;;
    *.md) grep -nE '^#{1,6} ' "$f" | head -n "$max" ;;
    *) head -n 20 "$f" | cut -c 1-160 ;;
esac
