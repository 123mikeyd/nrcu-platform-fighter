"""Compose the Pause before/after evidence sheet from the deterministic renders.

    python tools/pause_evidence_compose.py [--dir .verification/evidence/pause-owner-round]

Reads <dir>/before_*.png and <dir>/after_*.png (1280x720 renders of the same
frame; tools/pause_owner_fix_shot) and writes <dir>/pause_before_after_rows.png:
the pause plate cropped from each, BEFORE above AFTER, with the two pointer
states side by side. Pixel crops only - the renders themselves are never
touched.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw

# The pause plate plus a margin, in 1280x720 frame coordinates.
CROP = (380, 210, 900, 510)
SEPARATOR = 4
PAD = 8
CAPTION_H = 20


def crop(path: Path) -> Image.Image:
    with Image.open(path) as image:
        return image.convert('RGB').crop(CROP)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dir', default='.verification/evidence/pause-owner-round')
    args = parser.parse_args()
    directory = (Path(__file__).resolve().parent.parent / args.dir).resolve()

    panels = [
        ('BEFORE - default selection', 'before_pause_vs.png'),
        ('BEFORE - pointer on LEAVE', 'before_pause_hover_leave.png'),
        ('AFTER - default selection', 'after_pause_vs.png'),
        ('AFTER - pointer on LEAVE', 'after_pause_hover_leave.png'),
    ]
    images = [(text, crop(directory / name)) for text, name in panels]
    width = CROP[2] - CROP[0]
    height = CROP[3] - CROP[1]
    sheet = Image.new('RGB', (width * 2 + SEPARATOR + PAD * 2,
                              (height + CAPTION_H) * 2 + SEPARATOR + PAD * 2), (10, 12, 14))
    draw = ImageDraw.Draw(sheet)
    for index, (caption, image) in enumerate(images):
        row, column = divmod(index, 2)
        x = PAD + column * (width + SEPARATOR)
        y = PAD + row * (height + CAPTION_H + SEPARATOR)
        draw.text((x, y + 4), caption, fill=(240, 226, 190))
        sheet.paste(image, (x, y + CAPTION_H))
    out = directory / 'pause_before_after_rows.png'
    sheet.save(out)
    print('pause_evidence_compose: %s (%dx%d)' % (out, sheet.width, sheet.height))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
