"""Cut the carry pose (hand sheet v3, top row, cell 2 = the EMPTY pinch grip)
into assets/ui/hand_hold.png.

Method
------
1. Crop the source cell from the artist sheet (the same cell hand_grab.png was
   cut from: the four top-row cells are 56..425 / 476..858 / 902..1280 /
   1325..1738 in sheet x, row band y 131..619).
2. Background key: an explicit 8-connected flood from the cell border over
   "background" pixels (already-keyed alpha==0 OR near-white RGB).  Only
   border-connected background is cleared, so the glove's internal white, its
   soft shading, the cuff and the black outline are untouched.  Everything is
   reported so the key can be audited.
3. Scale/crop exactly like the sibling pose sprites: the content is resized so
   the pose height is 157 px inside a 147x160 canvas at (1,1) -- the same
   baseline, height and canvas size hand_grab.png uses.

Run: NRCU_HAND_SHEET=<path-to-hand_sheet_v3.png> python tools/cut_hand_hold.py
"""
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

SHEET = Path(os.environ.get(
    "NRCU_HAND_SHEET",
    str(Path.home() / "Downloads" / "hand-entwuerfe" / "hand_sheet_v3.png"),
))
OUT = Path(__file__).resolve().parent.parent / "assets" / "ui" / "hand_hold.png"
PREVIEW = Path(__file__).resolve().parent.parent / ".verification" / "carryfix-out"

# cell 2 of the top row (the empty pinch grip), in sheet pixels
CELL = (476, 177, 859, 588)
CANVAS = (147, 160)          # same canvas as hand_grab.png / hand_point.png
CONTENT = (146, 157)         # same content size as hand_grab.png
PAD = (1, 1)

# measured disc centre / radius of cell 1 (the same grip HOLDING the green
# disc) in cell-1 crop coordinates, for the anchor report
DISC_CENTRE_CELL1 = (98.19, 99.81)
DISC_R_OUTER = 98.83


def flood_background(rgba: np.ndarray) -> np.ndarray:
    """Background = pixels border-connected to alpha==0 or to near-white."""
    alpha = rgba[:, :, 3].astype(np.int32)
    rgb = rgba[:, :, :3].astype(np.int32)
    keyed = alpha < 8
    near_white = (rgb > 228).all(axis=2) & (alpha > 0)
    candidate = keyed | near_white
    labels, _ = ndimage.label(candidate, structure=np.ones((3, 3), dtype=int))
    border = np.unique(np.concatenate([labels[0, :], labels[-1, :],
                                       labels[:, 0], labels[:, -1]]))
    border = border[border != 0]
    return np.isin(labels, border)


def main() -> None:
    sheet = np.array(Image.open(SHEET).convert("RGBA"))
    cell = sheet[CELL[1]:CELL[3], CELL[0]:CELL[2]].copy()
    interior_white_before = int(((cell[:, :, 3] > 200)
                                 & (cell[:, :, :3] > 200).all(axis=2)).sum())

    background = flood_background(cell)
    cleared = background & (cell[:, :, 3] > 0)
    cell[:, :, 3] = np.where(background, 0, cell[:, :, 3])
    interior_white_after = int(((cell[:, :, 3] > 200)
                                & (cell[:, :, :3] > 200).all(axis=2)).sum())

    opaque = cell[:, :, 3] > 16
    ys, xs = np.nonzero(opaque)
    src_box = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    content = Image.fromarray(cell, "RGBA").crop(
        (src_box[0], src_box[1], src_box[2] + 1, src_box[3] + 1))

    scaled = content.resize(CONTENT, Image.LANCZOS)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    canvas.alpha_composite(scaled, PAD)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT)

    # --- report ------------------------------------------------------------
    sx = CONTENT[0] / (src_box[2] - src_box[0] + 1)
    sy = CONTENT[1] / (src_box[3] - src_box[1] + 1)
    print(f"sheet cell            : {CELL} -> content box {src_box} "
          f"({src_box[2]-src_box[0]+1}x{src_box[3]-src_box[1]+1})")
    print(f"scale (x, y)          : {sx:.5f}, {sy:.5f}")
    print(f"border-connected bg   : {int(background.sum())} px "
          f"(of which still opaque before the key: {int(cleared.sum())})")
    print(f"interior white kept   : {interior_white_before} -> {interior_white_after} px")
    print(f"outline/cuff intact   : content box covers the full pose "
          f"(min alpha>16 at {src_box[0]},{src_box[1]})")
    print(f"written               : {OUT} {canvas.size}")

    # anchored overlay proof (empty circle on the cut pose 2)
    preview = Image.new("RGBA", canvas.size, (46, 46, 58, 255))
    preview.alpha_composite(canvas)
    draw = ImageDraw.Draw(preview)
    for (cx, cy), colour in (((1 + DISC_CENTRE_CELL1[0] * sx, 1 + DISC_CENTRE_CELL1[1] * sy),
                              (255, 0, 255)),
                             ((1 + 96 * sx, 1 + 115 * sy), (0, 255, 255)),
                             ((1 + 61 * sx, 1 + 115.5 * sy), (255, 255, 0))):
        r = DISC_R_OUTER * sy
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=colour, width=1)
        draw.ellipse([cx - 1.5, cy - 1.5, cx + 1.5, cy + 1.5], fill=colour)
        print(f"candidate centre      : ({cx:.2f}, {cy:.2f}) r_out {r:.2f}")
    PREVIEW.mkdir(parents=True, exist_ok=True)
    preview.resize((CANVAS[0] * 3, CANVAS[1] * 3), Image.NEAREST).convert("RGB").save(
        PREVIEW / "hand_hold_anchor_candidates.png")


if __name__ == "__main__":
    main()
