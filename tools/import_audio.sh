#!/usr/bin/env bash
# Import a folder of dialogue .wav files as Sounds/AllDialog_<LANG>.uax, with
# lipsync, and verify it. Object names are the .wav basenames, so the folder
# must be flat (no group subfolders).
#
# Usage: tools/import_audio.sh <LANG> <wav-dir>     e.g. tools/import_audio.sh FRE assets/build/normalized/fre
set -euo pipefail
source "$(dirname "$0")/env.sh"

LANG_CODE="${1:?language code, e.g. FRE}"; LANG_CODE="${LANG_CODE^^}"
SRC="${2:?folder of .wav files}"
PKG="AllDialog_$LANG_CODE"
require_game_closed

count=$(find "$SRC" -maxdepth 1 -iname '*.wav' | wc -l)
[ "$count" -gt 0 ] || { echo "no .wav files in $SRC" >&2; exit 1; }

stage="$GAMEDIR/tmp_import_$LANG_CODE"
rm -rf "$stage"; mkdir -p "$stage"
cp "$SRC"/*.wav "$stage/"
rm -f "$GAMEDIR/system/$PKG.uax"
(cd "$GAMEDIR/system" && wine UCC.exe pkg import sound "$PKG" "C:\\HP2Mod\\$(basename "$stage")" nocompress lipsync >/dev/null 2>&1) || true
rm -rf "$stage"
# pkg import saves into system/, but the engine only searches ../Sounds/*.uax.
[ -s "$GAMEDIR/system/$PKG.uax" ] || { echo "$PKG: import failed" >&2; exit 1; }
mv -f "$GAMEDIR/system/$PKG.uax" "$GAMEDIR/Sounds/$PKG.uax"

lip=$(cd "$GAMEDIR/system" && wine UCC.exe haslipsync "$PKG" 2>&1 | grep -a -c "has lipsync" || true)
echo "$PKG: $count wavs imported, $lip with lipsync"
[ "$lip" -eq "$count" ] || { echo "$PKG: lipsync count mismatch" >&2; exit 1; }
