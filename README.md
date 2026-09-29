# HP2 Language Randomizer

A mod for **Harry Potter and the Chamber of Secrets** (PC, 2002), built on the
community **M212 "Harry – Coding Evolved"** version of the game. Every voice
line plays in a randomly chosen language from the game's official dubs, with
matching subtitles and a flag showing which language you're hearing.

## Features

- **Randomized voice lines** everywhere: cutscenes, dialogue, NPC chatter,
  position-triggered lines and spell incantations, with lipsync. Up to 17
  dubs: Brazilian Portuguese, Danish, Dutch, Finnish, French, German,
  Italian, Japanese, Norwegian, Polish, Portuguese, Russian, Spanish,
  Swedish, US and UK English, plus a hidden fan redub.
- **Subtitles** in the spoken language, with flag and native language name;
  Japanese and Russian in their own scripts. Long lines wrap beside the flag.
- **Language modes**: Random, Per character (everyone keeps one language),
  Per level, Shortest line, Longest line, and Chaos (audio and subtitles in
  different languages).
- **Guess the language**: the flag and name appear only near the end of
  each line.
- **Settings page** in the in-game book: enable languages, weight them
  (0–10), modes, menu randomization, cutscene skipping (off by default).
- **Statistics** saved with your game: lines and listening time per
  language, split by line type, character and level.
- **Credits** that open with your run's language overview and add every
  dub's voice cast.
- **Randomized menu text**, and per-language loudness normalization so no
  dub is noticeably louder or quieter.
- Console commands: `ReplayLine` (last line in another language),
  `Redub [on|off]` (the hidden redub pool).

## What you need

This repository contains **no game content** – no audio, text or game
files. To build the mod you need:

- The PC game, with the **M212 "Harry – Coding Evolved"** build installed.
- The **localized releases** whose dubs you want (your own copies). The mod
  works with any subset; languages you don't have are simply not in the
  pool.
- **Python 3** (standard library only) -- or, on Windows, the packaged
  `hp2mod.exe`, which needs nothing. On Linux/macOS the game and its UCC
  compiler run under **Wine**.

## Building

All steps go through one tool, `hp2mod` (`python3 tools/hp2mod.py`, or
`hp2mod.cmd` / `hp2mod.exe` on Windows). Details in
[`docs/building.md`](docs/building.md):

1. Install M212 and export the clean game source once into
   `assets/stock_original/` (see `docs/building.md`).
2. Extract the languages you own into `assets/audio_source/langs/<lang>/`
   ([`docs/extracting-languages.md`](docs/extracting-languages.md)).
3. `hp2mod install` -- normalizes loudness, imports every language's audio
   with lipsync, applies the stock patches and builds. (`hp2mod pack-assets`
   bundles steps 1–2 into a private zip; `hp2mod install --from-zip FILE`
   restores from it.)
4. `hp2mod run` to play with logging (`--res 1200x900` for 4:3); it
   summarizes the session afterwards.

## Repository layout

| Path | Contents |
|---|---|
| `src/mod/HGame/Classes/` | The mod's own UnrealScript classes (`LanguagePicker` is the core) |
| `patches/HGame/Classes/` | Diffs for the stock game classes the mod hooks into |
| `tools/` | `hp2mod.py` (the build/install tool) and `tools/scripts/` (data generators) |
| `art/` | Generated flag and menu-icon artwork |
| `docs/` | Design, stock patches, building, extracting languages |
| `third_party/flag-icons/` | Flag artwork (MIT) |

How the mod works: [`docs/design.md`](docs/design.md). Every change to a
stock game class: [`docs/stock-patches.md`](docs/stock-patches.md).

## Credits

- Mod by **basmulder03**.
- Built on **M212 "Harry – Coding Evolved"** by the M212 team.
- *Harry Potter and the Chamber of Secrets* (PC) by KnowWonder / Electronic
  Arts; Harry Potter is © Warner Bros. / J.K. Rowling. The localized dubs
  are the work of their respective studios and voice casts, credited
  in-game.
- Flag icons from [flag-icons](https://github.com/lipis/flag-icons) (MIT).

## Licence

The code in this repository is MIT-licensed ([`LICENSE`](LICENSE)). That
covers only this repository's own work; it grants nothing for the game, M212
or any game content.
