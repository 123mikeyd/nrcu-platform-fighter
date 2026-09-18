"""Measure a csscarry evidence render against the geometry the SAME run printed.

Usage:
    python tools/carry_evidence_measure.py <png> <hotspot_x> <hotspot_y>

Checks, on the pixels of the PNG itself:
  1. the carried per-player token is present near the hand and how many of its
     red pixels survive (the glove draws over its near edge, so a crescent);
  2. where the red pixels sit inside the token disc (which side the glove covers);
  3. how many glove pixels land inside the token disc (fingers in front);
  4. which pose is drawn - IoU of the render's glove silhouette against each
     candidate sprite (hand_hold vs hand_point vs hand_grab vs hand_carry) at the
     sprite slot implied by the printed hotspot and the anchor tip.
"""
from pathlib import Path
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

REPO = Path(__file__).resolve().parent.parent
HAND_SCALE = 0.33
TIP_HOLD = np.array([23.1, 45.0])
TOKEN_FILL = np.array([217, 90, 79])       # Tokens.PLAYER_COLORS[0] #d95a4f
TOKEN_SIZE = 26.0
CANDIDATES = ["hand_hold", "hand_point", "hand_grab", "hand_carry"]


def glove_mask(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[:, :, 0].astype(int), rgb[:, :, 1].astype(int), rgb[:, :, 2].astype(int)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    return (mn > 150) & ((mx - mn) < 45)


def main() -> None:
    png = Path(sys.argv[1])
    img = np.array(Image.open(png).convert("RGB")).astype(int)
    h, w, _ = img.shape
    hot = np.array([float(sys.argv[2]), float(sys.argv[3])])
    print(f"render                : {png.name} {w}x{h}")
    print(f"printed hotspot       : ({hot[0]:.1f}, {hot[1]:.1f})  (token centre by contract)")

    r, g, b = img[:, :, 0], img[:, :, 1], img[:, :, 2]
    red = (np.abs(img - TOKEN_FILL[None, None, :]).max(axis=2) <= 30)
    redish = (r > g + 35) & (r > b + 35) & (r > 70)
    yy, xx = np.mgrid[0:h, 0:w]
    d2 = (xx - hot[0]) ** 2 + (yy - hot[1]) ** 2
    disc = d2 <= (TOKEN_SIZE * 0.5) ** 2
    near = d2 <= 22.0 ** 2

    print(f"token fill +-30 in disc : {int((red & disc).sum())} px "
          f"(of {int(disc.sum())} disc px)")
    print(f"red-ish px within 22 px : {int((redish & near).sum())} px near the hand")
    print(f"red-ish px within 60 px : {int((redish & (d2 <= 60 ** 2)).sum())} px")
    if (redish & disc).any():
        ys, xs = np.nonzero(redish & disc)
        cx, cy = xs.mean() - hot[0], ys.mean() - hot[1]
        print(f"red centroid offset     : ({cx:+.2f}, {cy:+.2f}) from the disc centre, "
              f"bbox x {int(xs.min())}-{int(xs.max())} y {int(ys.min())}-{int(ys.max())}")

    glove = glove_mask(img)
    inside = int((glove & disc).sum())
    print(f"glove px inside the disc: {inside} px "
          f"({'fingers overlap the token' if inside else 'no overlap'})")

    slot = hot - TIP_HOLD * HAND_SCALE
    print(f"sprite slot           : top-left ({slot[0]:.2f}, {slot[1]:.2f}) "
          f"size ({147*HAND_SCALE:.2f}, {160*HAND_SCALE:.2f}) at HAND_SCALE {HAND_SCALE}")
    win = np.zeros_like(glove)
    win[max(0, int(hot[1]) - 80):int(hot[1]) + 80,
        max(0, int(hot[0]) - 80):int(hot[0]) + 80] = True
    glove_win = glove & win
    print(f"glove px in 160x160     : {int(glove_win.sum())} px")

    results = {}
    for name in CANDIDATES:
        path = REPO / "assets" / "ui" / (name + ".png")
        if not path.exists():
            continue
        alpha = np.array(Image.open(path).convert("RGBA"))[:, :, 3]
        mw, mh = int(round(147 * HAND_SCALE)), int(round(160 * HAND_SCALE))
        m = np.array(Image.fromarray((alpha > 128).astype(np.uint8) * 255).resize(
            (mw, mh), Image.NEAREST)) > 127
        best = (0.0, None)
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                ox, oy = int(round(slot[0])) + dx, int(round(slot[1])) + dy
                if ox < 0 or oy < 0 or ox + mw > w or oy + mh > h:
                    continue
                sub = glove_win[oy:oy + mh, ox:ox + mw]
                inter = int((sub & m).sum())
                union = int((sub | m).sum())
                iou = inter / union if union else 0.0
                if iou > best[0]:
                    best = (iou, (dx, dy))
        results[name] = best
    for name, (iou, off) in sorted(results.items(), key=lambda kv: -kv[1][0]):
        print(f"pose IoU {name:<11}: {iou:.3f}  (best offset {off})")
    if results:
        win_name = max(results.items(), key=lambda kv: kv[1][0])
        print(f"POSE VERDICT          : {win_name[0]} (IoU {win_name[1][0]:.3f})")

    # --- 5. closed pinch vs POINTER, on the pixels they disagree about ------
    # The claim to falsify is "the old pointing sprite is drawn": compare the
    # render's glove mask against hold and point in the exact pixels where the
    # two sprites differ (hand_grab shares the closed-grip silhouette).
    def sprite_mask(name: str) -> np.ndarray:
        alpha = np.array(Image.open(REPO / "assets" / "ui" / (name + ".png"))
                         .convert("RGBA"))[:, :, 3]
        return np.array(Image.fromarray((alpha > 128).astype(np.uint8) * 255).resize(
            (int(round(147 * HAND_SCALE)), int(round(160 * HAND_SCALE))),
            Image.NEAREST)) > 127

    m_hold, m_point = sprite_mask("hand_hold"), sprite_mask("hand_point")
    mh, mw = m_hold.shape
    ox, oy = int(round(slot[0])) + results[win_name[0]][1][0], int(round(slot[1])) + results[win_name[0]][1][1]
    sub = glove_win[oy:oy + mh, ox:ox + mw]
    gpx = int(sub.sum())
    print(f"render glove px in slot: {gpx} px")
    print(f"agreement with hold    : {int((sub & m_hold).sum()) / max(1, gpx):.3f} of the render's glove")
    print(f"agreement with point   : {int((sub & m_point).sum()) / max(1, gpx):.3f} of the render's glove")
    d_region = m_hold ^ m_point
    print(f"hold/point silhouette delta: {int(d_region.sum())} px; of those the render "
          f"matches hold {int((sub & d_region & m_hold).sum())} px vs point "
          f"{int((sub & d_region & m_point).sum())} px")
    print(f"VERDICT               : the drawn glove is the {'CLOSED PINCH (hand_hold)' if (sub & d_region & m_hold).sum() > (sub & d_region & m_point).sum() else 'POINTER (hand_point)'}")


if __name__ == "__main__":
    main()
