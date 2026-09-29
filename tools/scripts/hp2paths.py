"""Where things are, for every tool in this repo (standard library only).

- RES: read-only resources (patches/, src/mod/, art/): the repository root,
  or the bundle directory when running as a packaged executable.
- ASSETS: the private working folder with extracted game data and build
  output. `assets/` in the repository, or `hp2mod-assets/` next to the
  executable; override with HP2_ASSETS.
- GAMEDIR: the M212 game folder (the one containing System/Game.exe).
  Override with HP2_GAMEDIR. On Linux/macOS it's inside a Wine prefix
  (WINEPREFIX, default ~/Games/hp2-audio-randomizer-prefix).
"""
import os
import sys
from pathlib import Path

FROZEN = getattr(sys, "frozen", False)
IS_WINDOWS = os.name == "nt"

RES = Path(getattr(sys, "_MEIPASS", "")) if FROZEN else Path(__file__).resolve().parents[2]


def _default_assets() -> Path:
    if FROZEN:
        return Path(sys.executable).resolve().parent / "hp2mod-assets"
    return RES / "assets"


ASSETS = Path(os.environ.get("HP2_ASSETS") or _default_assets())
LANGS_DIR = ASSETS / "audio_source" / "langs"
BUILD_DIR = ASSETS / "build"
LOCALIZATION_DIR = BUILD_DIR / "localization"


def wineprefix() -> Path:
    return Path(os.environ.get("WINEPREFIX") or Path.home() / "Games" / "hp2-audio-randomizer-prefix")


# Windows install locations tried when HP2_GAMEDIR isn't set. The M212 editor
# needs a path without spaces for some commandlets, hence C:\HP2Mod first.
WINDOWS_CANDIDATES = [
    Path(r"C:\HP2Mod"),
    Path(r"C:\Games\HP2Mod"),
    Path(r"C:\Program Files (x86)\EA Games\Harry Potter and the Chamber of Secrets"),
    Path(r"C:\Program Files\EA Games\Harry Potter and the Chamber of Secrets"),
]


def _default_gamedir() -> Path:
    if IS_WINDOWS:
        for candidate in WINDOWS_CANDIDATES:
            if (candidate / "System" / "Game.exe").exists():
                return candidate
        return WINDOWS_CANDIDATES[0]
    return wineprefix() / "drive_c" / "HP2Mod"


GAMEDIR = Path(os.environ.get("HP2_GAMEDIR") or _default_gamedir())


def system_dir() -> Path:
    # The folder is "System" on Windows installs and "system" in some copies;
    # Windows doesn't care, Linux does.
    for name in ("system", "System"):
        if (GAMEDIR / name).is_dir():
            return GAMEDIR / name
    return GAMEDIR / "System"


def find_file(folder: Path, name: str) -> Path:
    """folder/name, matching the name case-insensitively (installs differ:
    hgame.u vs HGame.u), or folder/name as given if nothing matches.
    Needed on Linux; Windows ignores case anyway."""
    exact = folder / name
    if exact.exists() or not folder.is_dir():
        return exact
    lower = name.lower()
    for p in folder.iterdir():
        if p.name.lower() == lower:
            return p
    return exact


def documents_dir() -> Path:
    """Where the game writes Game.log and Game.ini."""
    sub = "Harry - Coding Evolved"
    if IS_WINDOWS:
        home = Path(os.environ.get("USERPROFILE") or Path.home())
        for docs in (home / "Documents", home / "OneDrive" / "Documents"):
            if (docs / sub).exists():
                return docs / sub
        return home / "Documents" / sub
    user = os.environ.get("USER") or "user"
    return wineprefix() / "drive_c" / "users" / user / "Documents" / sub
