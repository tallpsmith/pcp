#!/bin/sh
# Phase 8: Show commits between two run SHAs to assess impact.
# Usage: qa-commit-delta.sh <repo-path> [from-sha [to-sha]]
# If from-sha omitted: shows last 10 commits on HEAD.
# If to-sha omitted: defaults to HEAD.
# Outputs: one-line git log entries

REPO_PATH="${1:?Usage: qa-commit-delta.sh <repo-path> [from-sha [to-sha]]}"
FROM_SHA="${2:-}"
TO_SHA="${3:-HEAD}"

if [ -n "$FROM_SHA" ]; then
    git -C "$REPO_PATH" log --oneline "${FROM_SHA}..${TO_SHA}" 2>/dev/null
else
    git -C "$REPO_PATH" log --oneline -10 "$TO_SHA" 2>/dev/null
fi
