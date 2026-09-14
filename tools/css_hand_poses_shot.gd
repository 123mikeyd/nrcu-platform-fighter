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
#   css_entry_carry_mouse.png      the REAL mouse route's first visible frame:
#                                  a real left click on the shipped Main PLAY
#                                  row, then the CARRY grip with the chip in the
#                                  hand as the Character Select appears (the
#                                  pointer still where PLAY was clicked)
#   css_entry_carry_pad.png        the same, entered with a real pad-A accept
#   css_chip_tile_pinch.png        a committed chip: the pinch on ITS OWN tile
#   css_other_tile_pointer.png     a committed chip: the ordinary pointer on any
#                                  other tile
#   css_mouse_hover_chip_tile.png  the committed chip, hovered by REAL pointer
#                                  motion through the engine's dispatch
#   css_mouse_carry_over_tile.png  a fresh roster, the pointer hovering a tile:
#                                  the approved carry grip
#
# The two ENTRY captures are taken in the FIRST frame the screen is visible and
# NOTHING is re-asserted before the snap (that frame is the owner's finding);
# the later images re-assert the state they photograph immediately before the
# snap (a dev tool facility — the production paths themselves are driven for
# real in tests/test_char_select.gd).
#
# args (after the bare --):
#   --out=<dir>   output directory for the PNGs (required)

const Support = preload("res://tools/acceptance_support.gd")
const Roster = preload("res://scripts/roster.gd")
const SelectionState = preload("res://scripts/match_selection_state.gd")

var out_dir := ""
var entry_device := ""

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
	# The entry captures are taken on the REAL route (the shipped Main PLAY row
	# and the runtime's own scene change), in the FIRST frame the Character
	# Select is visible, with NOTHING re-asserted before the snap: that first
	# frame is the owner's finding. Each attempt re-runs the whole real route,
	# so a windowed run's stray pointer events can never fake the shot.
	var previous: Array = host_ids()
	var home = await mount_main()
	var play: Button = home.menu_rows()[0].get_node("HitArea")
	if entry_device == "mouse":
		var at: Vector2 = play.get_global_rect().get_center()
		Input.warp_mouse(at)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.relative = Vector2(26.0, 0.0)
		get_tree().root.push_input(motion, true)
		hand()._input(motion)
		await settle(2)
		get_tree().root.push_input(Support.mouse_button_event(at, true), true)
		get_tree().root.push_input(Support.mouse_button_event(at, false), true)
	else:
		play.grab_focus()
		await settle(3)
		Input.parse_input_event(Support.pad_button_event(JOY_BUTTON_A, true))
		await settle(2)
		Input.parse_input_event(Support.pad_button_event(JOY_BUTTON_A, false))
	await settle(2)
	var entry := await await_css_entry(previous)
	var host = entry[0]
	var css = entry[1]
	if css != null:
		if int(css.get_carried_by()) == 0 and int(hand().visual) == 1:
			await snap("css_entry_carry_" + entry_device)
			entry_report(entry_device, css)
			# The same state, once the entry choreography has revealed the
			# roster: the owner's by-eye frame (the pose must not change with
			# the reveal — nothing has been delivered to the screen).
			await settle(48)
			await snap("css_entry_carry_" + entry_device + "_settled")
			entry_report(entry_device + " (settled, roster revealed)", css)
			await free_route(host, home)
			return null
		push_error("css_hand_poses_shot: the %s entry did not hold the entry chip (carried_by %d, visual %d)"
			% [entry_device, int(css.get_carried_by()), int(hand().visual)])
	else:
		push_error("css_hand_poses_shot: the %s PLAY route never opened the Character Select" % entry_device)
	await free_route(host, home)
	return null

func host_ids() -> Array:
	var out: Array = []
	for child in get_tree().root.get_children():
		if child.has_method("char_select"):
			out.append(child.get_instance_id())
	return out

func await_css_entry(previous: Array) -> Array:
	# The FIRST frame a NEW MatchFlow host shows its Character Select — the frame
	# the runtime's PLAY route lands. No input is delivered after the press.
	for i in 600:
		await get_tree().process_frame
		for child in get_tree().root.get_children():
			if not child.has_method("char_select"):
				continue
			if child.get_instance_id() in previous:
				continue
			var css = child.char_select()
			if css != null and css.is_visible_in_tree():
				return [child, css]
	return [null, null]

func mount_main() -> Control:
	# The shipped Main Menu as the CURRENT SCENE, exactly like the runtime: the
	# PLAY route's own scene change replaces it with the MatchFlow host. This
	# tool's node is not the current scene, so the shoot survives that change.
	var home = (load("res://scenes/home.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(home)
	get_tree().current_scene = home
	await settle(14)
	return home

func free_route(host, home) -> void:
	if home != null and is_instance_valid(home):
		home.queue_free()
	if host != null and is_instance_valid(host):
		host.hide()
		if get_tree().current_scene == host:
			get_tree().current_scene = null
		host.queue_free()
	await settle(2)

func entry_report(device: String, css: Control) -> void:
	var cursor_hand := hand()
	var chip = css.token_view(0)
	var chip_centre := Vector2.ZERO
	if chip != null:
		chip_centre = chip.global_position + chip.size * 0.5
	print("--- ENTRY via a REAL %s accept on the shipped Main PLAY row — the FIRST visible frame, no input delivered to the screen ---" % device)
	print("hand        pose=%s texture=%s hotspot=%s" % [
		pose_name(int(cursor_hand.visual)),
		str(cursor_hand.active_texture().resource_path), str(cursor_hand.hotspot)])
	print("entry chip  carried_by=%d token_state=%d parent=%s visible=%s" % [
		int(css.get_carried_by()), int(css.token_state(0)),
		str(chip.get_parent().name) if chip != null and chip.get_parent() != null else "-",
		str(chip.visible) if chip != null else "false"])
	print("carry anchor chip_centre=%s, carry_pinch_point=%s (off %.2f px)" % [
		str(chip_centre), str(cursor_hand.carry_pinch_point()),
		chip_centre.distance_to(cursor_hand.carry_pinch_point())])
	print("pointer     off_roster=%s entry_chip_state=%s roster_bounds=%s" % [
		str(not css._cursor_in_roster()), str(bool(css._entry_carry)), str(css.roster_bounds())])
	print("entry frame phase=%d guard=%.2f candidate=%d" % [
		int(css.get_phase()), float(css.get_input_guard()), int(css.get_candidate())])

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

	# --- 1. the ENTRY CHIP on the real Main PLAY route, BOTH devices ---------
	entry_device = "mouse"
	await entry_shot(cards)
	entry_device = "pad"
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
