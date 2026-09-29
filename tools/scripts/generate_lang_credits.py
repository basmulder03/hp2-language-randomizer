"""Build LangCredits.dat: each dubbed language's own localization team and
voice cast, taken from that language's HPCredits.<lang> file, for
LangCreditsControl to append after the stock credits.

Every localized HPCredits file keeps the stock credits layout and inserts
its own block right after the (translated) "Special Thanks" section, ending
at the "Warner Bros. Interactive Entertainment" heading. Japanese is the
exception: its block follows the Warner Bros. section and runs to the end.
The block's first heading per language is listed explicitly in BLOCKS
below (checked by hand against each file), so a changed source file fails
loudly instead of silently extracting the wrong lines.

Output lines are "<lang>|<credits line>" (credits line keeps the stock
"/b" heading prefix); LangCreditsControl uses the lang tag to pick the
native font (Cyrillic for rus). Written as BOM + UTF-16LE + CRLF, the same
format LanguagePicker already reads with LoadStringArray.

Usage: python3 tools/scripts/generate_lang_credits.py
"""
import re
from pathlib import Path

from hp2paths import LANGS_DIR, LOCALIZATION_DIR
from merge_dialog_text import POLISH_TRANSLITERATION

OUT_PATH = LOCALIZATION_DIR / "LangCredits.dat"

# Pool order (LanguagePicker.LangCodes), dubbed languages with a credits
# file. usa/int are the stock credits themselves; pol and redub have none.
# lang -> (first heading of the localized block, heading that ends it or None)
BLOCKS = {
    "bra": ("/bEquipe de Localização - Brasil", "/bWarner Bros. Interactive Entertainment"),
    "dan": ("/bDansk versionisering", "/bWarner Bros. Interactive Entertainment"),
    "dut": ("/bNederlandse lokalisatie", "/bWarner Bros. Interactive Entertainment"),
    "fin": ("/bLokalisointi, Suomi", "/bWarner Bros. Interactive Entertainment"),
    "fre": ("/bLocalisation France", "/bWarner Bros. Interactive Entertainment"),
    "ger": ("/bGerman localisation", "/bWarner Bros. Interactive Entertainment"),
    "ita": ("/bLocalizzazione italiana", "/bWarner Bros. Interactive Entertainment"),
    "jap": ("/bElectronic Arts Square ", None),  # trailing space is in the file
    "nor": ("/bLokalisering til norsk", "/bWarner Bros. Interactive Entertainment"),
    "pol": ("/bLokalizacja - Polska - Cenega Poland", "/bWarner Bros. Interactive Entertainment"),
    "por": ("/bEquipa de Localização", "/bWarner Bros. Interactive Entertainment"),
    "rus": ("/bЛокализация для России", "/bWarner Bros. Interactive Entertainment"),
    "spa": ("/bEquipo de Localización España", "/bWarner Bros. Interactive Entertainment"),
    "swe": ("/bSvensk lokalisering", "/bWarner Bros. Interactive Entertainment"),
}


def credits_file(lang: str) -> Path | None:
    """The language's credits file, or None if it isn't there (any subset of
    languages is fine)."""
    folder = LANGS_DIR / lang
    matches = [p for p in folder.iterdir() if p.name.lower() == f"hpcredits.{lang}"] if folder.is_dir() else []
    if len(matches) > 1:
        raise SystemExit(f"{lang}: more than one HPCredits.{lang}: {matches}")
    return matches[0] if matches else None


def read_lines(path: Path) -> list[str]:
    data = path.read_bytes()
    if data[:2] == b"\xff\xfe":
        text = data[2:].decode("utf-16-le")
    else:
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = data.decode("cp1252")
    lines = {int(m.group(1)): m.group(2) for m in re.finditer(r"^Line(\d+)=(.*?)\r?$", text, re.M)}
    return [lines[i] for i in sorted(lines)]


def extract(lang: str) -> list[str]:
    start, end = BLOCKS[lang]
    lines = read_lines(credits_file(lang))
    if lines.count(start) != 1:
        raise SystemExit(f"{lang}: start heading {start!r} found {lines.count(start)} times")
    i = lines.index(start)
    if end is None:
        j = next((k for k in range(i, len(lines)) if lines[k].upper().startswith("/Q")), len(lines))
    else:
        j = lines.index(end, i)
    block = lines[i:j]
    while block and not block[-1].strip():
        block.pop()
    return block


def main():
    out = []
    for lang in BLOCKS:
        if credits_file(lang) is None:
            print(f"{lang}: no HPCredits.{lang}, skipped")
            continue
        block = extract(lang)
        if lang == "pol":
            # ą/ł/ż... aren't in the menu fonts; same transliteration as the
            # Polish subtitles.
            block = [line.translate(POLISH_TRANSLITERATION) for line in block]
        out.extend(f"{lang}|{line}" for line in block)
        out.append(f"{lang}|")
        print(f"{lang}: {len(block)} lines")
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_bytes(b"\xff\xfe" + ("\r\n".join(out) + "\r\n").encode("utf-16-le"))
    print(f"wrote {OUT_PATH} ({len(out)} lines)")


if __name__ == "__main__":
    main()
