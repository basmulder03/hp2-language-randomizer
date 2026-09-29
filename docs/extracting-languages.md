# Extracting language data from game discs

The mod ships no game content. Each dubbed language comes from a retail
release of *Harry Potter and the Chamber of Secrets* (PC, 2002) that you
own. Only releases with a real dub are useful: several (e.g. Taiwanese,
Simplified Chinese, Thai, the 2002 Russian disc) are subtitle-only and ship
the English recording.

## Target layout

Everything goes into `assets/audio_source/langs/<lang>/` (gitignored):

| File | What |
|---|---|
| `audio/*.wav` | one file per line, named by dialogue ID (`PC_Ron_WhompTut1_69.wav`), flat |
| `HpDialog.<lang>` | dialogue subtitles (`[All]` section, `ID=[Emotion]text`) |
| `BumpDialog.<lang>` | NPC chatter subtitles |
| `HpMenu.<lang>` | menu text (optional; used by menu randomization) |
| `HPCredits.<lang>` | credits, for the voice-cast section (optional) |

Language codes: `bra dan dut fin fre ger int ita jap nor pol por rus spa swe usa`
(plus the opt-in `redub`). `jap` also needs `HpDialog.jap.backup` /
`BumpDialog.jap.backup` (the disc's native UTF-16 text; the plain `.jap`
files are romanized) and `rus` its text in cp1251.

## From a disc image

1. **Raw images** (`.bin`/`.img`, 2352-byte sectors):
   `python3 tools/scripts/bin2iso.py disc.bin disc.iso`. Plain ISOs and
   `.mdf` files with 2048-byte sectors can be read directly.
2. **InstallShield discs** (`setup/data1.hdr`, `data1.cab`, `data2.cab`):
   extract all three from the ISO (`7z e disc.iso setup/data1.* setup/data2.cab`),
   then `unshield -d out x data1.cab`. Each language is one component with
   `AllDialog.<LANG>_uax`, `HpDialog/BumpDialog/HpMenu/HPCredits.<lang>`.
   `Setup.ini [Languages]` lists the disc's languages.
3. **Plain file discs** (e.g. the 2005 Russian release): the files are on
   the ISO as-is (`Sounds/AllDialog.uax`, `System/*.rus`).
4. **Audio to .wav**: with the game's UCC, in its `System/` folder:
   `wine UCC.exe batchexport <package.uax> Sound wav C:\export`. Copy the
   `.wav` files flat into `audio/` (some packages put them in a group
   subfolder such as `Int/` or `usa/`).
5. **Is it a real dub?** Compare a few lines with the English ones: a
   subtitle-only release has byte-identical `.wav` files (only ~15-50
   non-speech sounds should match).

Then run `hp2mod install` (normalizes loudness, imports every language's
audio with lipsync, builds).
