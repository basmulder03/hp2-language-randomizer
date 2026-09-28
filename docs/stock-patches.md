# Stock class patches

The mod changes 19 classes of the stock `HGame` package. The diffs live in
`patches/HGame/Classes/` (against a clean `ucc batchexport hgame Class uc`
export, see [`building.md`](building.md)); this page says what each one is
for. Stock files keep their original CRLF line endings, so the diffs only
contain real changes.

## Voice lines

| Class | Change |
|---|---|
| `baseDialog` | `FindDialog` resolves through `LanguagePicker.ResolveLine` (line type: dialogue). |
| `HChar` | `DoBumpLine` resolves stock bump lines through `ResolveLine` (chatter); lines from a custom package keep stock behaviour and reset the subtitle language to English. |
| `HPawn` | Overrides `SubstituteDialog` (cutscenes and `DeliverLocalizedDialog` for every `HPawn`: characters, the narrator, props, the cutscene camera); spell casts use `ResolveSoundOnly`. |
| `harry` | Same `SubstituteDialog` override and spell calls; the run-statistics storage and accessors (`LangStats*`, `LangStatSeconds`, `LangRunSeed`); console commands `ReplayLine`, `Redub` and the `DebugSpamLine` test command. |
| `PopupTrigger` | Overrides `SubstituteDialog` for triggers that use the stock dialogue data; custom packages keep stock behaviour. |

## Lines that stay English

These show English text in the subtitle area without going through the
randomizer, so they reset the subtitle language first (otherwise the
previous line's flag would appear over them):

| Class | Where |
|---|---|
| `Characters` | vendor pop-ups |
| `VendorManager` | vendor dialogue |
| `CauldronMixing` | cauldron message |
| `SpellLessonTrigger` | spell lessons |
| `FELangGrid` | the developer sound browser |

## Menus

| Class | Change |
|---|---|
| `FEBook` | Registers the settings page (`LANGRANDOMIZER`) and statistics page (`LANGSTATS`). |
| `FEInGamePage` | The language settings icon in the in-game book's bottom row. |
| `FECreditsPage` | Creates `LangCreditsControl` instead of the stock credits control. |
| `BaseFEPage` | `GetLocalFEString` returns `LanguagePicker.LocalizeMenu` (menu text randomization). |
| `baseConsole`, `FEInputPage`, `M212FEBindPage`, `StatusItem` | Pause/loading messages, key names and inventory tooltips go through `LocalizeMenu` too. |
| `HPConsole` | Cutscene skipping is ignored while disabled in the settings; the "skipping" notice goes through `LocalizeMenu`. |

## Data files

`tools/build.sh --data` also installs generated data into `System/`: the
merged `hpdialog.int`, `BumpDialog.int` and `HPMenu.int` (each stock file is
backed up once as `*.orig-backup`, which later merges read),
`LangCredits.dat`, `NativeLangNames.dat`, and the Japanese/Russian
native-text files. The per-language audio packages are
`Sounds/AllDialog_<LANG>.uax`.
