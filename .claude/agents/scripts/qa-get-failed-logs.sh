#!/bin/sh
# Phase 6: Retrieve failed-step log output for a run (Path B fallback).
# Usage: qa-get-failed-logs.sh <repo> <run-id> [line-limit]
# Outputs: text log lines from failed steps only

REPO="${1:?Usage: qa-get-failed-logs.sh <repo> <run-id> [line-limit]}"
RUN_ID="${2:?}"
LIMIT="${3:-1000}"

gh run view "$RUN_ID" \
    --repo "$REPO" \
    --log-failed \
    2>/dev/null | head -"$LIMIT"
