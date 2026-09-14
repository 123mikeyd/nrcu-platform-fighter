"""Mask the BAKED coin out of assets/ui/hand_carry.png -> assets/ui/hand_hold.png.

Why
---
hand_carry.png is the artist's top-left grip pose (hand_sheet_v3.png, top-left
cell) baked into a production sprite WITH a per-player token already drawn in
the pocket - a red disc carrying a "P1" label.  Player identity must never be
baked into hand art (Doc 01 §5, ledger C-008, G-031), so the carry pose has to
be the same grip with the coin removed; the per-player PlayerTokenView is drawn
separately, under the hand.

Method (the documented coin-removal recipe, used for the two earlier passes)
---------------------------------------------------------------------------
Work inside the measured coin disc only.  A pixel is CLEARED when either

  (a) it is coin by colour - the bright red fill, the darker red shaded rim,
      the pink upper-left highlight and the warm cream of the "P1" label
      ("barrier" below); or
  (b) it is not a GLOVE pixel: nothing that the glove could be - the white
      body, its grey/blue shading, its dark ink outline and the ink ring of
      the label - survives unless it lies within GLOVE_RADIUS of a bright
      NEUTRAL glove pixel.  The fingers curl over the coin's right/lower edge
      and the finger that closes under it hugs the glove body, so their
      contour lines sit 1-2 px from white glove and are kept; the label's ink
      ring and its greenish anti-aliasing sit in the middle of red and are
      cleared.  "Neutral" is what keeps the baked label apart from the glove:
      the glove is neutral/cool (r-b <= 12), the label's shaded greys are warm
      (r-b ~ 23).

Outside the disc NOTHING is touched: canvas, soft shading and every pixel
beyond the disc stay byte-identical to hand_carry.png.

Disc measured on hand_carry.png itself: RANSAC circle fit on the red-fill
boundary -> centre (34.41, 33.45), fill radius 30.67; the outermost coin pixel
is at radius 31.28.  The sheet's chroma disc maps to (36.9, 36.5) r 33.3, so
the baked coin is drawn ~2.5 px up-left of the chroma disc and ~2.6 px smaller.

Run:  python tools/mask_carry_coin.py
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "assets" / "ui" / "hand_carry.png"
OUT = REPO / "assets" / "ui" / "hand_hold.png"
PREVIEW = REPO / ".verification" / "carryv2"

COIN_CENTRE = (34.45, 33.46)
DISC_RADIUS = 32.00          # mask disc: covers the coin (max coin radius 31.28)
GLOVE_RADIUS = 6.0           # a pixel nearer than this to bright glove is glove

REDISH_MARGIN = 16           # r > g/b + this            -> coin red
WARM_MARGIN = 12             # r - b > this              -> coin / label warm
CREAM_R = 28                 # label fill: r-b > 28 and g-b > 8
NEUTRAL_TOL = 28             # max channel spread of a neutral white
BRIGHT = 150                 # min channel of a bright glove pixel


def classify(rgba: np.ndarray):
    a = rgba[:, :, 3].astype(np.int32)
    rgb = rgba[:, :, :3].astype(np.int32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    opaque = a > 16
    redish = opaque & (r > g + REDISH_MARGIN) & (r > b + REDISH_MARGIN)
    warm = opaque & ((r - b) > WARM_MARGIN)
    cream = opaque & (r > b + CREAM_R) & (g > b + 8)
    barrier = redish | warm | cream
    neutral = (mx - mn) <= NEUTRAL_TOL
    bright_glove = opaque & neutral & (mx > BRIGHT) & ((r - b) <= WARM_MARGIN)
    return barrier, bright_glove


def main() -> None:
    src = np.array(Image.open(SRC).convert("RGBA"))
    h, w = src.shape[:2]
    out = src.copy()

    yy, xx = np.mgrid[0:h, 0:w]
    d2 = (xx - COIN_CENTRE[0]) ** 2 + (yy - COIN_CENTRE[1]) ** 2
    disc = d2 <= DISC_RADIUS ** 2

    opaque = src[:, :, 3] > 16
    barrier, bright_glove = classify(src)
    dist = ndimage.distance_transform_edt(~bright_glove)
    is_glove = bright_glove | (dist <= GLOVE_RADIUS)

    remove = disc & opaque & (barrier | ~is_glove)
    remove &= ~bright_glove             # a bright neutral glove pixel never goes
    out[remove] = (0, 0, 0, 0)

    Image.fromarray(out, "RGBA").save(OUT)

    # --- report ------------------------------------------------------------
    rgbS = src[:, :, :3].astype(np.int32)
    mx = rgbS.max(axis=2)
    keep = disc & opaque & ~remove
    print(f"source                : {SRC.name} {w}x{h}")
    print(f"mask disc             : centre {COIN_CENTRE} r {DISC_RADIUS} "
          f"({int(disc.sum())} px), opaque {int((disc & opaque).sum())} px")
    print(f"cleared               : {int(remove.sum())} px")
    print(f"  of which coin by colour (barrier): {int((disc & opaque & barrier).sum())} px")
    print(f"  of which too far from glove      : "
          f"{int((disc & opaque & ~is_glove & ~barrier).sum())} px")
    print(f"kept                  : {int(keep.sum())} px")
    print(f"  bright glove white  : {int((keep & (mx > 150)).sum())} px")
    print(f"  dark glove outline  : {int((keep & (mx < 90)).sum())} px")
    print(f"  mid glove shading   : {int((keep & (mx >= 90) & (mx <= 150)).sum())} px")
    print(f"  max radius of a kept pixel: {np.sqrt(d2[keep]).max():.2f} px")

    left_red = keep & (rgbS[:, :, 0] > rgbS[:, :, 1] + 16) & (rgbS[:, :, 0] > rgbS[:, :, 2] + 16)
    left_warm = keep & ((rgbS[:, :, 0] - rgbS[:, :, 2]) > WARM_MARGIN)
    print(f"leftover red-ish px   : {int(left_red.sum())} (must be 0)")
    print(f"leftover warm px      : {int(left_warm.sum())} (must be 0)")

    outside = ~disc
    same = int(((out[outside] == src[outside]).all(axis=1)).sum())
    total_out = int(outside.sum())
    print(f"outside the disc      : {same}/{total_out} px byte-identical "
          f"({100.0 * same / total_out:.4f}%)")

    # --- preview: source | masked, 6x --------------------------------------
    def panel(img):
        bg = Image.new("RGBA", (w, h), (255, 0, 255, 255))
        return Image.alpha_composite(bg, Image.fromarray(img, "RGBA"))

    comp = Image.new("RGB", (w * 6 * 2, h * 6))
    comp.paste(panel(src).convert("RGB").resize((w * 6, h * 6), Image.NEAREST), (0, 0))
    comp.paste(panel(out).convert("RGB").resize((w * 6, h * 6), Image.NEAREST), (w * 6, 0))
    PREVIEW.mkdir(parents=True, exist_ok=True)
    comp.save(PREVIEW / "mask_before_after_x6.png")
    print(f"preview               : {PREVIEW / 'mask_before_after_x6.png'}")


if __name__ == "__main__":
    main()
