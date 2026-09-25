"""Pixel-level regression contract for the CLASH_OVERDRIVE Lab side fields."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/vs/generated"


def alpha(path):
    return Image.open(path).convert("RGBA")


def test_candidate_fields_are_monotonic_diagonal_with_arena_gap():
    left = alpha(ASSETS / "side_field_left_mask.png")
    right = alpha(ASSETS / "side_field_right_mask.png")
    assert left.size == right.size == (1280, 720)
    # The scribble has two parallel-ish edges leaning RIGHT as they descend,
    # not mirrored inward wedges. The unpainted corridor is the arena.
    bounds = []
    for y in range(0, 720, 8):
        lx = max(x for x in range(1280) if left.getpixel((x, y))[3] > 10)
        rx = min(x for x in range(1280) if right.getpixel((x, y))[3] > 10)
        assert 45 <= rx - lx <= 220, (y, lx, rx)
        bounds.append((lx, rx))
        if y >= 8:
            prev_l, prev_r = bounds[-2]
            assert lx >= prev_l and rx >= prev_r, (y, prev_l, lx, prev_r, rx)
    assert bounds[-1][0] - bounds[0][0] > 450
    assert bounds[-1][1] - bounds[0][1] > 350
    assert bounds[0][1] - bounds[0][0] > bounds[-1][1] - bounds[-1][0]


def test_default_is_the_game_layout_diagonal_and_legacy_stays_selectable():
    text = (ROOT / "scripts/fx_vnext/fx_side_shapes.gd").read_text(encoding="utf-8")
    assert 'const DEFAULT_PRESET := "CLASH_DIAGONAL_FIELDS"' in text
    assert '"CLASH_DIAGONAL_FIELDS"' in text
    assert '"CURRENT_HOURGLASS":' in text
    assert 'side_field_left_mask_legacy.png' in text
    assert 'side_field_left_mask.png' in text


def test_diagonal_mask_matches_game_layout_polygon():
    from PIL import Image, ImageDraw
    layout = json.loads((ROOT / "assets/vs/schema/vs_layout_1280x720.json").read_text(encoding="utf-8"))["side_fields"]
    for side in ("left", "right"):
        mask = Image.open(ROOT / f"assets/vs/generated/side_field_{side}_mask.png").convert("RGBA").getchannel("A")
        poly = Image.new("L", (1280, 720))
        ImageDraw.Draw(poly).polygon([tuple(p) for p in layout[f"{side}_points"]], fill=255)
        diff = sum(1 for a, b in zip(mask.point(lambda v: 255 if v > 127 else 0).getdata(), poly.getdata()) if a != b)
        assert diff == 0, (side, diff)


def test_side_field_sdfs_are_baked_for_both_presets():
    for name in ("side_field_left_sdf", "side_field_right_sdf", "side_field_left_sdf_legacy", "side_field_right_sdf_legacy"):
        assert (ROOT / f"assets/vs/generated/{name}.png").is_file(), name


def test_live_loader_bypasses_stale_import_for_existing_png():
    text = (ROOT / "scripts/fx_vnext/fx_screen_runtime.gd").read_text(encoding="utf-8")
    assert text.index("var absolute_path := ProjectSettings.globalize_path(path)") < text.index("var imported = load(path)")


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("PASS", name)
