# Building the mod

All tooling is one command, `hp2mod` -- `python3 tools/hp2mod.py` on
Linux/macOS (UCC runs through Wine), `hp2mod.cmd` or the packaged
`hp2mod.exe` on Windows. It uses only the Python standard library.
`hp2mod paths` shows which folders it uses; override them with
`HP2_GAMEDIR` (the M212 game folder), `HP2_ASSETS` (the private data folder)
and, on Linux, `WINEPREFIX` (default `~/Games/hp2-audio-randomizer-prefix`).
Close the game first: while it runs, UCC reports success without replacing
`hgame.u`, and the tool refuses to build.

| Task | Command |
|---|---|
| Everything from a private assets zip: extract, normalize, import all audio, build | `hp2mod install --from-zip FILE` |
| Rebuild after changing `src/mod/**/*.uc` | `hp2mod build` |
| Also regenerate and install the text data | `hp2mod build --data` |
| First build on a fresh game folder (stock classes = clean export + `patches/`) | `hp2mod build --apply-patches --data` |
| Restore from the local snapshot instead | `hp2mod build --restore-stock --data` |
| Bundle the local assets into a private zip (never share it) | `hp2mod pack-assets [--out FILE]` |
| Store that zip in your own S3 bucket / fetch it back (checksum-verified) | `hp2mod upload-assets`, `hp2mod download-assets` |
| Everything from the zip in S3 | `hp2mod install --from-s3` |
| Save the patched stock files + generated data locally | `hp2mod snapshot` |
| Regenerate `patches/` after editing a stock class | `hp2mod make-patches` |
| Even out loudness between languages | `hp2mod normalize` |
| (Re)import one language's audio with lipsync | `hp2mod import-audio FRE assets/build/normalized/fre` |
| Play with the engine log, then summarize the session | `hp2mod run` (`--res 1200x900` for 4:3; the size is kept) |
| Summarize a Game.log | `hp2mod check-log` |

S3 settings (any S3-compatible store: endpoint, bucket, region, object key,
and the keys or commands that print them) go in `~/.config/hp2mod/s3.ini`
or `HP2_S3_*` / `AWS_*` variables -- see `tools/scripts/s3.py`. Keep the
bucket private: the zip is game content.

The Linux shell names (`tools/build.sh`, `./run-game-with-logs.sh`, ...) are
thin wrappers around the same commands.

**Tests, packaging, releases.** `python3 -m unittest discover tests` runs the
tool tests (no game needed). `python3 tools/package.py` (needs `pip install
pyinstaller`) builds the single-file `dist/hp2mod(.exe)`. GitHub Actions
(`.github/workflows/build.yml`) runs the tests on Linux and Windows, builds
and smoke-tests `hp2mod.exe` and a Linux `hp2mod` binary on every push, and
on a version tag (`git tag v1.0.0 && git push origin v1.0.0`) publishes a
release with both binaries and `hp2mod.cmd`.

`build` deploys the mod classes and the artwork in `art/`, compiles, fails on
any compile error, and checks that `hgame.u` was rewritten and contains every
mod class and the custom textures.

## What lives where

- **Git:** mod classes (`src/mod`), stock-class diffs (`patches/`), the
  generated artwork (`art/`), tools, docs. No whole stock files or extracted game content.
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
prefix, run `hp2mod make-patches` and `hp2mod snapshot`.

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
