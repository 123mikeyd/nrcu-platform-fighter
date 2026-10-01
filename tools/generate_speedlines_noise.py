#!/usr/bin/env python3
"""Generate deterministic 256x256 tileable radial speedline noise (stdlib only)."""
from pathlib import Path
import math
import random
import struct
import zlib

OUT = Path(__file__).resolve().parents[1] / "assets/vs/fx/speedlines_noise.png"
SIZE = 256
SEED = 20260923

def png_chunk(kind: bytes, data: bytes) -> bytes:
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)

def main() -> None:
    rng = random.Random(SEED)
    lattice = [[rng.random() for _ in range(32)] for _ in range(32)]
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        fy = y * 32 / SIZE
        iy, ty = int(fy), fy - int(fy)
        sy = ty * ty * (3 - 2 * ty)
        for x in range(SIZE):
            fx = x * 32 / SIZE
            ix, tx = int(fx), fx - int(fx)
            sx = tx * tx * (3 - 2 * tx)
            a = lattice[iy][ix]
            b = lattice[iy][(ix + 1) % 32]
            c = lattice[(iy + 1) % 32][ix]
            d = lattice[(iy + 1) % 32][(ix + 1) % 32]
            value = (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy
            rows.append(round(value * 255))
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 0, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header) + png_chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + png_chunk(b"IEND", b"")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png)
    print(f"generated {OUT} bytes={len(png)} size={SIZE} seed={SEED}")

if __name__ == "__main__":
    main()
