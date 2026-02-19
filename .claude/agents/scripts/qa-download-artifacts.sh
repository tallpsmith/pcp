#!/bin/sh
# Phase 4: Download QA artifacts for a run into a local directory.
# Usage: qa-download-artifacts.sh <repo> <run-id> <output-dir> [artifact-name]
# Outputs: exit 0 on success, exit 1 on failure (artifact missing or expired)

REPO="${1:?Usage: qa-download-artifacts.sh <repo> <run-id> <output-dir> [artifact-name]}"
RUN_ID="${2:?}"
OUTPUT_DIR="${3:?}"
ARTIFACT_NAME="${4:-qa-logs}"

mkdir -p "$OUTPUT_DIR" 2>/dev/null || {
    echo "ERROR: Cannot create output directory: $OUTPUT_DIR" >&2
    exit 1
}

gh run download "$RUN_ID" \
    --repo "$REPO" \
    -n "$ARTIFACT_NAME" \
    --dir "$OUTPUT_DIR" \
    2>/dev/null
