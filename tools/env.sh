# Shared settings for tools/*.sh. Override WINEPREFIX (the Wine prefix) or
# HP2_GAMEDIR (the M212 game folder inside it) in the environment.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WINEPREFIX="${WINEPREFIX:-$HOME/Games/hp2-audio-randomizer-prefix}"
export WINEARCH=win64
GAMEDIR="${HP2_GAMEDIR:-$WINEPREFIX/drive_c/HP2Mod}"
SNAPSHOT="$REPO/assets/stock_patched"
MANIFEST="$REPO/tools/stock_patched_files.txt"

manifest_entries() {
    grep -v -E '^\s*(#|$)' "$MANIFEST"
}

# UCC "succeeds" without replacing hgame.u while the game has it open.
require_game_closed() {
    if ps -eo args | grep -i -q '[G]ame\.exe'; then
        echo "Game.exe is running -- close the game first." >&2
        exit 1
    fi
}
