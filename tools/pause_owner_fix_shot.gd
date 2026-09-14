extends Node
# pause_owner_fix_shot — deterministic 1280x720 captures of the Pause surface
# for the owner round (dev tool; packaging only, no game code).
#
#   godot --path <repo> --resolution 1280x720 --fixed-fps 60 --quit-after 900 \
#     res://tools/pause_owner_fix_shot.tscn -- --out=<dir> --tag=<before|after>
#
# Renders (real window: rendering is required, never --headless):
#   <tag>_pause_vs.png            live VS match, Pause open, selection RESUME
#   <tag>_pause_hover_leave.png   ... with the pointer on LEAVE MATCH (real
#                                 pointer motion: the hand hovers the row)
#   <tag>_pause_story.png         Story pause wording (LEAVE ENCOUNTER)
#   <tag>_reference_main_rows.png the owner-approved Main rows, same frame, for
#                                 a side-by-side grammar check
# and prints the MEASURED row geometry (frame-local, from the live tree).

const Tokens = preload("res://scripts/ui_tokens.gd")

var out_dir := ""
var tag := "shot"

func _ready() -> void:
	call_deferred("run")

func arg_value(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return fallback

func settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(out_dir + "/" + name + ".png")
		print("pause_owner_fix_shot: " + name + ".png")

func rect_of(node: Control, origin: Vector2) -> String:
	var r := node.get_global_rect()
	return "[x %.1f -> %.1f, y %.1f -> %.1f w %.1f h %.1f]" % [
		r.position.x - origin.x, r.end.x - origin.x,
		r.position.y - origin.y, r.end.y - origin.y, r.size.x, r.size.y]

func glyph_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	return font.get_string_size(str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x

func move_pointer(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = Vector2(4.0, 0.0)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame

func report_pause(pause: Control, origin: Vector2) -> void:
	print("--- Pause rows (frame-local from the 1280x720 ReferenceFrame) ---")
	for index in pause.menu_rows().size():
		var row: Control = pause.menu_rows()[index]
		var plate: Panel = pause.item_plate(index)
		var rail: Panel = pause.active_rail(index)
		var quiet: Panel = pause.quiet_rail(index)
		var label: Label = pause.row_label(index)
		print("row %d %-12s %s visible=%s" % [index, str(label.text), rect_of(row, origin), str(row.visible)])
		print("   label     %s size=%d glyphs=%.1f" % [rect_of(label, origin), label.get_theme_font_size("font_size"), glyph_width(label)])
		print("   plate     %s visible=%s | toprule visible=%s" % [rect_of(plate, origin), str(plate.visible), str((plate.get_node("TopRule") as Panel).visible)])
		print("   ledge     %s visible=%s" % [rect_of(rail, origin), str(rail.visible)])
		print("   quietrail %s visible=%s ends_before_plate_right=%.1f" % [
			rect_of(quiet, origin), str(quiet.visible),
			(plate.get_global_rect().end.x - origin.x) - (quiet.get_global_rect().end.x - origin.x)])
	print("active_index=%d" % pause.active_index())

func report_main_rows(home: Control, origin: Vector2) -> void:
	print("--- reference: owner-approved Main rows (frame-local) ---")
	var rows: Array = home.menu_rows()
	for i in rows.size():
		var row: Control = rows[i]
		var plate: Panel = row.get_node("ActivePlate")
		var rail: Panel = row.get_node("ActiveRail")
		var quiet: Panel = row.get_node("QuietRail")
		var label: Label = row.get_node("Label")
		print("row %d %-12s %s selected=%s" % [i, str(label.text), rect_of(row, origin), str(i == home.selected_index())])
		print("   label     %s size=%d glyphs=%.1f" % [rect_of(label, origin), label.get_theme_font_size("font_size"), glyph_width(label)])
		print("   plate     %s visible=%s | toprule visible=%s" % [rect_of(plate, origin), str(plate.visible), str((plate.get_node("TopRule") as Panel).visible)])
		print("   ledge     %s visible=%s" % [rect_of(rail, origin), str(rail.visible)])
		print("   quietrail %s visible=%s ends_before_plate_right=%.1f" % [
			rect_of(quiet, origin), str(quiet.visible),
			(plate.get_global_rect().end.x - origin.x) - (quiet.get_global_rect().end.x - origin.x)])

func story_pause_shot() -> void:
	# The Story wording is a pure surface state (no live Bobo encounter needed):
	# an overlay opened with story=true renders LEAVE ENCOUNTER.
	var pause = load("res://scripts/frontend/pause_overlay.gd").new()
	add_child(pause)
	await settle(8)
	pause.open(true)
	await settle(20)
	var origin := (pause.get_node("ReferenceFrame") as Control).get_global_rect().position
	print("--- Story Pause wording ---")
	print("title=%s resume=%s leave=%s" % [pause.title_text(), pause.resume_label(), pause.leave_label()])
	report_pause(pause, origin)
	await snap(tag + "_pause_story")
	var event := InputEventMouseMotion.new()
	event.position = pause.row_hit(1).get_global_rect().get_center()
	event.global_position = event.position
	event.relative = Vector2(4.0, 0.0)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle(20)
	pause.queue_free()
	await settle(4)

func run() -> void:
	out_dir = arg_value("out", "")
	if out_dir == "":
		push_error("pause_owner_fix_shot: --out=<dir> required")
		get_tree().quit(1)
		return
	tag = arg_value("tag", "shot")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 1) live VS match -> Pause open (direct arena fixture, deterministic).
	var arena := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(arena)
	await settle(6)
	var slots = load("res://scripts/match_config.gd").default_slots()
	slots[2].kind = "empty"
	slots[3].kind = "empty"
	arena.start_match(slots, false)
	await settle(20)
	var pause: Control = arena.pause_overlay()
	pause.open(false)
	await settle(24)
	var origin := (pause.get_node("ReferenceFrame") as Control).get_global_rect().position
	print("--- VS Pause (default selection) ---")
	print("title=%s resume=%s leave=%s state=%s" % [pause.title_text(), pause.resume_label(), pause.leave_label(), pause.state()])
	report_pause(pause, origin)
	await snap(tag + "_pause_vs")

	# 2) the pointer on LEAVE MATCH, through the real pointer path.
	await move_pointer(pause.row_hit(1).get_global_rect().get_center())
	await settle(24)
	var hand = get_tree().root.get_node_or_null("Cursor")
	var hovered := str(hand.hand.hovered.name) if hand != null and hand.hand.hovered != null else "<none>"
	print("--- VS Pause (pointer on LEAVE MATCH) ---")
	print("engine_hovered=%s hand_hovered=%s active_index=%d" % [
		str(get_viewport().gui_get_hovered_control().name) if get_viewport().gui_get_hovered_control() != null else "<none>",
		hovered, pause.active_index()])
	report_pause(pause, origin)
	await snap(tag + "_pause_hover_leave")
	arena.queue_free()
	await settle(6)

	# 3) Story wording.
	await story_pause_shot()

	# 4) the approved Main rows in the same frame, for a side-by-side check.
	var home := (load("res://scenes/home.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(home)
	await settle(30)
	home.select_row(0, true)
	await settle(20)
	report_main_rows(home, (home.get_node("ReferenceFrame") as Control).get_global_rect().position)
	await snap(tag + "_reference_main_rows")
	home.queue_free()
	await settle(6)
	print("pause_owner_fix_shot: done")
	get_tree().quit(0)
