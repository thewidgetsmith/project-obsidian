#!/usr/bin/env bash
# tools/lint.sh — run only the lint step of tools/verify.sh. Takes the same
# arguments (boards, --fix, --all-files); see tools/verify.sh --help.
exec "$(dirname "${BASH_SOURCE[0]}")/verify.sh" --only lint "$@"
