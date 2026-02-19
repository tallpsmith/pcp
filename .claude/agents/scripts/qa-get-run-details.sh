#!/bin/sh
# Phase 3: Get details for a specific run including job step status.
# Usage: qa-get-run-details.sh <repo> <run-id>
# Outputs: JSON (conclusion, createdAt, updatedAt, headSha, jobs)

REPO="${1:?Usage: qa-get-run-details.sh <repo> <run-id>}"
RUN_ID="${2:?Usage: qa-get-run-details.sh <repo> <run-id>}"

gh run view "$RUN_ID" \
    --repo "$REPO" \
    --json conclusion,createdAt,updatedAt,headSha,jobs \
    2>/dev/null
