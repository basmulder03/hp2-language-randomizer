#!/usr/bin/env bash
# Build the mod into the Wine prefix and verify the result.
#
# Usage: tools/build.sh [--apply-patches | --restore-stock] [--data]
#   --apply-patches  first rebuild the patched stock classes as clean export
#                    (assets/stock_original) + patches/ -- the fresh-setup path
#   --restore-stock  first rebuild the patched stock classes from the clean
#                    export (assets/stock_original) + patches/, and restore the
#                    generated data files from assets/stock_patched/ -- for a
#                    fresh prefix or after the stock files were lost
#   --data           regenerate and install all generated text data: merged
#                    dialogue/bump/menu text, LangCredits.dat, the jap/rus
#                    native-text files and NativeLangNames.dat (the stock
#                    .int files are backed up once as *.orig-backup first)
#
# Always: deploys src/mod/HGame/Classes/*.uc and the generated textures,
# refuses to run while the game is open (UCC then "succeeds" without replacing
# hgame.u), compiles, fails on compile errors, and checks that hgame.u was
# rewritten and contains every mod class and texture.
# Audio packages are separate: tools/import_audio.sh.
set -euo pipefail
source "$(dirname "$0")/env.sh"

RESTORE=0; DATA=0; APPLY=0
for arg in "$@"; do
    case "$arg" in
        --apply-patches) APPLY=1 ;;
        --restore-stock) RESTORE=1 ;;
        --data) DATA=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

require_game_closed
[ -f "$GAMEDIR/system/Game.exe" ] || { echo "no game at $GAMEDIR" >&2; exit 1; }

if [ $RESTORE -eq 1 ]; then
    # Patched stock classes: clean export (assets/stock_original) + the
    # tracked patches/ diff. Everything else, and any class without an
    # original, comes from the snapshot (tools/snapshot_stock.sh).
    ORIG="$REPO/assets/stock_original"
    patched=0; copied=0
    while read -r rel; do
        mkdir -p "$GAMEDIR/$(dirname "$rel")"
        if [ -f "$REPO/patches/$rel.patch" ] && [ -f "$ORIG/$rel" ]; then
            tmp="$(mktemp -d)"
            mkdir -p "$tmp/$(dirname "$rel")"
            cp "$ORIG/$rel" "$tmp/$rel"
            (cd "$tmp" && patch -s -p1 --binary < "$REPO/patches/$rel.patch") \
                || { echo "patch failed: $rel" >&2; rm -rf "$tmp"; exit 1; }
            cp "$tmp/$rel" "$GAMEDIR/$rel"
            rm -rf "$tmp"
            patched=$((patched+1))
        else
            [ -e "$SNAPSHOT/$rel" ] || { echo "no patch/original or snapshot for $rel" >&2; exit 1; }
            cp "$SNAPSHOT/$rel" "$GAMEDIR/$rel"
            copied=$((copied+1))
        fi
    done < <(manifest_entries)
    echo "restored stock files: $patched from original+patch, $copied from snapshot"
fi

if [ $APPLY -eq 1 ]; then
    ORIG="$REPO/assets/stock_original"
    n=0
    for p in "$REPO"/patches/HGame/Classes/*.patch; do
        rel="HGame/Classes/$(basename "$p" .patch)"
        [ -f "$ORIG/$rel" ] || { echo "no clean export of $rel in $ORIG (see docs/building.md)" >&2; exit 1; }
        tmp="$(mktemp -d)"; mkdir -p "$tmp/HGame/Classes"
        cp "$ORIG/$rel" "$tmp/$rel"
        (cd "$tmp" && patch -s -p1 --binary < "$p") || { echo "patch failed: $rel" >&2; rm -rf "$tmp"; exit 1; }
        cp "$tmp/$rel" "$GAMEDIR/$rel"; rm -rf "$tmp"
        n=$((n+1))
    done
    echo "applied $n stock patches"
fi

if [ $DATA -eq 1 ]; then
    # The merge reads the stock originals from *.orig-backup, so make those
    # once, before the first merged install overwrites the stock files.
    for f in hpdialog.int BumpDialog.int HPMenu.int; do
        [ -e "$GAMEDIR/system/$f.orig-backup" ] || cp "$GAMEDIR/system/$f" "$GAMEDIR/system/$f.orig-backup"
    done
    python3 "$REPO/tools/scripts/merge_dialog_text.py"
    python3 "$REPO/tools/scripts/generate_lang_credits.py"
    python3 "$REPO/tools/scripts/generate_native_text.py"
    python3 "$REPO/tools/scripts/generate_native_lang_names.py"
    L="$REPO/assets/build/localization"
    cp "$L/HPdialog.int" "$GAMEDIR/system/hpdialog.int"
    cp "$L/BumpDialog.int" "$GAMEDIR/system/BumpDialog.int"
    cp "$L/HPMenu.int" "$GAMEDIR/system/HPMenu.int"
    cp "$L/LangCredits.dat" "$L/NativeLangNames.dat" "$GAMEDIR/system/"
    cp "$L"/HpDialog.jap.backup "$L"/BumpDialog.jap.backup "$L"/HpDialog.rus.backup "$L"/BumpDialog.rus.backup "$GAMEDIR/system/"
    echo "installed generated text data"
fi

# Mod classes and the textures their #exec lines import.
cp "$REPO"/src/mod/HGame/Classes/*.uc "$GAMEDIR/HGame/Classes/"
mkdir -p "$GAMEDIR/HGame/Textures/Flags" "$GAMEDIR/HGame/Textures/LangPicker"
cp "$REPO"/assets/build/flags/*.png "$GAMEDIR/HGame/Textures/Flags/"
cp "$REPO"/assets/build/icons/*.png "$GAMEDIR/HGame/Textures/LangPicker/"

log="$(mktemp)"
before=$(stat -c %Y "$GAMEDIR/system/hgame.u" 2>/dev/null || echo 0)
sleep 1
(cd "$GAMEDIR/system" && wine UCC.exe make >"$log" 2>&1) || true
if ! grep -a -q "Success - 0 error(s)" "$log" || grep -a -q ": Error" "$log"; then
    grep -a -E ": Error|error\(s\)|Failure" "$log" >&2 || tail -20 "$log" >&2
    echo "BUILD FAILED (full log: $log)" >&2
    exit 1
fi
after=$(stat -c %Y "$GAMEDIR/system/hgame.u")
[ "$after" -gt "$before" ] || { echo "hgame.u was not rewritten -- is the game running?" >&2; exit 1; }

missing=0
for f in "$REPO"/src/mod/HGame/Classes/*.uc; do
    cls="$(basename "$f" .uc)"
    grep -a -q "$cls" "$GAMEDIR/system/hgame.u" || { echo "not in hgame.u: class $cls" >&2; missing=1; }
done
for tex in HP2MenuLanguages HP2MenuLanguagesOver Flag_USA Flag_RUS; do
    grep -a -q "$tex" "$GAMEDIR/system/hgame.u" || { echo "not in hgame.u: texture $tex" >&2; missing=1; }
done
[ $missing -eq 0 ] || { echo "BUILD INCOMPLETE" >&2; exit 1; }
rm -f "$log"
echo "build OK: hgame.u $(date -r "$GAMEDIR/system/hgame.u" '+%F %T'), $(ls "$REPO"/src/mod/HGame/Classes/*.uc | wc -l) mod classes verified"
