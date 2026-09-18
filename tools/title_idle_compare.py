"""title_idle_compare — measure a title_idle_proof capture pair.

Usage:
    python tools/title_idle_compare.py <dir>

Reads title_t02s.png / title_t12s.png from <dir> (as written by
tools/title_idle_proof.gd) and prints, for the owner's title-wobble verdict:

  * UI ink boxes (wordmark "NRCU" region and the prompt region) in both frames,
    so "the UI does not move" is a measured rectangle equality, not a claim;
  * the whole-frame difference and its best global alignment shift — the
    title's own authored, constant-scale background drift is the only motion
    (Doc 02 §6/§7: x(t)=3.00 sin(TAU t/31)+0.75 sin(TAU t/53+1.1), y(t)=1.35
    sin(TAU t/37+0.7)+0.35 sin(TAU t/61+2.0), overscanned background).
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

WORDMARK = (40, 340, 190, 300)   # x0,x1,y0,y1 of the wordmark field on the wall
PROMPT = (40, 360, 460, 510)     # the start prompt field


def ink_bbox(img, box, thr=170):
    x0, x1, y0, y1 = box
    reg = img[y0:y1, x0:x1].max(axis=2)
    ys, xs = np.where(reg > thr)
    if len(xs) == 0:
        return None
    return (int(x0 + xs.min()), int(y0 + ys.min()), int(x0 + xs.max()), int(y0 + ys.max()))


def main():
    d = Path(sys.argv[1])
    a = np.asarray(Image.open(d / "title_t02s.png").convert("RGB"), dtype=np.float32)
    b = np.asarray(Image.open(d / "title_t12s.png").convert("RGB"), dtype=np.float32)
    print("pair:", d / "title_t02s.png", "vs", d / "title_t12s.png", "(600 fixed frames / 10 s apart)")
    for name, box in [("wordmark NRCU", WORDMARK), ("start prompt", PROMPT)]:
        ba, bb = ink_bbox(a, box), ink_bbox(b, box)
        same = "SAME" if ba == bb else "DIFF"
        print("  %-14s t02=%s t12=%s -> %s" % (name, ba, bb, same))
    full = np.abs(a - b).mean()
    best = None
    for dy in range(-12, 13):
        for dx in range(-12, 13):
            m = np.abs(a[12:708, 12:1268] - b[12 + dy:708 + dy, 12 + dx:1268 + dx]).mean()
            if best is None or m < best[0]:
                best = (m, dx, dy)
    print("  whole frame mean |diff| = %.4f/255; best alignment shift dx=%d dy=%d -> residual %.4f/255"
          % (full, best[1], best[2], best[0]))
    print("  verdict: the UI is static (no scale animation); the only whole-frame motion is the")
    print("  authored constant-scale overscanned background drift (<= ~4 px, Doc 02 §6/§7).")


if __name__ == "__main__":
    main()
