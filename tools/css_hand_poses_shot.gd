extends Control
# CSS hand-pose evidence shot (dev tool, LANE C / owner review).
#
# Renders the Character Select with the DRAWN HAND in each pose the pose rule
# can produce, so the owner can judge them by eye, and prints the optical
# geometry the acceptance harness measures for the same tiles through the SAME
# definitions (tools/acceptance_support.gd) the focus manifest uses — so a PNG
# and its numbers come from ONE run, never from inference.
#
# Usage (real window, rendering required, fixed 60 Hz for determinism):
#   godot --path <repo> --resolution 1280x720 --fixed-fps 60 \
#     res://tools/css_hand_poses_shot.tscn -- --out=<dir>
#
# Images:
#   css_entry_pinch.png            fresh entry (pad): the empty pinch on the
#                                  first tile's anchor, no input delivered
#   css_chip_tile_pinch.png        a committed chip: the pinch on ITS OWN tile
#   css_other_tile_pointer.png     a committed chip: the ordinary pointer on any
#                                  other tile
#   css_mouse_hover_chip_tile.png  the committed chip, hovered by REAL pointer
#                                  motion through the engine's dispatch
#   css_mouse_carry_over_tile.png  a fresh roster, the pointer hovering a tile:
#                                  the approved carry grip
#
# The windowed run's OWN pointer events can re-claim MOUSE modality, so every
# image re-asserts the state it photographs immediately before the snap (a dev
# tool facility — the production paths themselves are driven for real in
# tests/test_char_select.gd).
#
# args (after the bare --):
#   --out=<dir>   output directory for the PNGs (required)

const Support = preload("res://tools/acceptance_support.gd")
const Roster = preload("res://scripts/roster.gd")
const SelectionState = preload("res://scripts/match_selection_state.gd")

var out_dir := ""

func _ready() -> void:
	call_deferred("run")

func arg_value(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return fallback

func hand() -> Control:
	var c = get_node_or_null("/root/Cursor")
	return c.hand if c != null else null

func settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func pose_name(visual: int) -> String:
	var names := ["REGULAR (ordinary pointer)", "CARRY (approved grip)", "HOVER (empty pinch)"]
	return names[clampi(visual, 0, 2)]

func claim_focus() -> void:
	# FOCUS is claimed the way the runtime claims it: a real meaningful frontend
	# event through the engine's own input path (with no screen mounted yet the
	# event claims the modality and nothing else).
	Input.parse_input_event(Support.key_event(KEY_ENTER, true))
	await settle(2)
	Input.parse_input_event(Support.key_event(KEY_ENTER, false))
	await settle(8)

func fresh_state():
	# The runtime's fresh VS defaults (Doc 01 §2): P1 Human / no fighter,
	# P2 CPU / no fighter, P3/P4 EMPTY — no fighter preselected anywhere.
	var state = SelectionState.new()
	for i in 4:
		state.slots[i]["character"] = ""
		state.slots[i]["kind"] = "human" if i == 0 else ("bot" if i == 1 else "empty")
	return state

func chip_state():
	# The owner's reviewed configuration: chips COMMITTED on two tiles.
	var state = fresh_state()
	state.slots[0]["character"] = "ggb"        # P1's chip lands on tile 2
	state.slots[1]["character"] = "doge_man"   # P2's chip lands on tile 1
	return state

func make_css(state, cards: Array) -> Control:
	var css = (load("res://scenes/character_select.tscn") as PackedScene).instantiate()
	css.name = "PoseCSS"
	add_child(css)
	await settle(6)
	css.build(cards)
	css.open_with(state)
	return css

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out_dir + "/" + name + ".png")
	if err != OK:
		push_error("css_hand_poses_shot: save failed for " + name + " (" + str(err) + ")")
	print("css_hand_poses_shot: %s.png -> %s" % [name, out_dir])

func report(tag: String, css: Control, tile_index: int) -> void:
	var cursor_hand := hand()
	var tile: Control = css.get_tiles()[tile_index]
	var label: Label = tile.get_node("NameBand/FighterName")
	var optical := Support.measure_placement(cursor_hand, tile)
	var anchor: Control = tile.anchor()
	print("--- %s ---" % tag)
	print("hand        pose=%s texture=%s hotspot=%s" % [
		pose_name(int(cursor_hand.visual)),
		str(cursor_hand.active_texture().resource_path), str(cursor_hand.hotspot)])
	print("tile        %s rect=%s" % [str(tile.fighter_id), str(tile.get_global_rect())])
	print("anchor      %s rel=(%.3f, %.3f) of the tile" % [
		str(anchor.get_global_rect().position), anchor.position.x / tile.size.x, anchor.position.y / tile.size.y])
	print("label       %s text=%s (the shaped name: the measurable label rect)" % [
		str(label.get_global_rect()), str(label.text)])
	print("hand_body   %s (drawn pose %s)" % [
		str(Support.hand_body_rect(cursor_hand, "observed")), pose_name(int(cursor_hand.visual))])
	print("optical     placement=%s distance=%.2fpx coverage=%.2f%% label_obscured=%.2fpx2" % [
		str(optical["placement"]), optical["distance_to_action_surface_px"],
		optical["hand_coverage_of_surface_pct"], optical["label_obscured_px2"]])
	# The harness's own split (the manifest reports both): label_obscured is the
	# AUTHORED point pose's question; a pose-dependent overlap of the carried
	# grip's wider reach is recorded separately, never folded into it.
	print("pose_split  authored_pose overlap=%.2fpx2 | observed_pose overlap=%.2fpx2 (pose-dependent: %s)" % [
		optical["label_obscured_px2"], optical["label_obscured_observed_px2"],
		str(optical["label_obscured_pose_dependent"])])

func hold_focus(css: Control, index: int) -> void:
	# Re-assert the FOCUS owner + authored target this image photographs (the
	# windowed run's own pointer events can otherwise re-claim MOUSE modality).
	var tile: Control = css.get_tiles()[index]
	if Support.focus_owner(get_tree()) != tile:
		tile.grab_focus()
	hand().claim_focus()
	hand().set_focus_target(tile.anchor())
	await settle(50)

func hold_pointer(tile: Control, at: Vector2) -> void:
	# Re-assert the real pointer hover on the tile's authored point.
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.relative = Vector2(30.0, 0.0)
	hand()._input(motion)
	await settle(4)
	hand()._input(motion)
	await settle(4)
	tile.mouse_entered.emit()
	await settle(24)

func entry_shot(cards: Array, attempts := 5) -> Control:
	# The runtime's entry: FOCUS claimed, then the screen opens and seeds the
	# first tile. Retried if the window's own pointer events intrude before the
	# snap (each attempt is a genuine open_with through the public entry).
	for attempt in attempts:
		await claim_focus()
		var fresh = await make_css(fresh_state(), cards)
		await settle(80)
		var tiles: Array = fresh.get_tiles()
		var ok: bool = int(hand().mode) == 1 \
			and hand()._focus_anchor == tiles[0].anchor() \
			and not hand().is_carrying() \
			and int(hand().visual) == 2
		if ok:
			await snap("css_entry_pinch")
			report("ENTRY, fresh roster, pad focus seeded on the first tile", fresh, 0)
			fresh.queue_free()
			await settle(6)
			return null
		print("css_hand_poses_shot: entry attempt %d did not hold the entry state (mode %d, visual %d, anchor %s)"
			% [attempt + 1, int(hand().mode), int(hand().visual),
			str(hand()._focus_anchor.get_path()) if hand()._focus_anchor != null else "-"])
		fresh.queue_free()
		await settle(6)
	push_error("css_hand_poses_shot: the entry pose could not be held for the shoot")
	return null

func run() -> void:
	out_dir = arg_value("out", "")
	if out_dir == "":
		push_error("css_hand_poses_shot: --out=<dir> is required")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cards: Array = []
	for id in Roster.ids():
		cards.append({"id": str(id), "name": Roster.display_name(str(id)).to_upper()})

	# --- 1. the fresh entry (pad): the pose in the first settled frame -------
	await entry_shot(cards)

	# --- 2/3. a committed chip: its own tile vs another tile ----------------
	await claim_focus()
	var chips = await make_css(chip_state(), cards)
	await settle(70)
	await hold_focus(chips, 2)
	await snap("css_chip_tile_pinch")
	report("COMMITTED chip, focus on ITS OWN tile (ggb)", chips, 2)
	await hold_focus(chips, 5)
	await snap("css_other_tile_pointer")
	report("COMMITTED chip, focus on another fighter", chips, 5)
	if is_instance_valid(chips):
		chips.queue_free()
	await settle(6)

	# --- 4. the committed chip's own tile, hovered by a real pointer --------
	# In the MOUSE path the hand is drawn AT THE POINTER (the authored anchor is
	# the FOCUS pose), so the shoot parks the pointer on the tile's authored
	# anchor point: the pose is judged without parking the hand on a name.
	await claim_focus()
	var hovered = await make_css(chip_state(), cards)
	await settle(70)
	var tile2: Control = hovered.get_tiles()[2]
	await hold_pointer(tile2, tile2.anchor().get_global_rect().position)
	await snap("css_mouse_hover_chip_tile")
	report("COMMITTED chip, REAL pointer hover on its own tile (hand at the pointer)", hovered, 2)

	# --- 5. the carry hand, over a tile the hand may pick a chip up from ----
	# A fresh roster: the pointer hovers a tile, the carry starts, and the grip
	# that holds the chip is drawn over ANY tile (finding 3's carry clause).
	if is_instance_valid(hovered):
		hovered.queue_free()
	await settle(6)
	var carry = await make_css(fresh_state(), cards)
	await settle(70)
	var tile1: Control = carry.get_tiles()[1]
	await hold_pointer(tile1, tile1.anchor().get_global_rect().position)
	await snap("css_mouse_carry_over_tile")
	report("FRESH roster, REAL pointer hover on a hold (the approved carry grip)", carry, 1)

	print("css_hand_poses_shot: done")
	get_tree().quit(0)
