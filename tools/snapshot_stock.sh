#!/usr/bin/env bash
# Copy every patched/generated file listed in tools/stock_patched_files.txt
# from the Wine prefix into assets/stock_patched/ (local, gitignored), so the
# mod can be restored onto a fresh prefix with tools/build.sh --restore-stock.
set -euo pipefail
source "$(dirname "$0")/env.sh"

missing=0
while read -r rel; do
    src="$GAMEDIR/$rel"
    if [ ! -e "$src" ]; then
        echo "missing in prefix: $rel" >&2
        missing=1
        continue
    fi
    mkdir -p "$SNAPSHOT/$(dirname "$rel")"
    cp -p "$src" "$SNAPSHOT/$rel"
done < <(manifest_entries)
echo "snapshot: $(manifest_entries | wc -l) files -> $SNAPSHOT"
exit $missing
