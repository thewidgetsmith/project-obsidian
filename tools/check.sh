#!/usr/bin/env bash
# tools/check.sh — the check command for agents: same as tools/verify.sh (same
# arguments, e.g. --fix, a board, --only). Ends with VERIFY PASS or VERIFY FAIL.
exec "$(dirname "${BASH_SOURCE[0]}")/verify.sh" "$@"
