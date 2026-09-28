"""Summarize a playtest from the engine log.

Usage: python3 tools/check_log.py [path/to/Game.log]
Default log: ~/Documents/Harry - Coding Evolved/Game.log (UTF-16).

Reports maps visited, voice lines played (from LanguagePicker.Played lines:
per language, per line type, English-fallback count), the language pages
opened, and anything that looks like a script problem.
"""
import collections
import re
import sys
from pathlib import Path

DEFAULT_LOG = Path.home() / "Documents/Harry - Coding Evolved/Game.log"
LINE_TYPES = ["dialogue", "cutscene", "chatter", "trigger", "spell"]
PROBLEMS = re.compile(r"Accessed None|Runaway loop|Infinite script recursion|Critical:|"
                      r"Failed to load|out of bounds|Script call stack|General protection", re.I)


def read_log(path: Path) -> list[str]:
    data = path.read_bytes()
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        text = data.decode("utf-16")
    else:
        text = data.decode("utf-8", errors="replace")
    return text.splitlines()


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_LOG
    lines = read_log(path)
    opened = next((l.split("open,", 1)[1].strip() for l in lines if "Log file open," in l), "?")
    print(f"log: {path}  (session {opened})")

    maps = []
    for l in lines:
        m = re.search(r"LoadMap: ([^?]+)", l)
        if m:
            # Save games load by full path ("C:\\users\\...\\Save3.usa"): keep the file name.
            name = m.group(1).strip().replace("\\", "/").rsplit("/", 1)[-1]
            if not maps or maps[-1] != name:
                maps.append(name)
    print("maps:", " -> ".join(maps) or "-")

    played = [re.search(r"type=(\d+) lang=(\S+) id=(\S+) map=(\S+)", l) for l in lines if "LanguagePicker.Played:" in l]
    played = [m for m in played if m]
    by_lang = collections.Counter(m.group(2) for m in played)
    by_type = collections.Counter(LINE_TYPES[int(m.group(1))] if int(m.group(1)) < len(LINE_TYPES) else m.group(1) for m in played)
    total = len(played)
    print(f"voice lines: {total}")
    if total:
        print("  by language:", ", ".join(f"{k} {v} ({100 * v // total}%)" for k, v in by_lang.most_common()))
        print("  by type:    ", ", ".join(f"{k} {v}" for k, v in by_type.most_common()))

    pages = collections.Counter(re.sub(r"\d+$", "", l.split("Transient.", 1)[1].strip())
                                for l in lines if "ChangePage Transient." in l)
    lang_pages = {k: v for k, v in pages.items() if k.startswith(("FELang", "FECredits"))}
    print("language pages opened:", ", ".join(f"{k} x{v}" for k, v in lang_pages.items()) or "-")

    skips = sum("STARTING FASTFORWARD" in l for l in lines)
    print(f"cutscene skips: {skips}")

    problems = [l.strip() for l in lines if PROBLEMS.search(l)]
    print(f"possible problems: {len(problems)}")
    for l in collections.OrderedDict.fromkeys(problems):
        print("  ", l[:160])


if __name__ == "__main__":
    main()
