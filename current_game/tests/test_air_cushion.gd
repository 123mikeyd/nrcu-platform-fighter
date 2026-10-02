extends SceneTree
# Double-jump air cushion: fires only on the 2nd jump, right style per fighter,
# none for first/walk-off jumps or GGB, self-clears, pooled (no node growth).
func _initialize() -> void: call_deferred("run")
var fails := 0
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + message)
	if not ok: fails += 1
func fx_live(f) -> bool:
	return f.air_cushion_fx != null and f.air_cushion_fx.clock >= 0.0
func run() -> void:
	var expect := {"teknium": "ring", "doge_man": "puff", "turbofit": "whoosh"}
	for ch in ["teknium", "doge_man", "turbofit", "ggb", "witcheer"]:
		var f = load("res://scripts/fighter.gd").new()
		f.character_id = ch
		root.add_child(f)
		f.set_physics_process(false)
		await process_frame
		check(f.try_jump(), ch + " first jump accepted")
		check(not fx_live(f), ch + " no cushion on first jump (ground or walk-off)")
		f.try_jump()
		if expect.has(ch):
			check(fx_live(f) and f.air_cushion_fx.cur_style == expect[ch], ch + " 2nd jump fires " + expect[ch])
			var kids: int = f.air_cushion_fx.get_child_count()
			for i in 30: await process_frame
			f.air_cushion_fx._process(0.5)
			var any_visible := false
			for c in f.air_cushion_fx.get_children(): any_visible = any_visible or c.visible
			check(not fx_live(f) and not any_visible, ch + " cushion fades out and hides")
			for n in 5:
				f.reset_air_resources(); f.try_jump(); f.try_jump()
			check(f.air_cushion_fx.get_child_count() == kids and f.get_children().filter(func(c): return c.name.begins_with("AirCushionFX")).size() == 1, ch + " pooled: no node growth after repeats")
			f.air_cushion_fx.clear()
			f.reset_air_resources(); f.try_jump()
			check(not fx_live(f), ch + " after landing, first jump still clean")
		else:
			for i in 4: f.try_jump()
			check(f.air_cushion_fx == null, ch + " gets no cushion")
		f.queue_free()
		await process_frame
	print("AIR_CUSHION_TEST fails=", fails)
	quit(1 if fails else 0)
