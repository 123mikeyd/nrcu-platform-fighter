extends Control
# Offline portrait generator (Doc 04 §7) — the roster's placeholder portraits
# are generated ONCE from the shared FighterRenderView PORTRAIT profile and
# saved as ordinary 2D PNGs, so the roster never owns a live 3D viewport and
# final character art can replace the PNGs at the same paths.
#
# Usage (real windowed run — rendering is required, this is NOT headless):
#   cd C:/Users/will/nrcu-platform-fighter
#   "C:/Users/will/Documents/obligate/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe" \
#     --path C:/Users/will/nrcu-platform-fighter --resolution 1280x720 \
#     res://tools/portrait_gen.tscn -- --out=res://assets/portraits
#
# Optional args:
#   --out=res://assets/portraits   output directory
#   --profile=PORTRAIT|PLAYER_BAY|RESULTS_HERO|RESULTS_TEAM
#   --size=320x240                 render size override (default: profile size)
#   --ids=teknium,ggb              subset inspection run (default: whole roster)
#   --prefix=body_                 filename prefix (default: "")
#
# Writes one 320x320 bust PNG per scripts/roster.gd id to <out>/<id>.png and
# quits with code 0 only when every id was saved. Wait frames before capture:
# fighters attach their visual meshes a few frames after instantiation, so the
# tool keeps requesting render frames until the target shows real content.
#
# After generating, run the editor import pass once so the PNGs load as
# textures in headless runs:
#   python tools/run_all_tests.py --engine "<engine>" --import-only

const Roster = preload("res://scripts/roster.gd")
const View = preload("res://scripts/frontend/fighter_render_view.gd")

const MAX_WAIT_FRAMES := 120
const MIN_CONTENT_SAMPLES := 40
const ALPHA_THRESHOLD := 24

func _ready() -> void:
	call_deferred("run")

func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return fallback

func run() -> void:
	var out_dir := _arg("out", "res://assets/portraits")
	var profile := _arg("profile", View.PROFILE_PORTRAIT)
	var prefix := _arg("prefix", "")
	var abs_dir := ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		printerr("PORTRAIT_GEN cannot create output dir: " + abs_dir)
		get_tree().quit(1)
		return
	var view = View.new()
	view.name = "PortraitView"
	add_child(view)
	view.set_profile(profile)
	var size_arg := _arg("size", "")
	if size_arg != "":
		var parts := size_arg.split("x")
		if parts.size() == 2:
			view.set_render_size(Vector2i(int(parts[0]), int(parts[1])))
	await get_tree().process_frame
	var ids: Array = Roster.ids()
	var selection := _arg("ids", "")
	if selection != "":
		ids = []
		for part in selection.split(","):
			if str(part).strip_edges() != "":
				ids.append(str(part).strip_edges())
	var saved := 0
	for id in ids:
		view.set_palette(0)
		view.set_subjects([str(id)])
		view.request_render()
		for i in 2: await get_tree().process_frame
		var box: AABB = view.model_aabb()
		var framed: AABB = view.framed_box()
		print("PORTRAIT_GEN aabb %s visible=%s framed=%s" % [str(id), str(box), str(framed)])
		var img: Image = await _capture(view)
		if img == null:
			printerr("PORTRAIT_GEN no rendered content for " + str(id))
			continue
		var path := abs_dir.path_join(prefix + str(id) + ".png")
		var err := img.save_png(path)
		if err != OK:
			printerr("PORTRAIT_GEN save failed for " + str(id) + " (err %d)" % err)
			continue
		saved += 1
		print("PORTRAIT_GEN %s -> %s (%dx%d)" % [str(id), path, img.get_width(), img.get_height()])
	print("PORTRAIT_GEN saved=%d/%d" % [saved, ids.size()])
	get_tree().quit(0 if saved == ids.size() else 1)

func _capture(view) -> Image:
	# Render-on-change: keep requesting frames until the model has arrived and
	# the target shows real pixels.
	for i in MAX_WAIT_FRAMES:
		view.request_render()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = view.render_target().get_image()
		if img != null and _has_content(img):
			return img
	return null

func _has_content(img: Image) -> bool:
	var data := img.get_data()
	var samples := 0
	var i := 3
	while i < data.size():
		if data[i] > ALPHA_THRESHOLD:
			samples += 1
			if samples >= MIN_CONTENT_SAMPLES:
				return true
		i += 16
	return false
