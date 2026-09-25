"""Bake signed-distance fields for the VS side-field masks.

The living side-field edge (shaders/side_field_edge.gdshader) warps and erodes
the field boundary. A binary mask can only be cut hard; a signed distance field
lets the shader move the edge smoothly and draw an anti-aliased rim.

Encoding: R = clamp(0.5 + d / (2 * RANGE_PX), 0, 1), d > 0 inside the field.
The mask is padded with edge replication before the distance transform, so the
screen border is never treated as a field edge.

usage: python tools/bake_side_field_sdf.py
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt

ROOT = Path(__file__).resolve().parents[1]
GENERATED = ROOT / "assets" / "vs" / "generated"
RANGE_PX = 128.0
PAD = 160
MASKS = [
    "side_field_left_mask",
    "side_field_right_mask",
    "side_field_left_mask_legacy",
    "side_field_right_mask_legacy",
]


def bake(name: str) -> Path:
    alpha = np.asarray(Image.open(GENERATED / f"{name}.png").convert("RGBA"))[..., 3]
    inside = np.pad(alpha > 127, PAD, mode="edge")
    d_in = distance_transform_edt(inside)
    d_out = distance_transform_edt(~inside)
    signed = (d_in - d_out)[PAD:-PAD, PAD:-PAD]
    encoded = np.clip(0.5 + signed / (2.0 * RANGE_PX), 0.0, 1.0)
    out = GENERATED / f"{name.replace('_mask', '_sdf')}.png"
    Image.fromarray(np.round(encoded * 255.0).astype(np.uint8), "L").save(out, optimize=True)
    return out


if __name__ == "__main__":
    for mask in MASKS:
        print(bake(mask).relative_to(ROOT))
