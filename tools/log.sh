#!/usr/bin/env bash
#
# tools/log.sh — show the errors of one tools/verify.sh step, with
# context, without dumping the whole log.
#
# Usage: tools/log.sh [STEP] [-n LINES] [-C CONTEXT]
#   STEP   build:xiao, test:atmega, lint:xiao, format, rules … (as printed by
#          verify.sh; "build-xiao" also works). Omit to list the logs.
#   -n     maximum lines to print (default 60)
#   -C     context lines around each error (default 3)
#   Lines longer than VERIFY_MAX_COLS (default 240) are cut.
#
# Prints the first errors in the step's log (the first one is usually the
# cause; later ones often cascade from it). Exit status is 1 if the log is
# missing.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/.verify"
max=60
ctx=3
cols="${VERIFY_MAX_COLS:-240}"
step=""

while [ $# -gt 0 ]; do
    case "$1" in
        -n)
            max=$2
            shift
            ;;
        -C)
            ctx=$2
            shift
            ;;
        -h | --help)
            sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) step=$1 ;;
    esac
    shift
done

if [ -z "$step" ]; then
    [ -f "$LOG_DIR/summary.txt" ] || {
        echo "log.sh: no .verify/summary.txt — run tools/verify.sh first"
        exit 1
    }
    grep -E '^(PASS|FAIL|SKIP|VERIFY)' "$LOG_DIR/summary.txt"
    exit 0
fi

log="$LOG_DIR/${step//:/-}.log"
if [ ! -f "$log" ]; then
    echo "log.sh: no log for '$step'. Available:" $(cd "$LOG_DIR" 2>/dev/null && ls -- *.log | sed 's/\.log$//')
    exit 1
fi

case "$step" in
    format*) pattern='error:|warning:' ;;
    rules* | secrets* | docs*) pattern='\] |: missing' ;;
    lint*) pattern='(error|warning|style|performance|portability):' ;;
    test*) pattern=':FAIL|FAILED|error:|undefined reference|Error [0-9]' ;;
    *) pattern='error:|warning:|undefined reference|Error [0-9]|CMake Error|FAILED:|fatal:|BUDGET:|not found' ;;
esac

total=$(grep -cE "$pattern" "$log")
if [ "$total" -eq 0 ]; then
    echo "log.sh: no error lines in ${log#"$ROOT"/}; last $max lines:"
    tail -n "$max" "$log" | cut -c "1-$cols"
    exit 0
fi

echo "${log#"$ROOT"/}: $total error lines; showing the first, with context"
grep -nE -B "$ctx" -A "$ctx" "$pattern" "$log" | head -n "$max" | cut -c "1-$cols"
shown=$(grep -nE -B "$ctx" -A "$ctx" "$pattern" "$log" | wc -l)
[ "$shown" -le "$max" ] || echo "... more — fix the first error, then re-run tools/verify.sh"
