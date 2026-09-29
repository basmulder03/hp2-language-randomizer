"""Build the single-file hp2mod executable with PyInstaller.

Bundles tools/hp2mod.py, the data scripts it imports, and the read-only
resources it needs at run time (patches/, src/mod/, art/, the stock-file
manifest). The private game assets are never bundled.

Usage: python3 -m pip install pyinstaller && python3 tools/package.py
Output: dist/hp2mod(.exe)
"""
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEP = ";" if os.name == "nt" else ":"
DATA = ["patches", "src/mod", "art", "tools/stock_patched_files.txt"]
HIDDEN = ["merge_dialog_text", "generate_lang_credits", "generate_native_text",
          "generate_native_lang_names", "normalize_dialog_loudness", "check_log", "hp2paths", "s3"]


def main():
    cmd = [sys.executable, "-m", "PyInstaller", "--onefile", "--noconfirm", "--clean",
           "--name", "hp2mod", "--paths", str(ROOT / "tools" / "scripts")]
    for item in DATA:
        dest = item if Path(item).suffix == "" else str(Path(item).parent)
        cmd += ["--add-data", f"{ROOT / item}{SEP}{dest}"]
    for mod in HIDDEN:
        cmd += ["--hidden-import", mod]
    cmd.append(str(ROOT / "tools" / "hp2mod.py"))
    subprocess.run(cmd, cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
