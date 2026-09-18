extends Node
# owner_fix_shot — deterministic before/after captures for the three
# owner-reported visual defects (dev tool; packaging only, no game code).
#
#   godot --path <repo> --resolution 1280x720 --fixed-fps 60 \
#     res://tools/owner_fix_shot.tscn -- --out=<dir> [--only=main|css|story]
#
# Renders and prints (frame-local numbers, read from the live tree):
#   main_row{0..3}_selected.png   every Main rail selection: the three
#                                 unselected QuietRails + their end x, the
#                                 label glyph boxes, the ActiveRail
#   css_entry.png                 fresh VS defaults (P1 KEYBOARD 1 / P2 NORMAL)
#   css_teams.png                 teams mode (team controls + input readouts)
#   css_committed.png             both slots committed (GLB presentations live)
#   story_select_default.png      Story Fighter Select as the route opens
#   story_select_teknium.png      ... with TEKNIUM selected (PreviewZone)
#   story_briefing.png            the Encounter Briefing after the step

const Roster = preload("res://scripts/roster.gd")
const SelectionState = preload("res://scripts/match_selection_state.gd")

var out_dir := ""
var only := "all"

func _ready() -> void:
	call_deferred("run")

func arg_value(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return fallback

func settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(out_dir + "/" + name + ".png")
		print("owner_fix_shot: " + name + ".png")

func rect_of(node: Control, origin: Vector2) -> String:
	var r := node.get_global_rect()
	return "[x %.1f -> %.1f, y %.1f -> %.1f w %.1f h %.1f]" % [
		r.position.x - origin.x, r.end.x - origin.x,
		r.position.y - origin.y, r.end.y - origin.y, r.size.x, r.size.y]

func glyph_rect(label: Label, origin: Vector2) -> Rect2:
	# The text the player reads: the label's own shaped extent, not its box.
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	var w: float = font.get_string_size(str(label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var r := label.get_global_rect()
	return Rect2(r.position + Vector2(-origin.x, -origin.y), Vector2(w, r.size.y))

# ------------------------------------------------------------------- main --
func run_main() -> void:
	for index in 4:
		var home = load("res://scenes/home.tscn").instantiate()
		add_child(home)
		await settle(30)
		home.select_row(index, true)
		await settle(40)
		var origin: Vector2 = (home.find_child("ReferenceFrame", true, false) as Control).get_global_rect().position
		print("--- MAIN row %d selected (frame-local x from the 1280x720 ReferenceFrame) ---" % index)
		var rows: Array = home.menu_rows()
		for i in rows.size():
			var quiet: Panel = rows[i].get_node("QuietRail")
			var label: Label = rows[i].get_node("Label")
			var g := glyph_rect(label, origin)
			var q := quiet.get_global_rect()
			print("row %d %-11s quiet=%s visible=%s | label_glyphs x %.1f -> %.1f | gap %.1f" % [
				i, str(label.text), rect_of(quiet, origin), str(quiet.visible),
				g.position.x, g.end.x, q.position.x - origin.x - g.end.x])
		var rail: Panel = rows[index].get_node("ActiveRail")
		print("active rail %s" % rect_of(rail, origin))
		await snap("main_row%d_selected" % index)
		home.queue_free()
		await settle(4)

# -------------------------------------------------------------------- css --
func css_cards() -> Array:
	var cards: Array = []
	for id in Roster.ids():
		cards.append({"id": str(id), "name": Roster.display_name(str(id)).to_upper()})
	return cards

func report_bay(bay: Control, origin: Vector2) -> void:
	var secondary: Control = bay.get_node("SecondaryControls")
	print("  bay %s rect=%s secondary=%s" % [str(bay.name), rect_of(bay, origin), rect_of(secondary, origin)])
	var children := ["InputRow/InputControl", "DifficultyRow/DifficultyControl", "TeamControl"]
	for path in children:
		var node: Control = bay.get_node("SecondaryControls/" + path)
		print("    %-26s visible=%-5s %s text='%s' font=%d" % [path, str(node.visible), rect_of(node, origin),
			str((node as Button).text), (node as Button).get_theme_font_size("font_size")])
	# The owner pass: the footer carries VALUES only, and a value never reaches
	# into the next element (shaped width vs the field it owns).
	var input_chip: Button = bay.get_node("SecondaryControls/InputRow/InputControl")
	var team: Button = bay.get_node("SecondaryControls/TeamControl")
	var font := input_chip.get_theme_font("font")
	var shaped: float = font.get_string_size(str(input_chip.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		input_chip.get_theme_font_size("font_size")).x
	var r := input_chip.get_global_rect()
	print("    value shaped=%.1f px in field %.1f px | chip end %.1f -> team start %.1f (gap %.1f)" % [
		shaped, r.size.x, r.end.x - origin.x, team.get_global_rect().position.x - origin.x,
		team.get_global_rect().position.x - r.end.x])
	var words: Array = []
	for node in secondary.find_children("*", "Label", true, false):
		if node.is_visible_in_tree():
			words.append(str(node.text))
	print("    visible words in the footer: %s" % str(words))

func run_css() -> void:
	var css = load("res://scenes/character_select.tscn").instantiate()
	add_child(css)
	await settle(6)
	css.build(css_cards())
	css.open_with(SelectionState.new())
	await settle(40)
	var origin: Vector2 = (css.find_child("ReferenceFrame", true, false) as Control).get_global_rect().position
	print("--- CSS fresh defaults (frame-local) ---")
	for tile in css.get_tiles():
		var band_label: Label = tile.get_node("NameBand/FighterName")
		print("  tile %-10s rect=%s name='%s' label=%.1fx%.1f font=%d shaped=%.1f" % [
			str(tile.fighter_id), rect_of(tile, origin), str(band_label.text),
			band_label.size.x, band_label.size.y, band_label.get_theme_font_size("font_size"),
			band_label.get_theme_font("font").get_string_size(str(band_label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				band_label.get_theme_font_size("font_size")).x])
	for bay in css.get_bays():
		report_bay(bay, origin)
	await snap("css_entry")
	css._set_mode(1)
	await settle(30)
	print("--- CSS teams mode ---")
	for bay in css.get_bays():
		report_bay(bay, origin)
	await snap("css_teams")
	css._set_mode(0)
	await settle(12)
	css._on_bay_activated(0)
	css._on_tile_pressed("teknium")
	css._on_bay_activated(1)
	css._on_tile_pressed("ggb")
	await settle(50)
	print("--- CSS both slots committed ---")
	for bay in css.get_bays():
		report_bay(bay, origin)
	await snap("css_committed")
	# The pad-less Human readout: CONNECT CONTROLLER is the shipped long value.
	var st = css._state
	st.slots[2]["kind"] = "human"
	st.slots[2]["character"] = "ggb"
	css.refresh_devices()
	await settle(20)
	print("--- CSS pad-less P3 Human (CONNECT CONTROLLER) ---")
	report_bay(css.get_bays()[2], origin)
	await snap("css_padless_p3")
	css.queue_free()
	await settle(4)

# ------------------------------------------------------------------ story --
func story_ids() -> Array:
	var ids: Array = []
	for id in Roster.ids():
		if str(id) != "ice_mage":
			ids.append(str(id))
	return ids

func report_preview(st: Control, origin: Vector2) -> void:
	var zone: Control = st.get_node("ReferenceFrame/SelectBody/PreviewZone")
	for path in ["PreviewLabel", "FighterName", "RenderHolder"]:
		var node: Control = zone.get_node(path)
		print("  %-13s %s" % [path, rect_of(node, origin)])
	var name_label: Label = zone.get_node("FighterName")
	var g := glyph_rect(name_label, origin)
	print("  FighterName glyphs x %.1f -> %.1f, y %.1f -> %.1f (text=%s)" % [
		g.position.x, g.end.x, g.position.y, g.end.y, str(name_label.text)])
	var label: Label = zone.get_node("PreviewLabel")
	var gly := glyph_rect(label, origin)
	print("  PreviewLabel glyphs x %.1f -> %.1f, y %.1f -> %.1f (text=%s)" % [
		gly.position.x, gly.end.x, gly.position.y, gly.end.y, str(label.text)])
	# The owner pass: the roster strip must end inside its own column, so the
	# preview's label block keeps the authored gutter.
	var strip: Control = st.get_node("ReferenceFrame/SelectBody/RosterZone/RosterStrip")
	var tiles: Array = st.roster_tiles()
	for tile in tiles:
		var band_label: Label = tile.get_node("NameBand/FighterName")
		var font := band_label.get_theme_font("font")
		var fs: int = band_label.get_theme_font_size("font_size")
		var shaped: float = font.get_string_size(str(band_label.text), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		print("  tile %-12s size=%.5fx%.5f pos=%s font=%d label=%.5fx%.5f minsize=%s shaped=%.5f text='%s' gr=%s" % [
			str(tile.fighter_id), tile.size.x, tile.size.y, str(tile.position), fs,
			band_label.size.x, band_label.size.y, str(band_label.get_combined_minimum_size()),
			shaped, str(band_label.text), str(band_label.get_global_rect())])
	var last: Control = tiles[tiles.size() - 1] if not tiles.is_empty() else null
	if last != null:
		print("  roster strip %s | last tile %s | gutter to the label block x %.1f" % [
			rect_of(strip, origin), rect_of(last, origin), zone.get_global_rect().position.x - last.get_global_rect().end.x])

func run_story() -> void:
	var st = load("res://scenes/story_select.tscn").instantiate()
	add_child(st)
	await settle(6)
	st.build(story_ids())
	st.open()
	await settle(50)
	var origin: Vector2 = (st.find_child("ReferenceFrame", true, false) as Control).get_global_rect().position
	print("--- STORY SELECT, default (%s selected) ---" % st.selected_fighter_id())
	report_preview(st, origin)
	await snap("story_select_default")
	for id in story_ids():
		st.select_fighter(str(id))
		await settle(6)
		if str(id) in ["teknium", "turbofit", "ggb", "doge_man", "bobo"]:
			await snap("story_select_" + str(id))
	print("--- STORY SELECT, all fighters (glyph extents only) ---")
	for id in story_ids():
		st.select_fighter(str(id))
		await settle(6)
		report_preview(st, origin)
	st.select_fighter("teknium")
	await settle(30)
	await snap("story_select_teknium")
	# DIAGNOSTIC (temporary): is the tile name's trim a stale shape?
	var diag_tiles: Array = st.roster_tiles()
	if not diag_tiles.is_empty():
		var lbl: Label = diag_tiles[0].get_node("NameBand/FighterName")
		print("DIAG before: size=%s font=%d text='%s'" % [str(lbl.size), lbl.get_theme_font_size("font_size"), str(lbl.text)])
		lbl.add_theme_font_size_override("font_size", 11)
		await settle(3)
		lbl.add_theme_font_size_override("font_size", 12)
		await settle(6)
		print("DIAG after re-shape: size=%s font=%d" % [str(lbl.size), lbl.get_theme_font_size("font_size")])
		await snap("story_select_diag_reshape")
	st.queue_free()
	await settle(4)

	var br = load("res://scenes/story_briefing.tscn").instantiate()
	add_child(br)
	await settle(6)
	br.build(story_ids())
	br.open("teknium")
	await settle(50)
	await snap("story_briefing")
	var b_origin: Vector2 = (br.find_child("ReferenceFrame", true, false) as Control).get_global_rect().position
	print("--- STORY BRIEFING (frame-local) ---")
	for path in ["BriefingBody/FighterZone/FighterLabel", "BriefingBody/FighterZone/FighterName",
			"BriefingBody/FighterZone/RenderHolder", "BriefingBody/EnemyZone/EnemyLabel",
			"BriefingBody/EnemyZone/EnemyName", "BriefingBody/EnemyZone/PresentationSlot"]:
		var node: Control = br.get_node("ReferenceFrame/" + path)
		print("  %-30s %s" % [path.split("/")[-1], rect_of(node, b_origin)])
	br.queue_free()
	await settle(4)

# ------------------------------------------------------------------- main --
func run() -> void:
	out_dir = arg_value("out", "")
	if out_dir == "":
		push_error("owner_fix_shot: --out=<dir> required")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	only = arg_value("only", "all")
	if only in ["all", "main"]:
		await run_main()
	if only in ["all", "css"]:
		await run_css()
	if only in ["all", "story"]:
		await run_story()
	print("owner_fix_shot: done")
	get_tree().quit(0)
