extends RefCounted
# LANE C / WP-7 — shared acceptance infrastructure (Doc 08 §1/§2/§5/§6).
#
# WHY THIS EXISTS
#   The acceptance harnesses drive the shipped frontends through PUBLIC input
#   (real InputEventKey / InputEventMouseButton / InputEventJoypad* delivered
#   through the engine's own input path) and then MEASURE what the player can
#   see and reach. They must not call screen-private helpers (Doc 08 §1: private
#   helper calls are allowed in GEOMETRY_FIXTURE only, forbidden as proof a user
#   can reach a state), and they must not guess at geometry: every number in a
#   report is read from the live tree.
#
# TWO ORTHOGONAL DIMENSIONS (Doc 08 §5 + the corrective pass' optical lesson)
#   REACH     — does the focus hand settle on the control's authored
#               CursorAnchor? (distance px, tolerance px)
#   OPTICAL   — is that hotspot ON the control's actionable surface? Reach can
#               be perfectly green while the hand sits detached at the far
#               margin of an invisible hit box (the Main rail's left-of-label
#               placement): the ledger locks the hand "12-20 px left of the
#               active label/ledge, never detached at the far margin", and
#               Gate A requires "hand never obscures target label".
#
# ACTIONABLE SURFACE
#   A control's actionable surface is what the player actually aims at:
#     * the control's own rect when the control itself draws content
#       (BaseButton with text/icon, or an authored drawable);
#     * otherwise the union of the visible drawables of its COMPONENT (its
#       siblings inside the component root, e.g. MenuRow = HitArea + Label +
#       ActivePlate + ActiveRail + QuietRail);
#     * a full-bleed bare hit plate (a BaseButton with no text/icon covering
#       >=95% of the component root) is HIT PLUMBING, never a surface — this is
#       exactly the rect that fools a naive "is the hotspot inside the control
#       rect" check.
#   The anchor itself is excluded (it is not a surface), and every candidate
#   surface is clipped to the component root so an over-long rail cannot make a
#   control's surface reach across the screen.
#
# Everything here is read-only with respect to production code.

const SCREEN_DIR := "res://.verification/acceptance/"

# --- reach (Doc 08 §5, Doc 03 §5) -------------------------------------------
# The hand settles exactly on an authored anchor; 0.5 px is the spring's own
# convergence floor, so 1-2 frames of settling can never produce a false failure.
const REACH_TOLERANCE_PX := 0.5

# --- optical placement -------------------------------------------------------
# The ledger's own authored band: the hand sits 12-20 px off the active
# label/ledge and is never detached at the far margin. 20 px is therefore the
# outer edge of "on the surface"; beyond it the placement is DETACHED.
const ON_SURFACE_BAND_PX := 20.0
# A hotspot further than this from any authored surface is "at the far margin".
const DETACHED_MARGIN_PX := 40.0
# Minimum label area the drawn hand body may cover before it counts as
# obscuring the target label (Gate A: "hand never obscures target label").
const LABEL_OBSCURE_AREA_PX2 := 4.0

const VERDICT_INSIDE := "INSIDE"
const VERDICT_ON_SURFACE := "ON_SURFACE"
const VERDICT_DETACHED := "DETACHED"

const AnchorScript = preload("res://scripts/frontend/cursor_anchor.gd")
const FocusGraph = preload("res://scripts/frontend/focus_graph.gd")

# ===========================================================================
# input events (real device events, never handler calls)
# ===========================================================================

static func key_event(code: Key, pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

static func mouse_button_event(position: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	return event

static func pad_button_event(index: int, pressed: bool, device := 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	event.device = device
	return event

static func pad_axis_event(axis: int, value: float, device := 0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = device
	return event

static func inject(event: InputEvent) -> void:
	# The engine's real input path: the viewport dispatch and every _input /
	# _unhandled_input / GUI callback see this exactly like a device event.
	Input.parse_input_event(event)

# ===========================================================================
# the tree (settle helpers; a SceneTree subclass cannot await from here)
# ===========================================================================

static func frames(tree: SceneTree, count: int) -> void:
	for i in count:
		await tree.process_frame

static func wait_until(tree: SceneTree, condition: Callable, limit := 240) -> bool:
	for i in limit:
		await tree.process_frame
		if bool(condition.call()):
			return true
	return false

static func wait_for_scene(tree: SceneTree, scene_name: String, limit := 300) -> Node:
	for i in limit:
		await tree.process_frame
		var scene := tree.current_scene
		if scene != null and str(scene.scene_file_path).find(scene_name) != -1:
			return scene
	return null

static func wait_for_node(tree: SceneTree, node_name: String, limit := 300) -> Node:
	for i in limit:
		await tree.process_frame
		var node := tree.root.get_node_or_null(node_name)
		if node != null:
			return node
	return null

static func hand(tree: SceneTree) -> Control:
	var cursor := tree.root.get_node_or_null("Cursor")
	if cursor == null:
		return null
	return cursor.hand

static func service(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("FrontendInput")

static func focus_owner(tree: SceneTree) -> Control:
	var svc := service(tree)
	if svc == null:
		return null
	return svc.focus_owner()

# ===========================================================================
# pointer / semantic activation through the public path
# ===========================================================================

static func click(tree: SceneTree, position: Vector2) -> void:
	# A real pointer press/release at viewport-local (design-space) coordinates:
	# the Control's own GUI hit test and press path own the result. The headless
	# window carries its own screen transform, so screen-space coordinates would
	# miss every authored rect (shipped convention: in_local_coords = true).
	tree.root.push_input(mouse_button_event(position, true), true)
	tree.root.push_input(mouse_button_event(position, false), true)

static func click_center(tree: SceneTree, control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	click(tree, control.get_global_rect().get_center())

static func tap_key(tree: SceneTree, code: Key, hold_frames := 3) -> void:
	inject(key_event(code, true))
	await frames(tree, hold_frames)
	inject(key_event(code, false))
	await frames(tree, 2)

static func tap_pad(tree: SceneTree, index: int, hold_frames := 3) -> void:
	inject(pad_button_event(index, true))
	await frames(tree, hold_frames)
	inject(pad_button_event(index, false))
	await frames(tree, 2)

static func hover(tree: SceneTree, position: Vector2, relative := Vector2(12.0, 0.0)) -> void:
	# Genuine pointer motion (not a teleport with zero delta): hover arming is
	# rearmed by real movement only (Doc 03 §3).
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	tree.root.push_input(event, true)

# ===========================================================================
# focus + hand measurement
# ===========================================================================

static func settle_hand(tree: SceneTree, limit := 60) -> void:
	var cursor_hand := hand(tree)
	for i in limit:
		await tree.process_frame
		if cursor_hand != null and is_instance_valid(cursor_hand) and cursor_hand.mode == 1 \
				and cursor_hand._focus_anchor != null:
			var target: Vector2 = cursor_hand._focus_anchor.get_global_rect().position
			if cursor_hand.hotspot.distance_to(target) <= REACH_TOLERANCE_PX:
				return

static func claim_focus_mode(tree: SceneTree) -> void:
	# §2: FOCUS is claimed by MEANINGFUL frontend input. A real ui_down key
	# event through the tree is that input; it never warps the pointer.
	await tap_key(tree, KEY_DOWN)

# ===========================================================================
# component / surface geometry (the optical dimension)
# ===========================================================================

static func is_visible(node: Node) -> bool:
	return node is Control and (node as Control).is_visible_in_tree()

static func is_anchor(node: Node) -> bool:
	return node is Control and (node as Control).get_script() == AnchorScript

static func draws_content(control: Control) -> bool:
	# Does this control paint something the player reads? Labels, panels,
	# colour fills, textures and content-bearing buttons do; a bare flat plate
	# does not.
	if control is Label or control is ColorRect or control is TextureRect or control is TextureButton:
		return true
	if control is Panel:
		return control.size.x > 0.0 and control.size.y > 0.0
	if control is BaseButton:
		var button := control as BaseButton
		if str(button.text) != "" or button.icon != null:
			return true
		return false
	return false

static func rect_area(rect: Rect2) -> float:
	return maxf(rect.size.x, 0.0) * maxf(rect.size.y, 0.0)

static func union_rect(rects: Array) -> Rect2:
	if rects.is_empty():
		return Rect2()
	var first: Rect2 = rects[0]
	var min_x := first.position.x
	var min_y := first.position.y
	var max_x := first.end.x
	var max_y := first.end.y
	for i in range(1, rects.size()):
		var r: Rect2 = rects[i]
		min_x = minf(min_x, r.position.x)
		min_y = minf(min_y, r.position.y)
		max_x = maxf(max_x, r.end.x)
		max_y = maxf(max_y, r.end.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

static func intersect_area(a: Rect2, b: Rect2) -> float:
	return rect_area(a.intersection(b))

static func point_rect_distance(point: Vector2, rect: Rect2) -> float:
	if rect.has_point(point):
		return 0.0
	var dx := maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0)
	var dy := maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)

static func hit_plumbing(control: Control) -> bool:
	# A bare full-bleed hit plate: a Button with no text/icon covering (nearly)
	# the whole focusable control. It is input plumbing, not a surface.
	if not (control is BaseButton):
		return false
	var button := control as BaseButton
	if str(button.text) != "" or button.icon != null:
		return false
	for child in control.get_children():
		if is_visible(child) and draws_content(child as Control):
			return false
	return control.size.x >= 40.0 and control.size.y >= 24.0

static func component_root(control: Control) -> Control:
	# The authored component a bare hit plate belongs to (MenuRow: HitArea +
	# Label + Plate + Rails). A control that draws its own content is its own
	# component root.
	if hit_plumbing(control):
		var parent := control.get_parent()
		if parent is Control:
			return parent as Control
	return control

static func painted_surface(control: Control) -> Rect2:
	# A control that paints its own surface in its own _draw() names the rect it
	# paints (the CSS READY band's plate + rail). The node-type test in
	# draws_content() cannot see a script-drawn surface, and inferring "any
	# Control with a script" would promote every invisible hit plate to a
	# surface — exactly what the actionable-surface definition excludes. So the
	# control declares it, and nothing else depends on the declaration.
	if control == null or not is_instance_valid(control) or not control.has_method("painted_surface_rect"):
		return Rect2()
	var value: Variant = control.call("painted_surface_rect")
	if value is Rect2:
		return value as Rect2
	return Rect2()

static func surface_rects(control: Control) -> Array:
	var root := component_root(control)
	var root_rect := root.get_global_rect()
	var out: Array = []
	# The component root's own PAINTED surface, when it declares one: still the
	# control's own drawn rect (never a bare full-bleed hit plate).
	var painted := painted_surface(root)
	if rect_area(painted) > 0.0:
		out.append(painted.intersection(root_rect))
	elif root != control or not hit_plumbing(control):
		# The component root itself, when it is the thing the player reads/aims at.
		if draws_content(root) and not hit_plumbing(root):
			out.append(root_rect)
	# Its visible authored surfaces (siblings of a hit plate, children of a
	# component), clipped to the component root.
	for child in root.get_children():
		if child == control:
			continue
		if not is_visible(child) or is_anchor(child):
			continue
		var node := child as Control
		if not draws_content(node) or hit_plumbing(node):
			continue
		var clipped := node.get_global_rect().intersection(root_rect)
		if rect_area(clipped) > 0.0:
			out.append(clipped)
	# A focusable control with no authored surface at all still has its own
	# rect as the only honest answer (never silently pass it).
	if out.is_empty():
		out.append(control.get_global_rect())
	return out

static func label_rects(control: Control) -> Array:
	# The text surfaces the hand must never obscure (Gate A).
	var root := component_root(control)
	var out: Array = []
	_collect_labels(root, control, out)
	if out.is_empty() and root is Label:
		out.append(root.get_global_rect())
	return out

static func _collect_labels(node: Node, skip: Control, out: Array) -> void:
	if node is Label and node != skip and is_visible(node):
		out.append((node as Label).get_global_rect())
	for child in node.get_children():
		if child == skip:
			continue
		_collect_labels(child, skip, out)

static func hand_body_rect(cursor_hand: Control, pose := "authored") -> Rect2:
	# The drawn hand: texture size * HAND_SCALE positioned so that the hotspot IS
	# the pose's tip. Read from the live service, never guessed.
	#
	#   "authored"  the POINT pose (hand.TIP_POINT) — the pose a focused control
	#               is authored against, and the pose Gate A's "hand never
	#               obscures target label" is written for.
	#   "observed"  whatever pose the service is actually drawing right now
	#               (CARRY while a candidate token follows the hand). Recorded
	#               separately: a pose-dependent overlap is a different finding.
	if cursor_hand == null or not is_instance_valid(cursor_hand):
		return Rect2()
	var scale: float = float(cursor_hand.HAND_SCALE)
	var tip: Vector2 = cursor_hand.TIP_POINT if pose == "authored" else cursor_hand.active_tip()
	var texture: Texture2D = cursor_hand.active_texture()
	var size := Vector2(147.0, 160.0)   # the shipped pose canvases
	if texture != null:
		size = Vector2(texture.get_width(), texture.get_height())
	return Rect2(cursor_hand.hotspot - tip * scale, size * scale)

static func measure_placement(cursor_hand: Control, control: Control) -> Dictionary:
	var hotspot: Vector2 = cursor_hand.hotspot if cursor_hand != null else Vector2.ZERO
	var control_rect := control.get_global_rect()
	var surfaces := surface_rects(control)
	var surface := union_rect(surfaces)
	var hand_rect := hand_body_rect(cursor_hand, "authored")
	var observed_rect := hand_body_rect(cursor_hand, "observed")
	var distance := point_rect_distance(hotspot, surface)
	var verdict := VERDICT_DETACHED
	if distance <= 0.0 and surfaces.size() > 0 and _in_any(hotspot, surfaces):
		verdict = VERDICT_INSIDE
	elif distance <= ON_SURFACE_BAND_PX:
		verdict = VERDICT_ON_SURFACE
	var label_rects := label_rects(control)
	var label_overlap := 0.0
	var label_overlap_observed := 0.0
	for label in label_rects:
		label_overlap += intersect_area(hand_rect, label)
		label_overlap_observed += intersect_area(observed_rect, label)
	return {
		"component_root": str(component_root(control).get_path()),
		"control_rect": _rect_array(control_rect),
		"hotspot": [snappedf(hotspot.x, 0.001), snappedf(hotspot.y, 0.001)],
		"hand_body_rect": _rect_array(hand_rect),
		"action_surface_rect": _rect_array(surface),
		"action_surface_count": surfaces.size(),
		"hotspot_in_control_rect": control_rect.has_point(hotspot),
		"hotspot_in_action_surface": _in_any(hotspot, surfaces),
		"distance_to_action_surface_px": snappedf(distance, 0.001),
		"on_surface_band_px": ON_SURFACE_BAND_PX,
		"placement": verdict,
		"placement_pass": verdict != VERDICT_DETACHED,
		"hand_coverage_of_surface_pct": snappedf(
			100.0 * intersect_area(hand_rect, surface) / maxf(rect_area(surface), 0.0001), 0.01),
		"hand_coverage_of_control_pct": snappedf(
			100.0 * intersect_area(hand_rect, control_rect) / maxf(rect_area(control_rect), 0.0001), 0.01),
		"label_obscured_px2": snappedf(label_overlap, 0.01),
		"label_obscured": label_overlap > LABEL_OBSCURE_AREA_PX2,
		"hand_body_observed_rect": _rect_array(observed_rect),
		"label_obscured_observed_px2": snappedf(label_overlap_observed, 0.01),
		"label_obscured_pose_dependent": label_overlap_observed > LABEL_OBSCURE_AREA_PX2 \
				and label_overlap <= LABEL_OBSCURE_AREA_PX2,
	}

static func _in_any(point: Vector2, rects: Array) -> bool:
	for r in rects:
		if (r as Rect2).has_point(point):
			return true
	return false

static func _rect_array(rect: Rect2) -> Array:
	return [snappedf(rect.position.x, 0.001), snappedf(rect.position.y, 0.001),
			snappedf(rect.size.x, 0.001), snappedf(rect.size.y, 0.001)]

# ===========================================================================
# reports
# ===========================================================================

static func write_json(relative_path: String, value: Dictionary) -> String:
	var absolute := ProjectSettings.globalize_path(relative_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(relative_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	return absolute

static func write_csv(relative_path: String, header: Array, rows: Array) -> String:
	var absolute := ProjectSettings.globalize_path(relative_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(relative_path, FileAccess.WRITE)
	if file == null:
		return ""
	var lines: Array = []
	lines.append(_csv_line(header))
	for row in rows:
		lines.append(_csv_line(row))
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return absolute

static func _csv_line(values: Array) -> String:
	var out: Array = []
	for value in values:
		var text := str(value).replace("\"", "\"\"")
		out.append("\"" + text + "\"")
	return ",".join(out)

static func screen_snapshot(screen: Control) -> Dictionary:
	# The observable state a settled destination must show (Doc 08 §3): which
	# screen is presented, its root alpha, and the focus owner.
	if screen == null or not is_instance_valid(screen):
		return {"presented": false}
	return {
		"presented": screen.is_visible_in_tree(),
		"root_alpha": snappedf(screen.modulate.a, 0.0001),
		"focus_owner": str(screen.get_viewport().gui_get_focus_owner().get_path()) \
				if screen.is_inside_tree() and screen.get_viewport().gui_get_focus_owner() != null else "",
	}
