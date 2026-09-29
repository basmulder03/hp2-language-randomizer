#!/usr/bin/env python3
"""Merge each language's HpDialog / BumpDialog / HpMenu text into the stock
hpdialog.int / BumpDialog.int / HPMenu.int as "<KEY>_<LANG>" entries.
Output: assets/build/localization/; installed by tools/build.sh --data.
"""
import os
import re
from pathlib import Path

from hp2paths import LANGS_DIR, LOCALIZATION_DIR, find_file, system_dir

ENCODINGS = {
    "jap": "utf-8",
    "pol": "utf-16-le",
    "rus": "cp1251",
}
DEFAULT_ENCODING = "cp1252"

# Languages whose text can contain characters with no cp1252 representation
# at all (Cyrillic, kanji/kana). In-game they're drawn from separate UTF-16
# files (generate_native_text.py); here they're encoded with
# errors="replace", so the merged copy just holds "?" for them.
REPLACE_ON_ENCODE = {"jap", "rus"}

# ą/ć/ę/ł/ń/ś/ź/ż (and uppercase) have no cp1252 representation at all --
# note ó IS in cp1252 and is left untouched. Polish has no dedicated
# native-font path planned (unlike jap/rus), so it needs to stay readable
# through this same cp1252 merged file. Map each unsupported character to
# its closest ASCII/cp1252-safe equivalent before encoding; this loses
# correct Polish orthography but produces readable text instead of a
# UnicodeEncodeError or "?" garbage.
POLISH_TRANSLITERATION = str.maketrans({
    "ą": "a", "Ą": "A",
    "ć": "c", "Ć": "C",
    "ę": "e", "Ę": "E",
    "ł": "l", "Ł": "L",
    "ń": "n", "Ń": "N",
    "ś": "s", "Ś": "S",
    "ź": "z", "Ź": "Z",
    "ż": "z", "Ż": "Z",
})

LANGS = ["bra", "dan", "dut", "fin", "fre", "ger", "int", "ita", "jap", "nor", "pol", "por", "redub", "rus", "spa", "swe", "usa"]

# Actual on-disk filenames -- note hpdialog.int is lowercase in
# the game's System folder, unlike BumpDialog.int. And the
# per-language source files use "HpDialog.<lang>" (lowercase p), not
# "HPdialog.<lang>". Wine itself is case-insensitive but this script reads
# directly off the native Linux filesystem, which is case-sensitive, so the
# exact case matters in both places.
BASE_FILENAMES = {
    "HPdialog.int": "hpdialog.int",
    "BumpDialog.int": "BumpDialog.int",
    "HPMenu.int": "HPMenu.int",
}
SRC_STEMS = {
    "HPdialog.int": "HpDialog",
    "BumpDialog.int": "BumpDialog",
    "HPMenu.int": "HpMenu",
}
# Menu text (LanguagePicker.LocalizeMenu) is drawn with the stock bitmap
# menu fonts, which have no Japanese/Cyrillic glyphs -- so jap/rus are left
# out. pol is transliterated like its dialogue. redub is included but only
# ever picked while it's enabled (PickWeightedLang's gate).
LANGS_FOR = {
    "HPMenu.int": ["bra", "dan", "dut", "fin", "fre", "ger", "int", "ita", "nor", "pol", "por", "redub", "spa", "swe", "usa"],
}


def find_source(lang: str, stem: str) -> Path | None:
    # Case-insensitive: sources are e.g. "HpMenu.fre" but "HPMenu.int".
    folder = LANGS_DIR / lang
    want = f"{stem}.{lang}".lower()
    if not folder.is_dir():
        return None
    for p in folder.iterdir():
        if p.name.lower() == want:
            return p
    return None


# The engine strips one leading "[Emotion]" tag before display; a tag
# missing its "]" (seen once: redub PC_Nar_PrivetIntro_60) would show on
# screen, so it's repaired here.
UNCLOSED_TAG = re.compile(r"^\[(Normal|Happy|Mad|Sarcastic|Sad|Whisper)(?!\])")


def fix_emotion_tag(value: str) -> str:
    return UNCLOSED_TAG.sub(lambda m: f"[{m.group(1)}]", value)


def parse_dialog_file(path: Path, encoding: str) -> dict[str, str]:
    entries = {}
    text = path.read_text(encoding=encoding, errors="replace")
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("[") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        entries[key.strip()] = value.strip()
    return entries


def merge(filename: str, out_path: Path):
    # Read the stock original from `<file>.orig-backup` when it exists: once
    # a merge is installed, the live file is the previous merged output, and
    # merging into it again would duplicate every "_LANG" entry. build.sh
    # writes the backup once, before the first install.
    base_name = BASE_FILENAMES[filename]
    backup_path = find_file(system_dir(), f"{base_name}.orig-backup")
    base_path = backup_path if backup_path.exists() else find_file(system_dir(), base_name)
    base_lines = base_path.read_text(encoding=DEFAULT_ENCODING, errors="replace").splitlines()

    # (line, lang) pairs -- lang is None for the base/usa/int content, which
    # gets strict-encoded just like the 11 Western European languages.
    merged: list[tuple[str, str | None]] = [(line, None) for line in base_lines]
    for lang in LANGS_FOR.get(filename, LANGS):
        src = find_source(lang, SRC_STEMS[filename])
        if src is None:
            print(f"skip {lang}: {SRC_STEMS[filename]}.{lang} not found")
            continue
        entries = parse_dialog_file(src, ENCODINGS.get(lang, DEFAULT_ENCODING))
        for key, value in entries.items():
            if lang == "pol":
                value = value.translate(POLISH_TRANSLITERATION)
            merged.append((f"{key}_{lang.upper()}={fix_emotion_tag(value)}", lang))

    # cp1252, not UTF-8: HP2's in-game text renderer reads localization
    # files as single-byte cp1252 (no BOM) on the standard, non-Japanese-
    # native-font path; UTF-8 would show up as mojibake on every accented
    # character. No BOM: it would break the "[All]" header on line one.
    #
    # jap/rus use errors="replace" (see REPLACE_ON_ENCODE). Everything else
    # is encoded strict, so an unexpected non-cp1252 character in a source
    # file fails loudly instead of silently turning into "?".
    with out_path.open("wb") as f:
        for line, lang in merged:
            errors = "replace" if lang in REPLACE_ON_ENCODE else "strict"
            f.write(line.encode(DEFAULT_ENCODING, errors=errors))
            f.write(b"\n")
    print(f"wrote {out_path} ({len(merged)} lines)")


if __name__ == "__main__":
    out_dir = LOCALIZATION_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    merge("HPdialog.int", out_dir / "HPdialog.int")
    merge("BumpDialog.int", out_dir / "BumpDialog.int")
    merge("HPMenu.int", out_dir / "HPMenu.int")
