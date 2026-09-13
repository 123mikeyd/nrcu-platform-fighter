extends Control
# CursorAnchor — authored focus-cursor placement (Step 0 §12.1).
#
# Every selectable component that can own controller/keyboard focus exposes
# one of these. The focus-mode hand settles exactly here, so placement is
# authored per element (hand beside a label, at an action hotspot, below a
# prompt) instead of being inferred from a generic rect center.
#
# Lives inside the centered ReferenceFrame, so anchor global positions inherit
# the frame's aspect-ratio offset automatically (Doc 01 §4A).

func anchor_position() -> Vector2:
    return get_global_rect().position

func place_at(at: Vector2) -> void:
    position = at
    size = Vector2.ZERO
