extends Object
# FocusGraph — authored focus topology, focus recovery and anchor resolution
# (Doc 03 §6 "every focusable control has an authored CursorAnchor" and §13
# "no important surface depends on automatic tree-order focus").
#
# WHY THIS EXISTS
#   §13 forbids relying on the engine's automatic (tree-order / geometric)
#   focus search. Every screen therefore AUTHORS its topology: it says, per
#   control and per direction, which control is the neighbour. This file is the
#   ONE place that writes those neighbours and the ONE place that resolves a
#   control's authored CursorAnchor, so no screen repeats the mapping rules.
#
# RECOVERY (§6, rear half)
#   "If a control disappears/gets disabled while focused, immediately move focus
#   to the correct surviving semantic neighbour and retarget the hand."
#   recover() implements exactly that: when the current focus owner is no longer
#   focusable (hidden, FOCUS_NONE, or a disabled Button) it walks the owner's OWN
#   authored neighbours in a deterministic priority order and moves focus to the
#   first survivor; only when the whole neighbourhood is gone does it fall back
#   to the screen's declared default control. Never leaves focus on a hidden
#   control, never invents a geometric guess.

const AnchorScript = preload("res://scripts/frontend/cursor_anchor.gd")

# The last control each screen retargeted to (screen instance id -> WeakRef).
# The engine RELEASES focus when a focused Control becomes hidden, so a screen
# cannot detect the disappearance from gui_get_focus_owner() alone: the screen's
# own last authored focus slot is the reference the recovery starts from.
static var _slots: Dictionary = {}

# Deterministic semantic priority for recovery. "The correct surviving
# neighbour" is not a geometric question, so the order is authored here once:
# below the control first (the natural continuation of a column), then above,
# then the row, then the Tab order.
const RECOVERY_PRIORITY: Array = [&"bottom", &"top", &"right", &"left", &"next", &"previous"]

# --- anchor resolution -------------------------------------------------------

static func anchor_of(control: Control) -> Control:
	# The authored CursorAnchor of a control: the direct child named
	# "CursorAnchor" (the component convention: FighterTile / PlayerBay /
	# ReadyBand / MenuRow / ActionBar / BackAction / state controls), else the
	# first descendant carrying the CursorAnchor script (screens that author
	# their anchors as siblings, e.g. Story Briefing's AnchorAction).
	if control == null or not is_instance_valid(control):
		return null
	var direct := control.get_node_or_null("CursorAnchor")
	if direct is Control:
		return direct as Control
	for child in control.get_children():
		if child is Control and child.get_script() == AnchorScript:
			return child as Control
	return null

static func anchor_path(control: Control) -> String:
	var anchor := anchor_of(control)
	return str(anchor.get_path()) if anchor != null else ""

# --- focusability ------------------------------------------------------------

static func focusable(control: Control) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	if not control.is_inside_tree() or not control.is_visible_in_tree():
		return false
	if control.focus_mode == Control.FOCUS_NONE:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	return true

# --- authoring ---------------------------------------------------------------

static func wire(control: Control, neighbour: Control, directions: Array) -> void:
	# Writes the explicit neighbour paths for the given directions.
	if control == null or neighbour == null:
		return
	for direction in directions:
		match str(direction):
			"top":
				control.focus_neighbor_top = control.get_path_to(neighbour)
			"bottom":
				control.focus_neighbor_bottom = control.get_path_to(neighbour)
			"left":
				control.focus_neighbor_left = control.get_path_to(neighbour)
			"right":
				control.focus_neighbor_right = control.get_path_to(neighbour)
			"next":
				control.focus_next = control.get_path_to(neighbour)
			"previous":
				control.focus_previous = control.get_path_to(neighbour)

static func clear(control: Control, directions: Array) -> void:
	if control == null:
		return
	for direction in directions:
		match str(direction):
			"top":
				control.focus_neighbor_top = NodePath()
			"bottom":
				control.focus_neighbor_bottom = NodePath()
			"left":
				control.focus_neighbor_left = NodePath()
			"right":
				control.focus_neighbor_right = NodePath()
			"next":
				control.focus_next = NodePath()
			"previous":
				control.focus_previous = NodePath()

static func chain(controls: Array, wrap := false) -> void:
	# Tab order along an explicit list. No wrap: the first control has no
	# previous and the last has no next (Doc 03 §13 Results: "no wrap").
	var n := controls.size()
	for i in n:
		var control: Control = controls[i]
		if control == null:
			continue
		if i + 1 < n:
			wire(control, controls[i + 1], [&"next"])
		elif wrap and n > 0:
			wire(control, controls[0], [&"next"])
		else:
			clear(control, [&"next"])
		if i > 0:
			wire(control, controls[i - 1], [&"previous"])
		elif wrap and n > 0:
			wire(control, controls[n - 1], [&"previous"])
		else:
			clear(control, [&"previous"])

# --- neighbour lookup --------------------------------------------------------

static func neighbour(control: Control, direction: StringName) -> Control:
	if control == null or not is_instance_valid(control):
		return null
	var path := NodePath()
	match str(direction):
		"top":
			path = control.focus_neighbor_top
		"bottom":
			path = control.focus_neighbor_bottom
		"left":
			path = control.focus_neighbor_left
		"right":
			path = control.focus_neighbor_right
		"next":
			path = control.focus_next
		"previous":
			path = control.focus_previous
		_:
			return null
	if path.is_empty():
		return null
	var node := control.get_node_or_null(path)
	return node as Control

static func surviving_neighbour(control: Control, priority: Array = RECOVERY_PRIORITY) -> Control:
	for direction in priority:
		var candidate := neighbour(control, direction)
		if focusable(candidate):
			return candidate
	return null

# --- recovery ----------------------------------------------------------------

static func track(screen: Node, control: Control) -> void:
	# §6: every focus-enter on a screen records the authored focus slot, so the
	# recovery can still find the correct surviving neighbour after the engine
	# released the focus (a hidden control loses the engine focus silently).
	if screen == null or control == null:
		return
	_slots[screen.get_instance_id()] = weakref(control)

static func last_slot(screen: Node) -> Control:
	if screen == null:
		return null
	var ref = _slots.get(screen.get_instance_id(), null)
	if ref == null:
		return null
	var control = ref.get_ref()
	return control as Control if control is Control else null

static func recover(viewport: Viewport, screen: CanvasItem, fallback: Callable = Callable()) -> Control:
	# Returns the surviving focus owner. If the current owner is still valid the
	# owner is untouched (a recover() must never steal focus from a good
	# control). With NO owner at all the screen's own last focus slot is
	# inspected: the engine releases focus when a focused control is hidden, and
	# §6 still requires the focus (and the hand) to move to the correct
	# surviving neighbour. A screen that never held focus is left alone.
	if viewport == null:
		return null
	var owner := viewport.gui_get_focus_owner()
	var stale: Control = null
	if owner != null and is_instance_valid(owner):
		if screen != null and not screen.is_ancestor_of(owner):
			return null     # not this screen's focus — never touch another surface
		if focusable(owner):
			return owner
		stale = owner
	else:
		var slot := last_slot(screen)
		if slot != null and not focusable(slot):
			stale = slot
		else:
			return null
	var next := surviving_neighbour(stale)
	if next == null and fallback.is_valid():
		var candidate = fallback.call()
		if focusable(candidate):
			next = candidate
	if next == null:
		# No survivor at all: the stale control must not keep the focus either
		# (§6 "never leave focus/hand on a hidden control"). Releasing is the
		# honest outcome; the screen seeds its own default on its next entry.
		if is_instance_valid(stale) and not focusable(stale):
			stale.release_focus()
		return null
	next.grab_focus()
	return next

static func retarget(hand: Control, anchor: Control) -> void:
	# §6: the hand target is part of the atomic focus-enter, and only FOCUS mode
	# owns it (a mouse user's hand follows the physical pointer instead).
	if hand == null or anchor == null or not is_instance_valid(anchor):
		return
	if hand.mode == 1:
		hand.set_focus_target(anchor)
