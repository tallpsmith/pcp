#!/bin/sh
# Phase 0: Detect git repo context for QA run analysis.
# Outputs LOCAL_REPO, BRANCH, REPO as KEY=VALUE lines.
# No arguments required — auto-detects from cwd.

LOCAL_REPO=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$LOCAL_REPO" ]; then
    echo "ERROR: Not in a git repository" >&2
    exit 1
fi

BRANCH=$(git branch --show-current 2>/dev/null)
[ -z "$BRANCH" ] && BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
if [ -z "$REPO" ]; then
    REMOTE_URL=$(git remote get-url origin 2>/dev/null)
    REPO=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/]([^/]+/[^/]+?)(\.git)?$|\1|')
fi

if [ -z "$REPO" ]; then
    echo "ERROR: Could not determine GitHub repo. Run: gh repo set-default" >&2
    exit 1
fi

echo "LOCAL_REPO=$LOCAL_REPO"
echo "BRANCH=$BRANCH"
echo "REPO=$REPO"
