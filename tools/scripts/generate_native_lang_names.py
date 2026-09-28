#!/usr/bin/env python3
"""Generate NativeLangNames.dat: the native-script names of Japanese and
Russian, for subtitle labels (LanguagePicker.GetNativeLanguageName). Same
format as the native-text files: BOM + UTF-16LE + CRLF, an "[All]" line,
then KEY=VALUE lines. Installed by tools/build.sh --data."""
from pathlib import Path

OUT_PATH = Path(__file__).resolve().parents[2] / "assets/build/localization/NativeLangNames.dat"

ENTRIES = {
    "jap": "日本語",
    "rus": "Русский",
}


def main():
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    lines = ["[All]"] + [f"{lang}={name}" for lang, name in ENTRIES.items()]
    out_bytes = b"\xff\xfe" + "".join(line + "\r\n" for line in lines).encode("utf-16-le")
    OUT_PATH.write_bytes(out_bytes)
    print(f"wrote {OUT_PATH} ({len(lines)} lines, {len(out_bytes)} bytes)")


if __name__ == "__main__":
    main()
