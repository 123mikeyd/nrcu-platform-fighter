extends Control
# CursorAnchor — the hand's CLICK/FINGERTIP hotspot (Step 0 §12.1, Doc 03 §6).
#
# WHY THIS IS A RULE, NOT A NUMBER
#   The anchor IS the hand's fingertip. The hand sprite draws DOWN-RIGHT of it
#   (hand_point.png 137x160 at HAND_SCALE 0.33 => the body reaches ~45 px right
#   and ~53 px below the tip), so where the anchor sits decides two things at
#   once: what the player can click, and what the hand covers.
#
#   The previous generation authored every pose as "just left of the label"
#   (Main's rail anchored 40 px left of the menu plate) — a reach-correct but
#   optically wrong hand that reads as pointing at nothing
#   ("der Mouse-Hover liegt links neben den Menü-Elementen").
#
# THE DEFAULT (this file, everywhere)
#   anchor = host_rect.position + host_rect.size * Vector2(x_ratio, y_ratio)
#            + optical_offset
#   The default ratio lands on the LOWER-RIGHT / LOWER-CENTRAL part of the
#   host's rect: the fingertip is ON the actionable surface (the hand reads as
#   ready to click that item) while the hand body — which draws down-right —
#   stays clear of a left-aligned label.
#
# PER-CONTROL OVERRIDES (authored; an authored value always wins)
#   * host_path                     point the rule at another control when the
#                                   anchor is authored as a sibling (a header
#                                   back button, a modal action, a tile's
#                                   portrait area). Empty = the parent.
#   * x_ratio / y_ratio / optical_offset   an authored ratio tweak (e.g. 0.79
#                                   for the Main rail, or a mirrored 0.20 when
#                                   the control's text is right-aligned).
#   * place_at(point)               an explicitly authored POINT in the host's
#                                   own coordinates — used by the components
#                                   that compute proportional geometry from
#                                   their own size (FighterTile, PlayerBay,
#                                   ReadyBand, Stage Select's tiles).
#
# The rule RE-RESOLVES (guarded by an equality check, so a stable layout costs
# one comparison) because a resolution change, a rebuilt roster or a modal that
# moves its plate must never leave the hand pointing at a stale spot. It never
# touches the host's layout: size stays 0 and the anchor ignores the mouse.

const DEFAULT_X_RATIO := 0.80
const DEFAULT_Y_RATIO := 0.72

# The drawn hand's reach from its fingertip, at HAND_SCALE 0.33 (hand_point.png
# 137x160 with the tip at (15.5, 1)): the sprite covers 5.1 px LEFT of the tip
# and 39.8 px right / 52.1 px below it — the hand is a 45x53 px body around a
# point. Components that author a pose close to a label use these to keep the
# DRAWN body off the text, never a guessed margin.
const HAND_REACH_LEFT := 5.2
const HAND_REACH_DOWN := 52.1

# An authored override: which control the rule measures, and where inside it.
@export var host_path := NodePath("")
@export var x_ratio := DEFAULT_X_RATIO
@export var y_ratio := DEFAULT_Y_RATIO
@export var optical_offset := Vector2.ZERO

var _authored_point := false
var _resolved := false
var _last := Vector2.ZERO

func _ready() -> void:
	# An anchor is pure measurement geometry: it must never eat a pointer event.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ZERO
	_resolve()

func anchor_position() -> Vector2:
	return get_global_rect().position

func anchor_host() -> Control:
	# The control whose rect the rule measures (an explicit host_path when the
	# anchor is authored as a sibling, else the parent component).
	if host_path != NodePath(""):
		var node := get_node_or_null(host_path)
		if node is Control and is_instance_valid(node):
			return node as Control
	var parent := get_parent()
	return parent as Control if parent is Control else null

func anchor_ratio() -> Vector2:
	return Vector2(x_ratio, y_ratio)

func place_at(at: Vector2) -> void:
	# An authored POINT in the host's coordinates: it wins over the ratio rule.
	_authored_point = true
	position = at
	size = Vector2.ZERO

func _resolve() -> void:
	if _authored_point:
		return
	var host := anchor_host()
	if host == null or not is_instance_valid(host):
		return
	var rect := host.get_global_rect()
	var at := rect.position + rect.size * Vector2(x_ratio, y_ratio) + optical_offset
	if _resolved and at.is_equal_approx(_last):
		return
	_last = at
	_resolved = true
	global_position = at

func _process(_delta: float) -> void:
	_resolve()
