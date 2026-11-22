#!/usr/bin/env bash
#
# tools/pr.sh — open a pull request for the current branch.
#
# Usage: tools/pr.sh "TITLE" BODY_FILE
#
# Uses `gh` (GitHub) or `tea` (Gitea), whichever is installed and logged in.
# The branch must already be pushed (git push -u origin HEAD). Prints the PR
# URL on success. Exit 3 means no PR tool is available: the human opens the PR.

set -uo pipefail
title="${1:?usage: tools/pr.sh TITLE BODY_FILE}"
body="${2:?usage: tools/pr.sh TITLE BODY_FILE}"
[ -f "$body" ] || { echo "pr: body file not found: $body"; exit 2; }
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" != main ] || { echo "pr: on main; refusing"; exit 2; }

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh pr create --base main --head "$branch" --title "$title" --body-file "$body"
elif command -v tea >/dev/null 2>&1; then
    tea pr create --base main --head "$branch" --title "$title" --description "$(cat "$body")"
else
    echo "pr: no PR tool (gh or tea) available. Branch '$branch' is pushed;"
    echo "pr: the human must open the PR (title: $title, body: $body)."
    exit 3
fi
