# Building the mod

Everything targets the Wine prefix in `tools/env.sh`
(`~/Games/hp2-audio-randomizer-prefix` by default; override with `WINEPREFIX=` or `HP2_GAMEDIR=`).
Close the game first: while it runs, UCC reports success without replacing
`hgame.u`, and the scripts refuse to start.

| Task | Command |
|---|---|
| Rebuild after changing `src/mod/**/*.uc` | `tools/build.sh` |
| Also regenerate merged dialogue/menu text and `LangCredits.dat` | `tools/build.sh --data` |
| First build on a fresh prefix (stock classes = clean export + `patches/`) | `tools/build.sh --apply-patches --data` |
| Rebuild a fresh or broken prefix from the local snapshot | `tools/build.sh --restore-stock --data` |
| Save the prefix's patched stock files + generated data locally | `tools/snapshot_stock.sh` |
| Regenerate `patches/` after editing a stock class | `tools/make_stock_patches.sh` |
| (Re)import one language's audio with lipsync | `tools/import_audio.sh FRE assets/build/normalized/fre` |
| Even out loudness between languages | `python3 tools/scripts/normalize_dialog_loudness.py`, then `import_audio.sh` per language |
| Play with the engine log | `./run-game-with-logs.sh` (log: `~/Documents/Harry - Coding Evolved/Game.log`, UTF-16) |
| Test another aspect ratio | `./run-game-with-logs.sh --res 1200x900` (4:3) or `--res 1600x900` (16:9); the size is kept for later runs |
| Summarize a playtest (maps, voice lines per language/type, pages opened, script problems) | `python3 tools/check_log.py` |

`build.sh` deploys the mod classes and generated textures (`assets/build/flags`,
`assets/build/icons`), compiles, fails on any compile error, and checks that
`hgame.u` was rewritten and contains every mod class and the custom textures.

## What lives where

- **Git:** mod classes (`src/mod`), stock-class diffs (`patches/`), tools,
  docs. No whole stock files or extracted game content.
- **`assets/` (local, gitignored):** extracted language sources
  (`audio_source/langs/<lang>/`), generated build output (`build/`), and
  `stock_patched/` — the snapshot of every file listed in
  `tools/stock_patched_files.txt`.
- **Wine prefix:** the installed game. Stock classes are patched in place;
  each patch is described in `docs/stock-patches.md`.

## Stock patches

Each patched stock class has a tracked diff in `patches/HGame/Classes/`
against the clean decompile in `assets/stock_original/HGame/Classes/`
(local, gitignored: it's stock code). `tools/build.sh --restore-stock`
rebuilds those classes as original + patch; the generated data files come
from the `assets/stock_patched/` snapshot. After editing a stock class in the
prefix, run `tools/make_stock_patches.sh` and `tools/snapshot_stock.sh`.

**Recreating `assets/stock_original`.** The M212 installer
(`M212_Editor_Setup.exe`, Inno Setup) ships `System/hgame.u` compiled, not as
source; the source is its UCC export:

1. Install M212 into a fresh Wine prefix, to a path **without spaces**
   (e.g. `C:\HP2Mod`) -- with spaces, `batchexport` fails with
   `Failed to find object 'Class Any.Potter'`. The installer refuses a target
   that doesn't look like a game folder (`System/Game.exe` etc.). The DirectX
   web setup it launches at the end crashes under Wine; harmless.
2. Make sure the retail packages `hgame.u` depends on (`HPSounds.u`,
   textures, sounds, ...) are present in that folder, e.g. by symlinking them
   from a full game install.
3. From its `System/`: `wine UCC.exe batchexport hgame Class uc C:\HGameExport`.
   The output path must be an absolute Windows path. Use lowercase `hgame` --
   the name's casing ends up in `defaultproperties` (`Class'hgame.CutScript'`),
   and the patches were made against that casing.

An export made this way is byte-identical for every class the mod doesn't
touch, and applying `patches/` to it reproduces the patched classes exactly.
Keep the stock files' CRLF line endings when editing them, or the diffs
balloon.

The audio packages (`Sounds/AllDialog_*.uax`) aren't
snapshotted (~6 GB); they're rebuilt from `assets/audio_source` with
`import_audio.sh` (after `normalize_dialog_loudness.py` for loudness).
