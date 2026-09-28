#!/usr/bin/env python3
"""Generate the 64x32 flag textures for the language pool
(assets/build/flags/Flag_<CODE>.png), rasterized from the vendored
flag-icons SVGs (third_party/flag-icons, MIT). "redub" has no country, so it
gets a drawn clapperboard (draw_redub). FlagIcons.uc imports the PNGs.

Requires Pillow and CairoSVG (e.g. in a venv:
`python3 -m venv .venv && .venv/bin/pip install pillow cairosvg`).
"""
import io
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[2]
SVG_DIR = REPO / "third_party/flag-icons/4x3"
OUT_DIR = REPO / "assets/build/flags"
W, H = 64, 32

# lang_code -> ISO 3166-1 alpha-2 country code (flag-icons filename).
# "int" ("international" English, genuinely UK-spelled/voiced dialogue --
# confirmed distinct from "usa", not a duplicate) uses the UK flag.
COUNTRY_FLAGS = {
    "bra": "br",
    "dan": "dk",
    "dut": "nl",
    "fin": "fi",
    "fre": "fr",
    "ger": "de",
    "int": "gb",
    "ita": "it",
    "jap": "jp",
    "nor": "no",
    "pol": "pl",
    "por": "pt",
    "rus": "ru",
    "spa": "es",
    "swe": "se",
    "usa": "us",
}


def draw_redub(draw: ImageDraw.ImageDraw):
    # "redub" isn't a real country -- it's the pool's redubbed/alternate-
    # audio entry, so a country flag never made sense here. A clapperboard
    # (hazard-striped clapper + dark slate + a red "recording" dot) reads
    # as "alternate audio take" at a glance, and can't be mistaken for any
    # real flag.
    draw.rectangle([0, 0, W, H], fill="#222222")
    strip_h = 9
    stripe_w = 7
    colors = ["#FFD500", "#111111"]
    x = -strip_h
    i = 0
    while x < W:
        color = colors[i % 2]
        draw.polygon(
            [(x, strip_h), (x + stripe_w, strip_h), (x + stripe_w + strip_h, 0), (x + strip_h, 0)],
            fill=color,
        )
        x += stripe_w
        i += 1
    draw.rectangle([0, strip_h, W, strip_h + 2], fill="#FFFFFF")
    cy = strip_h + 2 + (H - strip_h - 2) // 2
    draw.ellipse([W // 2 - 6, cy - 6, W // 2 + 6, cy + 6], fill="#E4002B")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for code, country in COUNTRY_FLAGS.items():
        svg_path = SVG_DIR / f"{country}.svg"
        out_path = OUT_DIR / f"Flag_{code.upper()}.png"
        png_bytes = cairosvg.svg2png(url=str(svg_path), output_width=W, output_height=H)
        img = Image.open(io.BytesIO(png_bytes)).convert("RGB")
        img.save(out_path, format="PNG")
        print(f"wrote {out_path} (from {svg_path.name})")

    img = Image.new("RGB", (W, H), "#FFFFFF")
    draw_redub(ImageDraw.Draw(img))
    out_path = OUT_DIR / "Flag_REDUB.png"
    img.save(out_path, format="PNG")
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
