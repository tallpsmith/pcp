#!/bin/sh
# Phase 1: List recent workflow runs for a repo.
# Usage: qa-find-runs.sh <repo> <workflow-file> [limit]
# Outputs: JSON array of runs (databaseId, conclusion, createdAt, headSha, headBranch, displayTitle)

REPO="${1:?Usage: qa-find-runs.sh <repo> <workflow-file> [limit]}"
WORKFLOW="${2:?Usage: qa-find-runs.sh <repo> <workflow-file>}"
LIMIT="${3:-5}"

gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --limit "$LIMIT" \
    --json databaseId,conclusion,createdAt,headSha,headBranch,displayTitle \
    2>/dev/null
