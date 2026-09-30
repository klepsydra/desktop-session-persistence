#!/bin/bash
# Shared helper: copy $SRC into $HIST_DIR as a timestamped snapshot, unless
# it's byte-identical to the most recent existing snapshot with the same
# prefix (skips the copy in that case, so periodic saves don't pile up
# hundreds of duplicate entries when nothing actually changed). Then rotate,
# keeping only the newest $KEEP.
#
# Usage: history-snapshot.sh <source-file> <hist-dir> <prefix> <ext> [keep=20]
set -euo pipefail

SRC="$1"; HIST_DIR="$2"; PREFIX="$3"; EXT="$4"; KEEP="${5:-20}"

mkdir -p "$HIST_DIR"

LATEST_HIST=$(ls -t "$HIST_DIR/${PREFIX}_"*".${EXT}" 2>/dev/null | head -1 || true)
if [ -z "$LATEST_HIST" ] || ! cmp -s "$SRC" "$LATEST_HIST"; then
  cp "$SRC" "$HIST_DIR/${PREFIX}_$(date +%Y%m%dT%H%M%S).${EXT}"
fi

ls -t "$HIST_DIR/${PREFIX}_"*".${EXT}" 2>/dev/null | tail -n "+$((KEEP + 1))" | xargs -r rm --
