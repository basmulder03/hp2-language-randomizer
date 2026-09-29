#!/usr/bin/env python3
"""hp2mod: build and install the HP2 Language Randomizer.

Standard library only; runs the same on Windows (UCC.exe directly) and
Linux/macOS (UCC.exe through Wine). Also packaged as a single hp2mod.exe.

    hp2mod paths                        show the folders being used
    hp2mod install --from-zip FILE      extract assets, normalize, import audio, build
    hp2mod build [--apply-patches | --restore-stock] [--data]
    hp2mod import-audio LANG DIR        import one language's .wav files with lipsync
    hp2mod normalize [LANG ...]         write loudness-normalized .wav copies
    hp2mod pack-assets [--out FILE]     bundle the local assets into a private zip
    hp2mod upload-assets [--file FILE]  store the private zip in your S3 bucket
    hp2mod download-assets [--out FILE] fetch it back (checksum-verified)
    hp2mod install --from-s3            download it and install
    hp2mod snapshot                     save patched/generated game files locally
    hp2mod make-patches                 regenerate patches/ after editing stock classes
    hp2mod run [--res WxH] [ARGS...]    start the game with logging, then summarize
    hp2mod check-log [FILE]             summarize a Game.log

Folders: see tools/scripts/hp2paths.py (HP2_GAMEDIR, HP2_ASSETS, WINEPREFIX).
"""
import argparse
import difflib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

if not getattr(sys, "frozen", False):
    sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))

import hp2paths  # noqa: E402
from hp2paths import ASSETS, BUILD_DIR, GAMEDIR, IS_WINDOWS, LANGS_DIR, LOCALIZATION_DIR, RES, find_file  # noqa: E402

MOD_CLASSES = RES / "src" / "mod" / "HGame" / "Classes"
PATCHES = RES / "patches"
ART = RES / "art"
MANIFEST = RES / "tools" / "stock_patched_files.txt"
STOCK_ORIGINAL = ASSETS / "stock_original"
SNAPSHOT = ASSETS / "stock_patched"
CUSTOM_TEXTURES = ["HP2MenuLanguages", "HP2MenuLanguagesOver", "Flag_USA", "Flag_RUS"]
# int is the stock package's Int group; never imported as its own package.
IMPORTED_LANGS = ["bra", "dan", "dut", "fin", "fre", "ger", "ita", "jap", "nor",
                  "pol", "por", "redub", "rus", "spa", "swe", "usa"]


class ToolError(Exception):
    pass


def say(msg: str):
    print(msg, flush=True)


# --- game process and UCC ---------------------------------------------------

def game_running() -> bool:
    try:
        if IS_WINDOWS:
            out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Game.exe", "/NH"],
                                 capture_output=True, text=True).stdout
            return "game.exe" in out.lower()
        out = subprocess.run(["ps", "-eo", "args"], capture_output=True, text=True).stdout
        return any("game.exe" in line.lower() and "hp2mod" not in line.lower() for line in out.splitlines())
    except OSError:
        return False


def require_game_closed():
    # UCC reports success without replacing hgame.u while the game has it open.
    if game_running():
        raise ToolError("Game.exe is running -- close the game first.")


def require_game():
    if not (hp2paths.system_dir() / "Game.exe").exists():
        raise ToolError(f"no game found at {GAMEDIR} (set HP2_GAMEDIR to the M212 folder)")


def ucc_path(p: Path) -> str:
    """A path as UCC.exe sees it (Windows path; C:\\ inside the Wine prefix)."""
    p = Path(p).resolve()
    if IS_WINDOWS:
        return str(p)
    drive_c = (hp2paths.wineprefix() / "drive_c").resolve()
    try:
        return "C:\\" + str(p.relative_to(drive_c)).replace("/", "\\")
    except ValueError:
        return "Z:" + str(p).replace("/", "\\")


def ucc(*args: str, check_output=False) -> str:
    sysdir = hp2paths.system_dir()
    if IS_WINDOWS:
        cmd = [str(sysdir / "UCC.exe"), *args]
        env = None
    else:
        cmd = ["wine", "UCC.exe", *args]
        env = dict(os.environ, WINEPREFIX=str(hp2paths.wineprefix()), WINEDEBUG="-all")
    result = subprocess.run(cmd, cwd=sysdir, env=env, capture_output=True, text=True, errors="replace")
    return result.stdout + result.stderr


# --- patches ----------------------------------------------------------------

HUNK = re.compile(rb"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def split_lines(data: bytes) -> list[bytes]:
    lines = data.split(b"\n")
    out = [line + b"\n" for line in lines[:-1]]
    if lines[-1]:
        out.append(lines[-1])
    return out


def apply_patch(original: bytes, patch: bytes) -> bytes:
    """Apply a unified diff exactly (no fuzz), byte for byte (CRLF kept)."""
    src = split_lines(original)
    plines = split_lines(patch)
    out: list[bytes] = []
    pos = 0
    i = 0
    while i < len(plines):
        m = HUNK.match(plines[i])
        if not m:
            i += 1
            continue
        old_start, old_len = int(m.group(1)), int(m.group(2) or 1)
        start = old_start - 1 if old_len else old_start
        if start < pos:
            raise ToolError("overlapping hunks")
        out.extend(src[pos:start])
        pos = start
        i += 1
        while i < len(plines) and plines[i][:1] in (b" ", b"-", b"+", b"\\"):
            line = plines[i]
            tag, body = line[:1], line[1:]
            if i + 1 < len(plines) and plines[i + 1].startswith(b"\\"):
                body = body.rstrip(b"\n")   # "\ No newline at end of file"
            if tag == b"\\":
                i += 1
                continue
            if tag in (b" ", b"-"):
                if pos >= len(src) or src[pos] != body:
                    raise ToolError(f"patch context mismatch at line {pos + 1}")
                pos += 1
                if tag == b" ":
                    out.append(body)
            else:
                out.append(body)
            i += 1
    out.extend(src[pos:])
    return b"".join(out)


def make_patch(original: bytes, patched: bytes, rel: str) -> bytes:
    a, b = split_lines(original), split_lines(patched)
    diff = difflib.diff_bytes(difflib.unified_diff, a, b, f"a/{rel}".encode(), f"b/{rel}".encode(), n=3)
    out = []
    for line in diff:
        if line.endswith(b"\n"):
            out.append(line)
        else:   # last line of a file without a trailing newline
            out.append(line + b"\n\\ No newline at end of file\n")
    return b"".join(out)


def manifest_entries() -> list[str]:
    return [l.strip() for l in MANIFEST.read_text().splitlines() if l.strip() and not l.lstrip().startswith("#")]


def game_file(rel: str) -> Path:
    # Manifest paths use "system/"; resolve against the real System folder.
    if rel.lower().startswith("system/"):
        return hp2paths.system_dir() / rel.split("/", 1)[1]
    return GAMEDIR / rel


# --- commands -----------------------------------------------------------------

def cmd_paths(_args):
    say(f"resources : {RES}")
    say(f"assets    : {ASSETS}")
    say(f"game      : {GAMEDIR}  ({'found' if (hp2paths.system_dir() / 'Game.exe').exists() else 'Game.exe NOT found'})")
    if not IS_WINDOWS:
        say(f"wineprefix: {hp2paths.wineprefix()}")
    say(f"documents : {hp2paths.documents_dir()}")


def apply_stock_patches():
    # A fresh M212 install ships hgame.u compiled, without its source, but
    # `ucc make` rebuilds HGame from HGame/Classes: fill in every class the
    # game folder lacks from the clean export (existing files are kept).
    classes = GAMEDIR / "HGame" / "Classes"
    classes.mkdir(parents=True, exist_ok=True)
    have = {p.name.lower() for p in classes.glob("*.uc")}
    added = 0
    for src in (STOCK_ORIGINAL / "HGame" / "Classes").glob("*.uc"):
        if src.name.lower() not in have:
            shutil.copyfile(src, classes / src.name)
            added += 1
    if added:
        say(f"added {added} stock classes from the clean export")
    n = 0
    for patch in sorted((PATCHES / "HGame" / "Classes").glob("*.patch")):
        rel = f"HGame/Classes/{patch.name[:-len('.patch')]}"
        original = STOCK_ORIGINAL / rel
        if not original.exists():
            raise ToolError(f"no clean export of {rel} in {STOCK_ORIGINAL} (see docs/building.md)")
        (GAMEDIR / rel).write_bytes(apply_patch(original.read_bytes(), patch.read_bytes()))
        n += 1
    say(f"applied {n} stock patches")


def restore_stock():
    patched = copied = 0
    for rel in manifest_entries():
        patch = PATCHES / f"{rel}.patch"
        if patch.exists() and (STOCK_ORIGINAL / rel).exists():
            game_file(rel).write_bytes(apply_patch((STOCK_ORIGINAL / rel).read_bytes(), patch.read_bytes()))
            patched += 1
        elif (SNAPSHOT / rel).exists():
            shutil.copyfile(SNAPSHOT / rel, game_file(rel))
            copied += 1
        else:
            raise ToolError(f"no patch/original or snapshot for {rel}")
    say(f"restored stock files: {patched} from original+patch, {copied} from snapshot")


def install_data():
    import generate_lang_credits
    import generate_native_lang_names
    import generate_native_text
    import merge_dialog_text

    sysdir = hp2paths.system_dir()
    # The merge reads the stock originals from *.orig-backup: make those once,
    # before the first merged install overwrites the stock files.
    for name in ("hpdialog.int", "BumpDialog.int", "HPMenu.int"):
        stock = find_file(sysdir, name)
        backup = find_file(sysdir, f"{name}.orig-backup")
        if not backup.exists():
            shutil.copyfile(stock, sysdir / f"{stock.name}.orig-backup")
    LOCALIZATION_DIR.mkdir(parents=True, exist_ok=True)
    for name in ("HPdialog.int", "BumpDialog.int", "HPMenu.int"):
        merge_dialog_text.merge(name, LOCALIZATION_DIR / name)
    generate_lang_credits.main()
    generate_native_text.main()
    generate_native_lang_names.main()
    shutil.copyfile(LOCALIZATION_DIR / "HPdialog.int", find_file(sysdir, "hpdialog.int"))
    shutil.copyfile(LOCALIZATION_DIR / "BumpDialog.int", find_file(sysdir, "BumpDialog.int"))
    shutil.copyfile(LOCALIZATION_DIR / "HPMenu.int", find_file(sysdir, "HPMenu.int"))
    for name in ("LangCredits.dat", "NativeLangNames.dat", "HpDialog.jap.backup", "BumpDialog.jap.backup",
                 "HpDialog.rus.backup", "BumpDialog.rus.backup"):
        shutil.copyfile(LOCALIZATION_DIR / name, find_file(sysdir, name))
    say("installed generated text data")


def build(apply_patches=False, restore=False, data=False):
    require_game_closed()
    require_game()
    if restore:
        restore_stock()
    if apply_patches:
        apply_stock_patches()
    if data:
        install_data()

    classes = GAMEDIR / "HGame" / "Classes"
    for f in MOD_CLASSES.glob("*.uc"):
        shutil.copyfile(f, classes / f.name)
    for sub, src in (("Flags", ART / "flags"), ("LangPicker", ART / "icons")):
        dst = GAMEDIR / "HGame" / "Textures" / sub
        dst.mkdir(parents=True, exist_ok=True)
        for png in src.glob("*.png"):
            shutil.copyfile(png, dst / png.name)

    hgame = find_file(hp2paths.system_dir(), "hgame.u")
    before = hgame.stat().st_mtime if hgame.exists() else 0
    time.sleep(1)
    log = ucc("make")
    if "Success - 0 error(s)" not in log or ": Error" in log:
        errors = [l for l in log.splitlines() if ": Error" in l or "error(s)" in l or "Failure" in l]
        log_path = BUILD_DIR / "ucc-make.log"
        BUILD_DIR.mkdir(parents=True, exist_ok=True)
        log_path.write_text(log)
        raise ToolError("BUILD FAILED\n" + "\n".join(errors[-20:]) + f"\n(full log: {log_path})")
    if not hgame.exists() or hgame.stat().st_mtime <= before:
        raise ToolError("hgame.u was not rewritten -- is the game running?")
    data_bytes = hgame.read_bytes()
    missing = [f.stem for f in MOD_CLASSES.glob("*.uc") if f.stem.encode() not in data_bytes]
    missing += [t for t in CUSTOM_TEXTURES if t.encode() not in data_bytes]
    if missing:
        raise ToolError("BUILD INCOMPLETE, not in hgame.u: " + ", ".join(missing))
    say(f"build OK: hgame.u {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(hgame.stat().st_mtime))}, "
        f"{len(list(MOD_CLASSES.glob('*.uc')))} mod classes verified")


def cmd_build(args):
    build(apply_patches=args.apply_patches, restore=args.restore_stock, data=args.data)


def import_audio(lang: str, src: Path):
    require_game_closed()
    require_game()
    code = lang.upper()
    pkg = f"AllDialog_{code}"
    wavs = sorted(p for p in Path(src).rglob("*") if p.suffix.lower() == ".wav")
    if not wavs:
        raise ToolError(f"no .wav files in {src}")
    stage = GAMEDIR / f"tmp_import_{code}"
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir(parents=True)
    try:
        for w in wavs:   # flat: object names are the file names
            shutil.copyfile(w, stage / w.name)
        sysdir = hp2paths.system_dir()
        find_file(sysdir, f"{pkg}.uax").unlink(missing_ok=True)
        ucc("pkg", "import", "sound", pkg, ucc_path(stage), "nocompress", "lipsync")
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    built = find_file(sysdir, f"{pkg}.uax")
    if not built.exists() or built.stat().st_size == 0:
        raise ToolError(f"{pkg}: import failed")
    # pkg import saves into System/, but the engine only searches ../Sounds/*.uax.
    sounds = GAMEDIR / "Sounds"
    sounds.mkdir(exist_ok=True)
    target = find_file(sounds, f"{pkg}.uax")
    target.unlink(missing_ok=True)
    shutil.move(str(built), str(target))
    count = len({w.name.lower() for w in wavs})
    lip = ucc("haslipsync", pkg).count("has lipsync")
    say(f"{pkg}: {count} wavs imported, {lip} with lipsync")
    if lip != count:
        raise ToolError(f"{pkg}: lipsync count mismatch ({lip} of {count})")


def cmd_import_audio(args):
    import_audio(args.lang, Path(args.dir))


def cmd_normalize(args):
    import normalize_dialog_loudness
    normalize_dialog_loudness.main(args.langs)


def cmd_snapshot(_args):
    n = 0
    for rel in manifest_entries():
        src = game_file(rel)
        if not src.exists():
            raise ToolError(f"missing in the game folder: {rel}")
        dst = SNAPSHOT / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        n += 1
    say(f"snapshot: {n} files -> {SNAPSHOT}")


def cmd_make_patches(_args):
    out_dir = PATCHES / "HGame" / "Classes"
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.patch"):
        old.unlink()
    n = 0
    for rel in manifest_entries():
        if not rel.startswith("HGame/Classes/"):
            continue
        original = STOCK_ORIGINAL / rel
        if not original.exists():
            raise ToolError(f"no clean export of {rel} in {STOCK_ORIGINAL}")
        patch = make_patch(original.read_bytes(), (GAMEDIR / rel).read_bytes(), rel)
        if not patch:
            raise ToolError(f"no changes in {rel}?")
        (PATCHES / f"{rel}.patch").write_bytes(patch)
        n += 1
    say(f"wrote {n} patches to {out_dir}")


# --- private asset zip ----------------------------------------------------------

def zip_members():
    """(path, arcname) of every local asset worth keeping: language sources
    (audio + text, not the raw .uax packages) and the clean stock export."""
    for p in sorted(LANGS_DIR.rglob("*")):
        rel = p.relative_to(ASSETS)
        if not p.is_file() or "_2002_subtitle_only" in rel.parts:
            continue
        if p.name.lower().endswith(("_uax", ".uax")):
            continue
        yield p, rel.as_posix()
    for p in sorted(STOCK_ORIGINAL.rglob("*")):
        if p.is_file():
            yield p, p.relative_to(ASSETS).as_posix()


def cmd_pack_assets(args):
    out = Path(args.out).expanduser().resolve()
    if RES in out.parents and ASSETS not in out.parents:
        raise ToolError("refusing to write the private zip inside the repository")
    members = list(zip_members())
    if not members:
        raise ToolError(f"nothing to pack under {ASSETS}")
    langs = sorted({m[1].split("/")[2] for m in members if m[1].startswith("audio_source/langs/")})
    total = sum(p.stat().st_size for p, _ in members)
    say(f"packing {len(members)} files ({total / 2**30:.1f} GiB), languages: {' '.join(langs)}")
    tmp = out.with_suffix(out.suffix + ".part")
    with zipfile.ZipFile(tmp, "w", allowZip64=True) as z:
        z.writestr("HP2MOD-ASSETS.txt",
                   "Private HP2 Language Randomizer assets -- contains game content. Do not share.\n"
                   f"languages: {' '.join(langs)}\nfiles: {len(members)}\n")
        for i, (p, arc) in enumerate(members, 1):
            method = zipfile.ZIP_STORED if p.suffix.lower() == ".wav" else zipfile.ZIP_DEFLATED
            z.write(p, arc, compress_type=method)
            if i % 5000 == 0:
                say(f"  {i}/{len(members)}")
    tmp.replace(out)
    say(f"wrote {out} ({out.stat().st_size / 2**30:.1f} GiB)")


def extract_assets(zip_path: Path):
    with zipfile.ZipFile(zip_path) as z:
        names = z.namelist()
        if "HP2MOD-ASSETS.txt" not in names:
            raise ToolError(f"{zip_path} isn't an hp2mod assets zip")
        root = ASSETS.resolve()
        for name in names:
            if name == "HP2MOD-ASSETS.txt":
                continue
            target = (ASSETS / name).resolve()
            if root not in target.parents:
                raise ToolError(f"unsafe path in zip: {name}")
        say(f"extracting {len(names) - 1} files to {ASSETS}")
        z.extractall(ASSETS, [n for n in names if n != "HP2MOD-ASSETS.txt"])


DEFAULT_ZIP = Path.home() / "hp2-language-assets.zip"


def s3_client():
    import s3
    try:
        settings = s3.load_settings()
    except s3.S3Error as e:
        raise ToolError(str(e))
    return s3, s3.Client(settings), settings


def cmd_upload_assets(args):
    s3, client, settings = s3_client()
    path = Path(args.file).expanduser()
    if not path.exists():
        raise ToolError(f"{path} not found (make it with `hp2mod pack-assets`)")
    say(f"hashing {path} ...")
    digest = s3.sha256_file(path)
    size = path.stat().st_size
    say(f"uploading to s3://{settings.bucket}/{settings.key} ({size / 2**30:.2f} GiB)")
    try:
        client.upload_file(path, settings.key, {"sha256": digest}, progress=say)
        info = client.head(settings.key)
    except s3.S3Error as e:
        raise ToolError(str(e))
    if not info or int(info.get("content-length", -1)) != size or info.get("x-amz-meta-sha256") != digest:
        raise ToolError(f"upload verification failed: {info}")
    say(f"uploaded and verified: {size} bytes, sha256 {digest[:16]}...")


def download_assets(out: Path) -> Path:
    s3, client, settings = s3_client()
    try:
        info = client.head(settings.key)
        if not info:
            raise ToolError(f"s3://{settings.bucket}/{settings.key} not found")
        say(f"downloading s3://{settings.bucket}/{settings.key} -> {out}")
        digest = client.download_file(settings.key, out, progress=say)
    except s3.S3Error as e:
        raise ToolError(str(e))
    expected = info.get("x-amz-meta-sha256")
    if expected and expected != digest:
        out.unlink(missing_ok=True)
        raise ToolError("checksum mismatch after download (file removed)")
    say(f"downloaded and verified ({'sha256 ' + digest[:16] + '...' if expected else 'no stored checksum'})")
    return out


def cmd_download_assets(args):
    download_assets(Path(args.out).expanduser())


def cmd_install(args):
    require_game_closed()
    require_game()
    if args.from_s3:
        args.from_zip = str(download_assets(DEFAULT_ZIP if not args.from_zip else Path(args.from_zip)))
    if args.from_zip:
        extract_assets(Path(args.from_zip))
    if not LANGS_DIR.is_dir():
        raise ToolError(f"no language sources in {LANGS_DIR}")
    import normalize_dialog_loudness
    say("normalizing loudness (this takes a while)...")
    normalize_dialog_loudness.main([])
    normalized = BUILD_DIR / "normalized"
    for lang in IMPORTED_LANGS:
        src = normalized / lang if (normalized / lang).is_dir() else LANGS_DIR / lang / "audio"
        if not src.is_dir():
            say(f"{lang}: no audio, skipped")
            continue
        import_audio(lang, src)
    build(apply_patches=True, data=True)


def cmd_run(args):
    import check_log
    require_game()
    if args.res:
        if game_running():
            raise ToolError("the game is already running -- close it before changing --res")
        m = re.fullmatch(r"(\d+)x(\d+)", args.res)
        if not m:
            raise ToolError("--res needs WxH, e.g. 1200x900")
        ini = hp2paths.documents_dir() / "Game.ini"
        data = ini.read_bytes()
        start = data.index(b"[WinDrv.WindowsClient]")
        end = data.find(b"\n[", start + 1)
        end = len(data) if end < 0 else end
        section = re.sub(rb"WindowedViewportX=\d+", b"WindowedViewportX=" + m.group(1).encode(), data[start:end])
        section = re.sub(rb"WindowedViewportY=\d+", b"WindowedViewportY=" + m.group(2).encode(), section)
        ini.write_bytes(data[:start] + section + data[end:])
        say(f"window size set to {m.group(1)}x{m.group(2)}")
    sysdir = hp2paths.system_dir()
    if IS_WINDOWS:
        cmd = [str(sysdir / "Game.exe"), "-log", *args.game_args]
        env = None
    else:
        cmd = ["wine", "Game.exe", "-log", *args.game_args]
        env = dict(os.environ, WINEPREFIX=str(hp2paths.wineprefix()))
    say("starting the game...")
    subprocess.run(cmd, cwd=sysdir, env=env)
    say("game exited\n")
    check_log.main([])


def cmd_check_log(args):
    import check_log
    check_log.main([args.file] if args.file else [])


def main(argv=None):
    parser = argparse.ArgumentParser(prog="hp2mod", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("paths").set_defaults(func=cmd_paths)
    p = sub.add_parser("build")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--apply-patches", action="store_true", help="stock classes = clean export + patches/")
    g.add_argument("--restore-stock", action="store_true", help="also restore generated files from the snapshot")
    p.add_argument("--data", action="store_true", help="regenerate and install the text data")
    p.set_defaults(func=cmd_build)
    p = sub.add_parser("import-audio")
    p.add_argument("lang")
    p.add_argument("dir")
    p.set_defaults(func=cmd_import_audio)
    p = sub.add_parser("normalize")
    p.add_argument("langs", nargs="*")
    p.set_defaults(func=cmd_normalize)
    sub.add_parser("snapshot").set_defaults(func=cmd_snapshot)
    sub.add_parser("make-patches").set_defaults(func=cmd_make_patches)
    p = sub.add_parser("pack-assets")
    p.add_argument("--out", default=str(Path.home() / "hp2-language-assets.zip"))
    p.set_defaults(func=cmd_pack_assets)
    p = sub.add_parser("upload-assets")
    p.add_argument("--file", default=str(Path.home() / "hp2-language-assets.zip"))
    p.set_defaults(func=cmd_upload_assets)
    p = sub.add_parser("download-assets")
    p.add_argument("--out", default=str(Path.home() / "hp2-language-assets.zip"))
    p.set_defaults(func=cmd_download_assets)
    p = sub.add_parser("install")
    p.add_argument("--from-zip", metavar="FILE", help="assets zip (with --from-s3: where to save it)")
    p.add_argument("--from-s3", action="store_true", help="download the assets zip from S3 first")
    p.set_defaults(func=cmd_install)
    p = sub.add_parser("run")
    p.add_argument("--res", metavar="WxH")
    p.add_argument("game_args", nargs=argparse.REMAINDER)
    p.set_defaults(func=cmd_run)
    p = sub.add_parser("check-log")
    p.add_argument("file", nargs="?")
    p.set_defaults(func=cmd_check_log)
    args = parser.parse_args(argv)
    try:
        args.func(args)
    except ToolError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    except SystemExit as e:
        # The data scripts stop with SystemExit("message") on bad input.
        if e.code not in (None, 0):
            print(f"error: {e.code}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
