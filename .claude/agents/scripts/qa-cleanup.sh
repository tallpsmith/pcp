#!/bin/sh
# Phase 10: Paranoid cleanup of a QA artifact download directory.
# Usage: qa-cleanup.sh <artifact-dir>
# Six guards prevent accidental deletion of anything outside ~/.claude/tmp/qa-analysis-*

ARTIFACT_DIR="${1:-}"
SAFE_PREFIX="$HOME/.claude/tmp/qa-analysis-"

# Guard 1: must not be empty
if [ -z "$ARTIFACT_DIR" ]; then
    echo "CLEANUP ABORTED: no directory specified"
    exit 0
fi

# Guard 2: must start with the safe prefix
case "$ARTIFACT_DIR" in
    "$SAFE_PREFIX"*) ;;
    *) echo "CLEANUP ABORTED: '$ARTIFACT_DIR' does not start with '$SAFE_PREFIX'"; exit 0 ;;
esac

# Guard 3: no path traversal
case "$ARTIFACT_DIR" in
    *..*) echo "CLEANUP ABORTED: path contains '..'"; exit 0 ;;
esac

# Guard 4: must have a non-empty run-specific suffix after the prefix
SUFFIX="${ARTIFACT_DIR#$SAFE_PREFIX}"
if [ -z "$SUFFIX" ]; then
    echo "CLEANUP ABORTED: no run-specific suffix — refusing to delete the prefix directory itself"
    exit 0
fi

# Guard 5: suffix must not contain path separators (no subdirectory tricks)
case "$SUFFIX" in
    */*|*\\*) echo "CLEANUP ABORTED: suffix contains path separators"; exit 0 ;;
esac

# Guard 6: must actually be a directory
if [ ! -d "$ARTIFACT_DIR" ]; then
    echo "CLEANUP SKIPPED: '$ARTIFACT_DIR' is not a directory (may already be cleaned up)"
    exit 0
fi

echo "All 6 guards passed. Removing $ARTIFACT_DIR"
rm -rf "$ARTIFACT_DIR"
echo "Done."
