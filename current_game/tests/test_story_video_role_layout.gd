extends SceneTree
var failures := 0
func _initialize() -> void:
	root.unfocusable = true
	root.position = Vector2i(-16000, -16000)
	call_deferred("run")
func run() -> void:
	var out := OS.get_environment("STORY_VIDEO_EVIDENCE")
	if out.is_empty():
		quit(1)
		return
	var ending = load("res://scripts/story_ending.gd").new()
	root.add_child(ending)
	await process_frame
	ending.play("teknium")
	ending._motion.kill()
	ending._begin_movies()
	await create_timer(1.3).timeout
	ending.set_process(false)
	var lines: Array = ending.roll.get_children()
	for i in range(lines.size() - 1):
		if lines[i].position.y + lines[i].get_minimum_size().y > lines[i+1].position.y:
			failures += 1
			print("FAIL: credit line overlaps: ", lines[i].text)
	var frames := {"Producer": "credits_role_first", "Development": "credits_hermes_roles", "Game State Controller Coordinator": "credits_other_contributors"}
	for label in lines:
		if frames.has(label.text):
			ending.roll.position.y = 12 - label.position.y
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join(frames[label.text] + ".png"))
	ending.cancel()
	ending.queue_free()
	await process_frame
	print("PASS: role-first credits native layout, no overlapping text" if failures == 0 else "FAIL: credit layout")
	quit(0 if failures == 0 else 1)
