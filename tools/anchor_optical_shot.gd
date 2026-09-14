extends Control
# anchor_optical_shot (dev evidence tool, LANE C / anchor optics).
#
# Renders ONE Main Menu rail row (or one Quit-modal action) at an exact
# resolution with the focus hand settled, saves the PNG for a by-eye approval,
# and prints the OPTICAL geometry the harness measures (actionable surfaces,
# label rects, the anchor, the drawn hand body, coverage, obscured px) read
# from the live tree through tools/acceptance_support.gd — the same definitions
# the acceptance manifest uses, so a screenshot and its numbers come from the
# SAME run.
#
# Usage (real window, rendering required):
#   godot --path <repo> --resolution 1280x720 --quit-after 900 \
#     res://tools/anchor_optical_shot.tscn -- --row=0 --out=C:/evidence/main_play.png
# args (after the bare --):
#   --row=<0-3>     which Main rail row to focus (default 0)
#   --modal         focus the Quit modal's STAY action instead of a rail row
#   --out=<path>    PNG path (required)

const Support = preload("res://tools/acceptance_support.gd")
const Roster = preload("res://scripts/roster.gd")
const SelectionState = preload("res://scripts/match_selection_state.gd")

func arg_value(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return fallback

func has_flag(key: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--" + key:
			return true
	return false

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var out := arg_value("out", "")
	if out == "":
		push_error("anchor_optical_shot: --out=<path> is required")
		get_tree().quit(1)
		return
	var row_index := int(arg_value("row", "0"))
	var modal := has_flag("modal")
	var css_band := has_flag("cssband")
	var hand: Control = Support.hand(get_tree())
	if css_band:
		await run_css_band(out)
		return
	var home = (load("res://scenes/home.tscn") as PackedScene).instantiate()
	add_child(home)
	for i in 12:
		await get_tree().process_frame

	if hand == null:
		push_error("anchor_optical_shot: no cursor hand in the tree")
		get_tree().quit(1)
		return
	# FOCUS mode is claimed by MEANINGFUL input (a real ui_down through the
	# engine's input path), never by a direct mode assignment.
	await Support.claim_focus_mode(get_tree())

	var control: Control = null
	if modal:
		var quit_row: Control = home.menu_rows()[3].get_node("HitArea")
		Support.click_center(get_tree(), quit_row)
		for i in 12:
			await get_tree().process_frame
		# A pointer click hands the cursor back to MOUSE; FOCUS is re-claimed by
		# meaningful input, exactly like a player resuming the pad/stick.
		await Support.claim_focus_mode(get_tree())
		control = home.get_node("ReferenceFrame/QuitOverlay/Plate/ActionStay")
	else:
		control = home.menu_rows()[row_index].get_node("HitArea")
	control.grab_focus()
	for i in 4:
		await get_tree().process_frame
	await Support.settle_hand(get_tree())
	for i in 30:
		await get_tree().process_frame

	report(home, control, hand, modal, row_index)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out)
	if err != OK:
		push_error("anchor_optical_shot: save failed " + str(err))
		get_tree().quit(1)
		return
	print("anchor_optical_shot: %s -> %s (%dx%d)" % [control.name, out, image.get_width(), image.get_height()])
	get_tree().quit(0)

func rects(entries: Array) -> String:
	var parts: Array = []
	for r in entries:
		parts.append("[%.1f,%.1f %.1fx%.1f]" % [r.position.x, r.position.y, r.size.x, r.size.y])
	return " ".join(parts)

func run_css_band(out: String) -> void:
	# The Ready band's evidence: the band is the click target, its label IS the
	# band, so the harness's "obscured" number covers drawn-hand area only. This
	# mode measures the WORDMARK's own glyph box next to the hand, so the report
	# can state how far the drawn hand is from the words the player reads.
	var cards: Array = []
	for id in Roster.ids():
		cards.append({"id": str(id), "name": Roster.display_name(str(id)).to_upper()})
	var css = (load("res://scenes/character_select.tscn") as PackedScene).instantiate()
	add_child(css)
	for i in 6:
		await get_tree().process_frame
	css.build(cards)
	var state = SelectionState.new()
	state.slots[0]["kind"] = "human"
	state.slots[0]["character"] = str(cards[0]["id"])
	state.slots[1]["kind"] = "bot"
	state.slots[1]["character"] = str(cards[1]["id"])
	css.open_with(state)
	for i in 40:
		await get_tree().process_frame
	var band: Control = css.get_ready_band()
	band.show_band()
	for i in 20:
		await get_tree().process_frame
	var hand: Control = Support.hand(get_tree())
	hand.set_mode(1)
	var anchor: Control = band.anchor()
	if anchor != null:
		anchor.grab_focus()
	hand.set_focus_target(anchor)
	for i in 60:
		await get_tree().process_frame
	var wordmark: Label = band.get_node("ReadyText")
	var glyphs := Vector2(wordmark.get_theme_font("font").get_string_size(
		str(wordmark.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, wordmark.get_theme_font_size("font_size")).x,
		wordmark.get_global_rect().size.y)
	print("--- anchor optical report (Ready band) ---")
	print("band_shown   %s visible_in_tree=%s" % [str(band.is_shown()), str(band.is_visible_in_tree())])
	print("band_rect    %s" % str(band.get_global_rect()))
	print("label_rect   %s (the ReadyText label = the whole band)" % str(wordmark.get_global_rect()))
	print("wordmark_box [%.1f,%.1f %.1fx%.1f] (the glyphs the player reads, centred in the band)" % [
		wordmark.get_global_rect().position.x + (band.size.x - glyphs.x) * 0.5,
		wordmark.get_global_rect().position.y, glyphs.x, glyphs.y])
	print("surfaces     %s" % rects(Support.surface_rects(band)))
	print("labels       %s" % rects(Support.label_rects(band)))
	print("anchor       %s ratio=%s offset=%s" % [str(anchor.get_global_rect().position),
		str(anchor.anchor_ratio()), str(anchor.optical_offset)])
	var optical := Support.measure_placement(hand, band)
	print("hotspot      %s hand_body %s" % [str(hand.hotspot), str(Support.hand_body_rect(hand, "authored"))])
	print("placement    %s distance=%.2fpx coverage=%.2f%% label_obscured=%.2fpx2 (full hand area %.2f)" % [
		str(optical["placement"]), optical["distance_to_action_surface_px"],
		optical["hand_coverage_of_surface_pct"], optical["label_obscured_px2"],
		Support.hand_body_rect(hand, "authored").size.x * Support.hand_body_rect(hand, "authored").size.y])
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(out)
	print("anchor_optical_shot: ready band -> %s (%dx%d)" % [out, image.get_width(), image.get_height()])
	get_tree().quit(0)

func report(home, control: Control, hand: Control, modal: bool, row_index: int) -> void:
	var anchor: Control = home.focus_anchor_for(control)
	var optical := Support.measure_placement(hand, control)
	print("--- anchor optical report (%s) ---" % ("quit modal STAY" if modal else "Main row %d" % row_index))
	print("control      %s" % str(control.get_path()))
	print("control_rect %s" % str(control.get_global_rect()))
	if not modal:
		var row: Control = home.menu_rows()[row_index]
		print("row_rect     %s" % str(row.get_global_rect()))
		print("label_rect   %s" % str((row.get_node("Label") as Label).get_global_rect()))
		print("plate_rect   %s" % str((row.get_node("ActivePlate") as Panel).get_global_rect()))
		print("rail_rect    %s" % str((row.get_node("ActiveRail") as Panel).get_global_rect()))
	print("surfaces     %s" % rects(Support.surface_rects(control)))
	print("labels       %s" % rects(Support.label_rects(control)))
	print("anchor       %s (%s) ratio=%s offset=%s" % [str(anchor.get_global_rect().position), str(anchor.get_path()),
		str(anchor.anchor_ratio()), str(anchor.optical_offset)])
	print("hotspot      %s hand_body %s texture=%s" % [str(hand.hotspot),
		str(Support.hand_body_rect(hand, "authored")), str(hand.active_texture().resource_path)])
	print("placement    %s distance=%.2fpx coverage=%.2f%% label_obscured=%.2fpx2" % [
		str(optical["placement"]), optical["distance_to_action_surface_px"],
		optical["hand_coverage_of_surface_pct"], optical["label_obscured_px2"]])
	print("focus_owner  %s" % str(Support.focus_owner(get_tree()).get_path() if Support.focus_owner(get_tree()) != null else ""))
