extends Node
# title_idle_proof — deterministic idle-stability capture for the Title screen.
#
# Captures the SAME running title instance twice, 10 s of fixed-60 Hz time
# apart (600 frames at --fixed-fps 60), so a byte-identical pair proves the
# idle composite does not move — the owner's title wobble. Windowed, because
# rendering is required (dev tool; packaging only, no game code).
#
#   godot --path <repo> --resolution 1280x720 --fixed-fps 60 --quit-after 2000 \
#     res://tools/title_idle_proof.tscn -- --out=<dir>

func _ready() -> void:
	call_deferred("run")

func arg_value(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.substr(key.length() + 3)
	return fallback

func snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("title_idle_proof: no viewport image")
		return
	var err := image.save_png(path)
	if err != OK:
		push_error("title_idle_proof: save failed " + str(err))
		return
	print("title_idle_proof: " + path + " (%dx%d)" % [image.get_width(), image.get_height()])

func run() -> void:
	var out := arg_value("out", "")
	if out == "":
		push_error("title_idle_proof: --out=<dir> required")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var title = load("res://scenes/title.tscn").instantiate()
	add_child(title)
	for i in 120:
		await get_tree().process_frame          # 2 s settle
	await snap(out + "/title_t02s.png")
	for i in 600:
		await get_tree().process_frame          # +10 s of title idle
	await snap(out + "/title_t12s.png")
	print("title_idle_proof: done (2 frames, 600 fixed frames apart)")
	get_tree().quit(0)
