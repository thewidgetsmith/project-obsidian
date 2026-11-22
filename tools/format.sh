#!/usr/bin/env bash
# tools/format.sh — run only the format step of tools/verify.sh. Takes the same
# arguments (boards, --fix, --all-files); see tools/verify.sh --help.
exec "$(dirname "${BASH_SOURCE[0]}")/verify.sh" --only format "$@"
