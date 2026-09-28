#!/usr/bin/env bash
# Launch HP2 (Chamber of Secrets, PC 2002 / M212 build) under Wine with the
# engine's own logging enabled, then surface whatever log file it produced.
#
# Usage: ./run-game-with-logs.sh [--res WxH] [extra Game.exe args]
#   --res WxH   set the game window size first, e.g. --res 1200x900 for 4:3
#               or --res 1600x900 for 16:9 (kept for later runs too)

set -uo pipefail

source "$(dirname "$0")/tools/env.sh"
SYSDIR="$GAMEDIR/system"
WINE_STDERR_LOG="/tmp/hp2-wine-stderr.log"
# This build writes its engine log to the user's Documents folder (Wine
# symlinks it to the real ~/Documents), not to $SYSDIR.
USERDIR="$WINEPREFIX/drive_c/users/$USER/Documents/Harry - Coding Evolved"

if [ ! -f "$SYSDIR/Game.exe" ]; then
    echo "Game.exe not found at $SYSDIR/Game.exe -- check WINEPREFIX/GAMEDIR." >&2
    exit 1
fi

RES=""
if [ "${1:-}" = "--res" ]; then
    RES="${2:?--res needs WxH, e.g. 1200x900}"
    shift 2
fi

if [ -n "$RES" ]; then
    if ps -eo args | grep -i -q '[G]ame\.exe'; then
        echo "Game.exe is already running -- close it before changing --res." >&2
        exit 1
    fi
    W="${RES%x*}"; H="${RES#*x}"
    INI="$USERDIR/Game.ini"
    # Only the [WinDrv.WindowsClient] section; the ini uses CRLF.
    python3 - "$INI" "$W" "$H" <<'PY'
import re, sys
path, w, h = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(path, "rb").read()
start = data.index(b"[WinDrv.WindowsClient]")
end = data.find(b"\n[", start + 1)
end = len(data) if end < 0 else end
section = data[start:end]
section = re.sub(rb"WindowedViewportX=\d+", b"WindowedViewportX=" + w.encode(), section)
section = re.sub(rb"WindowedViewportY=\d+", b"WindowedViewportY=" + h.encode(), section)
open(path, "wb").write(data[:start] + section + data[end:])
PY
    echo "window size set to ${W}x${H}"
fi

cd "$SYSDIR"

# Timestamp marker so we can tell which log this run produced/updated.
before_marker=$(mktemp)

echo "WINEPREFIX=$WINEPREFIX"
echo "GAMEDIR=$GAMEDIR"
echo "Launching: wine Game.exe -log $*"
echo

# -log opens a live UnrealScript engine console/log window in addition to
# writing the usual .log file in $SYSDIR. Wine-level stderr (DLL/prefix
# issues, not engine warnings) is tee'd separately so it doesn't get lost.
wine Game.exe -log "$@" 2> >(tee "$WINE_STDERR_LOG" >&2)
exit_code=$?

echo
echo "Game exited (code $exit_code)."

newest=$(find "$USERDIR" "$SYSDIR" -maxdepth 1 -iname "Game.log" -newer "$before_marker" 2>/dev/null | head -1)
rm -f "$before_marker"

if [ -n "$newest" ]; then
    echo "Engine log: $newest"
    echo "---- last 40 lines ----"
    # The log is UTF-16; convert so it's readable/greppable.
    iconv -f utf-16 -t utf-8 "$newest" 2>/dev/null | tail -n 40 || tail -n 40 "$newest"
else
    echo "No new/updated .log file found in $USERDIR or $SYSDIR."
    echo "Check Wine-level stderr instead: $WINE_STDERR_LOG"
fi
