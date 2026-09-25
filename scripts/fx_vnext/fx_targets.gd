class_name FxTargets
extends RefCounted
# NRCU FX Lab vNext — presentation target registry (Stream A/B foundation).
#
# Enumerates the real render targets of a mounted VS screen and derives the
# semantic target context plus the canonical target signature defined in
# specs/15 §9 (fixed key order, empty strings for missing fields).
#
# Pure data + node inspection: no UI, no rendering, no screen mutation.

const ROLE_IDS := {
	"VS MARK": "vs_mark",
	"PRIMARIES": "primary",
	"ECHOES": "echo",
	"NAMES": "name",
	"STAGE": "stage",
	"SIDE FIELDS": "side_field",
	"NAME PLATES": "name_plate",
	"ACCENT LINES": "accent_line",
}

# Canonical target signature key order — specs/15 §9. Do not reorder.
const SIGNATURE_ORDER: Array[String] = [
	"element_id", "fighter_id", "element_role", "visual_side",
	"presentation_slot", "team_side", "mode_family", "stage_id",
]

var screen: Node
var mode_format := "1v1"
var stage_id := "debug"

var slot_nodes: Dictionary = {}
var slot_roles: Dictionary = {}
# SP-06: document order (scene-tree traversal) is the visual stacking
# authority — never lexicographic key order. Recorded at gather time.
var slot_order: Dictionary = {}
var _order_counter := 0

var _multiplayer_layouts: Dictionary = {}

func _init() -> void:
	_multiplayer_layouts = _load_json("res://assets/vs/schema/multiplayer_layouts_1280x720.json")

# ---------------------------------------------------------------- binding

func bind_screen(screen_node: Node, format: String, stage: String) -> void:
	screen = screen_node
	mode_format = format
	stage_id = stage
	collect()

func collect() -> void:
	slot_nodes.clear()
	slot_roles.clear()
	slot_order.clear()
	_order_counter = 0
	if screen == null or not is_instance_valid(screen):
		return
	var root := screen.get_node_or_null("Root")
	if root != null:
		_gather(root)

func keys() -> Array:
	var result: Array = slot_nodes.keys()
	result.sort()
	return result

func ordered_keys() -> Array:
	# Canonical visual authority order: scene document order, key as tiebreak.
	var result: Array = slot_nodes.keys()
	result.sort_custom(func(a, b):
		var oa := int(slot_order.get(str(a), 1 << 30))
		var ob := int(slot_order.get(str(b), 1 << 30))
		if oa != ob:
			return oa < ob
		return str(a) < str(b)
	)
	return result

func order_index(key: String) -> int:
	return int(slot_order.get(key, 1 << 30))

func target_node(key: String) -> Node:
	return slot_nodes.get(key)

func composition_context() -> Dictionary:
	# Scene/Event Looks resolve against this synthetic authority instead of a
	# fighter texture. It is deliberately stable across remounts and carries
	# only the fields the assignment resolver is allowed to use.
	return {
		"target_key": "composition",
		"element_id": "composition",
		"element_role": "composition",
		"mode_family": mode_format,
		"stage_id": stage_id,
	}

func resolve_anchor(anchor: String, target_key := "") -> Vector2:
	# Return a canvas-normalized point. Custom points stay authored in the FX
	# fields; named anchors always resolve from live scene geometry.
	var requested := anchor if anchor in ["VS_MARK", "TARGET_CENTER", "LEFT_FIGHTER", "RIGHT_FIGHTER"] else "CUSTOM"
	var key := ""
	match requested:
		"VS_MARK":
			key = _first_key_for_role("VS MARK")
		"TARGET_CENTER":
			key = target_key if slot_nodes.has(target_key) else _first_key_for_role("PRIMARIES")
		"LEFT_FIGHTER":
			key = _first_key_for_side("left")
		"RIGHT_FIGHTER":
			key = _first_key_for_side("right")
	if key == "" or not slot_nodes.has(key) or not (slot_nodes[key] is TextureRect):
		return Vector2(0.5, 0.5)
	var rect := presentation_rect(slot_nodes[key] as TextureRect)
	return Vector2(clampf(rect.get_center().x / 1280.0, 0.0, 1.0), clampf(rect.get_center().y / 720.0, 0.0, 1.0))

func _first_key_for_role(role: String) -> String:
	for key in ordered_keys():
		if str(slot_roles.get(str(key), "")) == role:
			return str(key)
	return ""

func _first_key_for_side(side: String) -> String:
	for key in ordered_keys():
		var candidate := str(key)
		if visual_side_for_slot(presentation_slot_for_key(candidate)) == side and role_for_key(candidate) in ["PRIMARIES", "ECHOES"]:
			return candidate
	return ""

# ---------------------------------------------------------------- roles

func role_for_key(key: String) -> String:
	if key == "mark" or key.contains("vs_mark"):
		return "VS MARK"
	if key == "stage" or key.contains("stage"):
		return "STAGE"
	if key.contains("side_field") or key.contains("field_left") or key.contains("field_right"):
		return "SIDE FIELDS"
	if key.contains("plate"):
		return "NAME PLATES"
	if key.contains("accent"):
		return "ACCENT LINES"
	if key.contains("primary"):
		return "PRIMARIES"
	if key.contains("echo"):
		return "ECHOES"
	if key.begins_with("name") or key.contains("_name_"):
		return "NAMES"
	return "OTHER TEXTURES"

func role_id(role: String) -> String:
	return str(ROLE_IDS.get(role, role.to_snake_case()))

func fighter_id_for(node: Variant) -> String:
	if not (node is TextureRect) or node.texture == null:
		return ""
	var path := String(node.texture.resource_path)
	var parts := path.split("/")
	for i in range(parts.size() - 1):
		if parts[i] == "fighters":
			return String(parts[i + 1])
	return ""

# ---------------------------------------------------------------- semantic context

func context_for_key(key: String) -> Dictionary:
	var context := {"mode_family": mode_format, "stage_id": stage_id}
	if not slot_nodes.has(key):
		return context
	var role := str(slot_roles.get(key, "OTHER TEXTURES"))
	var node = slot_nodes[key]
	context["target_key"] = key
	context["element_role"] = role_id(role)
	var fighter_id := str(node.get_meta("fx_fighter_id", "")) if node is Node else ""
	if fighter_id == "":
		fighter_id = fighter_id_for(node)
	if fighter_id != "":
		context["fighter_id"] = fighter_id
	var presentation_slot := presentation_slot_for_key(key)
	if presentation_slot != "":
		context["presentation_slot"] = presentation_slot
		var visual_side := visual_side_for_slot(presentation_slot)
		if visual_side != "":
			context["visual_side"] = visual_side
		var team_side := team_side_for_slot(presentation_slot)
		if team_side != "":
			context["team_side"] = team_side
	if node is Node and node.has_meta("fx_visual_side"):
		context["visual_side"] = str(node.get_meta("fx_visual_side"))
	if node is Node and node.has_meta("fx_stage_id"):
		context["stage_id"] = str(node.get_meta("fx_stage_id"))
	if node is Node and node.has_meta("fx_element_id"):
		context["element_id"] = str(node.get_meta("fx_element_id"))
	elif role == "VS MARK":
		context["element_id"] = "vs_mark"
	elif role == "STAGE":
		context["element_id"] = "stage"
	return context

func context_for_target(key: String) -> Dictionary:
	# One resolver for every target identity. "composition" is synthetic and
	# must never fall through to the ordinary slot/node registry.
	return composition_context() if key == "composition" else context_for_key(key)

func signature_for_context(ctx: Dictionary) -> String:
	var parts: Array = []
	for field in SIGNATURE_ORDER:
		parts.append(str(ctx.get(field, "")))
	return "|".join(parts)

func signature_for_key(key: String) -> String:
	return signature_for_context(context_for_target(key))

# ---------------------------------------------------------------- slot semantics

func presentation_slot_for_key(key: String) -> String:
	# Resolve against the actual layout schema instead of assuming only duel/FFA
	# left/right names. Team families use slots such as A_back and B_solo.
	var candidates: Array[String] = ["left_outer", "right_outer", "left_inner", "right_inner", "center", "left", "right"]
	var families: Dictionary = _multiplayer_layouts.get("families", {})
	for family in families.values():
		if not (family is Dictionary):
			continue
		var slots: Dictionary = family.get("slots", {})
		for raw_slot in slots.keys():
			var slot := str(raw_slot).to_lower()
			if not candidates.has(slot):
				candidates.append(slot)
	candidates.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var normalized := key.to_lower()
	for candidate in candidates:
		if normalized == candidate or normalized.begins_with(candidate + "_") or normalized.contains("_" + candidate + "_") or normalized.ends_with("_" + candidate):
			return candidate
	return ""

func visual_side_for_slot(slot: String) -> String:
	if slot == "":
		return ""
	if slot in ["left", "right", "center"]:
		return slot
	var family_spec: Dictionary = (_multiplayer_layouts.get("families", {}) as Dictionary).get(mode_format, {})
	var slot_spec: Dictionary = (family_spec.get("slots", {}) as Dictionary).get(slot, {})
	var side := str(slot_spec.get("side", "")).to_lower()
	return side if side in ["left", "right", "center"] else ""

func team_side_for_slot(slot: String) -> String:
	if not mode_format.begins_with("TEAM_"):
		return ""
	if slot.begins_with("a_"):
		return "A"
	if slot.begins_with("b_"):
		return "B"
	return ""

# ---------------------------------------------------------------- scene-space helpers

static func raw_presentation_size(node: TextureRect, tex: Texture2D) -> Vector2:
	var local_size := node.size
	if local_size.x < 1.0 or local_size.y < 1.0:
		local_size = Vector2(tex.get_width(), tex.get_height())
	var transform := node.get_global_transform()
	var scale_x := maxf(transform.x.length(), 0.0001)
	var scale_y := maxf(transform.y.length(), 0.0001)
	return Vector2(maxf(local_size.x * scale_x, 1.0), maxf(local_size.y * scale_y, 1.0))

static func presentation_rect(node: TextureRect) -> Rect2:
	var xform := node.get_global_transform()
	var corners := [Vector2.ZERO, Vector2(node.size.x, 0.0), node.size, Vector2(0.0, node.size.y)]
	var first: Vector2 = xform * corners[0]
	var minp := first
	var maxp := first
	for i in range(1, corners.size()):
		var pnt: Vector2 = xform * corners[i]
		minp.x = minf(minp.x, pnt.x)
		minp.y = minf(minp.y, pnt.y)
		maxp.x = maxf(maxp.x, pnt.x)
		maxp.y = maxf(maxp.y, pnt.y)
	return Rect2(minp, maxp - minp)

static func logical_bounds(node: TextureRect) -> Rect2:
	# SP-03: vector proxies are full-canvas sampling surfaces (1280x720) —
	# their node rect is NOT the element's logical geometry. Resolve through
	# to the replaced source element (proxy name = source name + "_FXProxy",
	# same parent); otherwise the node's own presentation rect.
	if node != null and bool(node.get_meta("fx_vector_proxy", false)):
		var parent := node.get_parent()
		if parent != null:
			var source = parent.get_node_or_null(String(node.name).trim_suffix("_FXProxy"))
			if source != null and source != node:
				return node_bounds(source)
	return presentation_rect(node)

static func node_bounds(node: Node) -> Rect2:
	# Logical visual bounds for any canvas element type.
	if node is TextureRect:
		return presentation_rect(node)
	if node is Polygon2D:
		var poly := node as Polygon2D
		var xform := poly.get_global_transform()
		var first := true
		var minp := Vector2.ZERO
		var maxp := Vector2.ZERO
		for pt in poly.polygon:
			var pnt: Vector2 = xform * pt
			if first:
				minp = pnt
				maxp = pnt
				first = false
			else:
				minp.x = minf(minp.x, pnt.x)
				minp.y = minf(minp.y, pnt.y)
				maxp.x = maxf(maxp.x, pnt.x)
				maxp.y = maxf(maxp.y, pnt.y)
		if first:
			return Rect2()
		return Rect2(minp, maxp - minp)
	if node is Line2D:
		var line := node as Line2D
		var xform := line.get_global_transform()
		var first := true
		var minp := Vector2.ZERO
		var maxp := Vector2.ZERO
		for pt in line.points:
			var pnt: Vector2 = xform * pt
			if first:
				minp = pnt
				maxp = pnt
				first = false
			else:
				minp.x = minf(minp.x, pnt.x)
				minp.y = minf(minp.y, pnt.y)
				maxp.x = maxf(maxp.x, pnt.x)
				maxp.y = maxf(maxp.y, pnt.y)
		if first:
			return Rect2()
		var half := line.width * 0.5
		return Rect2(minp - Vector2(half, half), (maxp - minp) + Vector2(half * 2.0, half * 2.0))
	if node is Control:
		var control := node as Control
		return Rect2(control.get_global_transform() * Vector2.ZERO, control.size * Vector2((control.get_global_transform().x.length()), (control.get_global_transform().y.length())))
	return Rect2()

# ---------------------------------------------------------------- internals

func _gather(node: Node) -> void:
	for child in node.get_children():
		if child is TextureRect and child.texture != null and not bool(child.get_meta("fx_overscan_proxy", false)):
			var key := String(child.name).to_snake_case()
			if key not in ["shadow", "under_shadow"] and not slot_nodes.has(key):
				slot_nodes[key] = child
				slot_roles[key] = String(child.get_meta("fx_role", role_for_key(key)))
				slot_order[key] = _order_counter
				_order_counter += 1
		_gather(child)

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}
