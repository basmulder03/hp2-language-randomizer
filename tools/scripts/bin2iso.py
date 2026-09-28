"""Convert a raw CD image (2352-byte sectors: .bin/.img dumps, e.g. from
Redumper) into a plain 2048-byte-sector ISO that 7-Zip can read.
Mode 1 sectors keep bytes 16..2064, Mode 2 Form 1 sectors bytes 24..2072.

Usage: python3 tools/scripts/bin2iso.py <image.bin> <out.iso>
"""
import os
import sys


def main():
    src, dst = sys.argv[1:3]
    size = os.path.getsize(src)
    if size % 2352:
        raise SystemExit(f"{src}: size isn't a multiple of 2352 -- probably already an ISO")
    with open(src, "rb") as f, open(dst, "wb") as out:
        for _ in range(size // 2352):
            sector = f.read(2352)
            out.write(sector[16:2064] if sector[15] == 1 else sector[24:2072])
    print(f"wrote {dst}")


if __name__ == "__main__":
    main()
