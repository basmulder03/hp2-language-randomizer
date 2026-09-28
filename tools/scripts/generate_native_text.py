"""Write the native-script subtitle files LanguagePicker.GetNativeText reads
(system/HpDialog.<lang>.backup, system/BumpDialog.<lang>.backup) for the two
languages the merged cp1252 .int files can't represent:

- jap: the disc's own UTF-16 files, kept as <File>.jap.backup in
  assets/audio_source/langs/jap/ (the plain HpDialog.jap there is a
  romanized copy used for the merged .int).
- rus: converted from HpDialog.rus / BumpDialog.rus (cp1251).

Format: BOM + UTF-16LE + CRLF. Output: assets/build/localization/.

Usage: python3 tools/scripts/generate_native_text.py
"""
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LANGS = REPO / "assets/audio_source/langs"
OUT = REPO / "assets/build/localization"


def write_utf16(lines: list[str], path: Path):
    path.write_bytes(b"\xff\xfe" + ("\r\n".join(lines) + "\r\n").encode("utf-16-le"))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for stem in ("HpDialog", "BumpDialog"):
        jap = LANGS / "jap" / f"{stem}.jap.backup"
        data = jap.read_bytes()
        text = data[2:].decode("utf-16-le") if data[:2] == b"\xff\xfe" else data.decode("utf-16")
        write_utf16(text.splitlines(), OUT / f"{stem}.jap.backup")

        rus = LANGS / "rus" / f"{stem}.rus"
        write_utf16(rus.read_bytes().decode("cp1251").splitlines(), OUT / f"{stem}.rus.backup")
    print(f"wrote native-text backups to {OUT}")


if __name__ == "__main__":
    main()
