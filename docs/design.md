# Design

How the language randomizer works inside the game. For building see
[`building.md`](building.md); for every change to a stock game class see
[`stock-patches.md`](stock-patches.md).

## How the game delivers a voice line

Stock *Chamber of Secrets* resolves a line by ID (`PC_Ron_WhompTut1_69`):
the subtitle comes from `Localize("All", ID, "HPdialog")` (or `BumpDialog`),
the audio from `DynamicLoadObject("AllDialog." $ ID)`. Lines reach that point
along several paths:

| Path | Where | Line type |
|---|---|---|
| Interactive dialogue | `baseDialog.FindDialog` | dialogue |
| NPC one-liners | `HChar.DoBumpLine` | chatter |
| Cutscene `Say`/`Talk` | `Actor.CutCommand_M212Say` → `SubstituteDialog` | cutscene |
| Scripted gameplay lines | `Actor.DeliverLocalizedDialog` → `SubstituteDialog` | dialogue |
| Position triggers | `PopupTrigger` → `DeliverLocalizedDialog` | trigger |
| Spell incantations | `harry` / `HPawn` `PlaySound(AllDialog.<id>)` | spell |

`SubstituteDialog` is an M212 hook on `Actor`: it receives the resolved
sound and text and may replace both. The mod overrides it on `HPawn` (every
character, the narrator, props and the cutscene camera), `harry` and
`PopupTrigger`, and patches the other paths to call `LanguagePicker`
directly.

## LanguagePicker

`LanguagePicker` (static, `config`) is the core. For a line ID it picks a
language, loads `AllDialog_<LANG>.<id>` and the subtitle `<id>_<LANG>` from
the merged `.int` files, and falls back to the stock English line if a
language lacks it.

- **Languages:** `LangCodes` / `LangWeights` / `LangEnabled`. `usa` plays
  the North American recording (`AllDialog_USA`), `int` the UK one (the
  stock package's `Int` group). `redub` is only eligible while
  `bRedubEnabled` is set (ini or the `Redub` console command).
- **Modes (`LangMode`):** Random (weighted), Per character and Per level
  (a weighted pick seeded by speaker or map name plus a per-run seed, so the
  choice is stable for the run), Shortest / Longest (compare every eligible
  language's recording length), Chaos (audio and subtitle from two
  different languages).
- **Subtitle state:** the language and line ID of the last resolved line
  are cached; `CutSceneManager.SetText` freezes them together with the text,
  so a subtitle never picks up a later line's language. Lines the mod
  doesn't randomize (vendor pop-ups and similar) reset the cache to English.

## Subtitles

`CutSceneManager.DrawText` shows a flag and the language's native name in
front of the text, and lays the text out itself: wrapped into the area
right of the flag, each line centered, falling back to smaller fonts to fit
the subtitle bar. Japanese and Russian can't be represented in the cp1252
`.int` files, so their text comes from separate UTF-16 files
(`HpDialog.jap.backup` etc.) and is drawn with a font created at runtime.
The "Guess the language" option hides flag and name for the first 60% of
each line.

## Settings, statistics, credits

- **Settings page** (`FELangRandomizerPage`), opened from an icon in the
  in-game book (`FEInGamePage`): randomizer on/off, cutscene skipping (off
  by default), menu randomization, guess mode, the mode, and per language an
  enable checkbox, a 0–10 weight and the resulting share. Values are
  `LanguagePicker` config, saved immediately.
- **Statistics** (`FELangStatsPage`): every resolved line is counted per
  language, by line type, speaker and level, plus seconds heard per
  language. The counts are `travel` variables on `harry`, so they follow the
  player between levels and are saved with the game.
- **Credits** (`LangCreditsControl`, created by `FECreditsPage`): an
  overview of the run's languages, the stock credits, then each dub's
  localization team and voice cast (`LangCredits.dat`, extracted from the
  localized credits files).

## Menu text

`BaseFEPage.GetLocalFEString` and a few direct lookups go through
`LanguagePicker.LocalizeMenu`, which gives each menu label a random
language from the merged `HPMenu.int` (Japanese and Russian excluded: the
menu fonts have no glyphs for them). Labels are built once per page, so they
keep their language for the session.

## Audio pipeline

Each language's `.wav` files are loudness-normalized (one constant gain
per language toward the median across languages, peak-limited) and imported
as `Sounds/AllDialog_<LANG>.uax` with lipsync data. Subtitle, menu and
credits text is merged into the stock `.int` files as `<key>_<LANG>`
entries.

## Engine notes

UnrealScript quirks that shaped the code:

- No `bool` arrays (use `byte`); no `class'X'.const.Y` across classes.
- A context expression (`Other.Array[i]`) is limited to 4 KB, hence the
  accessor functions on `harry` for the statistics tables.
- Identifiers are case-insensitive: a local `rowTotal` clashes with a
  function `RowTotal`.
- `%` on ints yields a float; wrapping it in `float()` is a compile error.
- `HPMenuRaisedButton` forces its width to 180 every frame; `LangMenuButton`
  honours a set width.
- `Localize` returns a `<?...?>` marker, not `""`, for a missing key.
- `UCC make` reports success but leaves `hgame.u` untouched while the game
  is running; `tools/build.sh` checks for this.
