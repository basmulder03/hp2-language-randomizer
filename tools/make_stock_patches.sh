#!/usr/bin/env bash
# Regenerate patches/HGame/Classes/*.patch: one unified diff per patched stock
# class, from the clean export in assets/stock_original/ to the prefix's
# current file. Run after changing a stock file in the prefix.
#
# assets/stock_original/HGame/Classes is `ucc batchexport hgame Class uc` of
# the unmodified M212 hgame.u (lowercase "hgame" -- the package name's casing
# shows up in defaultproperties); see docs/building.md.
set -euo pipefail
source "$(dirname "$0")/env.sh"

ORIG="$REPO/assets/stock_original"
[ -d "$ORIG/HGame/Classes" ] || { echo "no clean export at $ORIG (see docs/building.md)" >&2; exit 1; }
mkdir -p "$REPO/patches/HGame/Classes"
rm -f "$REPO"/patches/HGame/Classes/*.patch
n=0
while read -r rel; do
    case "$rel" in HGame/Classes/*.uc) ;; *) continue ;; esac
    name="$(basename "$rel")"
    diff -u --label "a/$rel" --label "b/$rel" "$ORIG/$rel" "$GAMEDIR/$rel" > "$REPO/patches/$rel.patch" || true
    [ -s "$REPO/patches/$rel.patch" ] || { echo "no changes in $name?" >&2; exit 1; }
    n=$((n+1))
done < <(manifest_entries)
echo "wrote $n patches to patches/HGame/Classes/"
