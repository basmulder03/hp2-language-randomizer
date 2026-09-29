"""Even out dialogue loudness between languages.

Measures every language's speech loudness (median over its lines of the RMS
of each line's loudest half of 50 ms windows, so pauses don't count), then
writes gain-adjusted copies of each dubbed language's .wav files so its
median lands on the median across all languages. One constant gain per
language keeps each dub's own internal dynamics; a line that would clip
after a boost gets just enough less gain to stay under full scale.

Source .wavs in assets/audio_source/langs/<lang>/audio/ are never modified.
Output: assets/build/normalized/<lang>/*.wav (flat), ready for
`wine UCC.exe pkg import sound "AllDialog_<LANG>" <dir> nocompress lipsync`.

usa/int are measured (they set the reference) but not rewritten: int lives
in the stock AllDialog package, and both sit within ~0.3 dB of the median.

Usage: python3 tools/scripts/normalize_dialog_loudness.py [lang ...]
"""
import array
import math
import statistics
import sys
import wave
from pathlib import Path

from hp2paths import LANGS_DIR, BUILD_DIR

OUT_DIR = BUILD_DIR / "normalized"
REFERENCE_ONLY = {"usa", "int"}
MIN_ADJUST_DB = 0.5  # smaller differences aren't worth a re-import
WINDOW = 1102        # ~50 ms at 22050 Hz


def wav_files(lang: str) -> list[Path]:
    return sorted((LANGS_DIR / lang / "audio").rglob("*.wav"))


def read_samples(path: Path):
    with wave.open(str(path)) as w:
        params = w.getparams()
        if params.sampwidth != 2:
            return params, None
        return params, array.array("h", w.readframes(params.nframes))


def speech_db(samples) -> float | None:
    if samples is None or len(samples) < 2 * WINDOW:
        return None
    energies = []
    for i in range(0, len(samples) - WINDOW, WINDOW):
        chunk = samples[i:i + WINDOW]
        energies.append(sum(x * x for x in chunk) / WINDOW)
    energies.sort()
    loud = energies[len(energies) // 2:]
    mean = sum(loud) / len(loud)
    if mean <= 0:
        return None
    db = 10 * math.log10(mean / 32768 ** 2)
    return db if db > -60 else None


def language_median(lang: str) -> float:
    values = [db for db in (speech_db(read_samples(p)[1]) for p in wav_files(lang)) if db is not None]
    return statistics.median(values)


def write_scaled(src: Path, dst: Path, gain_db: float) -> bool:
    params, samples = read_samples(src)
    if samples is None:
        dst.write_bytes(src.read_bytes())
        return False
    peak = max((abs(x) for x in samples), default=0)
    gain = 10 ** (gain_db / 20)
    limited = False
    if peak and peak * gain > 32767:
        gain = 32767 / peak
        limited = True
    out = array.array("h", (max(-32768, min(32767, int(round(x * gain)))) for x in samples))
    with wave.open(str(dst), "wb") as w:
        w.setparams(params)
        w.writeframes(out.tobytes())
    return limited


def main(argv=None):
    langs = sorted(p.name for p in LANGS_DIR.iterdir() if wav_files(p.name))
    medians = {lang: language_median(lang) for lang in langs}
    reference = statistics.median(medians.values())
    print(f"reference (median of languages): {reference:.1f} dBFS")
    wanted = set(sys.argv[1:] if argv is None else argv) or set(langs)
    for lang in langs:
        gain = reference - medians[lang]
        note = ""
        if lang in REFERENCE_ONLY:
            note = "reference only"
        elif abs(gain) < MIN_ADJUST_DB:
            note = "within tolerance"
        elif lang in wanted:
            out = OUT_DIR / lang
            out.mkdir(parents=True, exist_ok=True)
            limited = sum(write_scaled(p, out / p.name, gain) for p in wav_files(lang))
            note = f"wrote {len(wav_files(lang))} files ({limited} peak-limited)"
        print(f"{lang:6} median {medians[lang]:6.1f} dBFS  gain {gain:+5.1f} dB  {note}")


if __name__ == "__main__":
    main()
