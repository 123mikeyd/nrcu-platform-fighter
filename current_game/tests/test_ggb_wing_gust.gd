extends SceneTree
# GGB Wing Gust (side special) in a real match: real P1 keys, idle P2 target.
var fails := 0
var arena
var g
var tgt
func _initialize() -> void: call_deferred("run")
func check(ok: bool, msg: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + msg)
	if not ok: fails += 1
func key(code: int, down: bool) -> void:
	var e := InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = down
	Input.parse_input_event(e); Input.flush_buffered_events()
func frames(n: int) -> void:
	for i in n: await physics_frame
func setup(target_char: String, gx: float, tx: float) -> void:
	if arena: arena.queue_free(); await process_frame; await process_frame
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena); await process_frame
	var slots = load("res://scripts/match_config.gd").default_slots()
	slots[0].character = "ggb"; slots[1].kind = "human"; slots[1].character = target_char
	slots[2].kind = "empty"; slots[3].kind = "empty"
	arena.start_match(slots, false)
	g = arena.fighters[0]; tgt = arena.fighters[1]
	await frames(100)
	g.global_position = Vector3(gx, g.global_position.y, 0); g.velocity = Vector3.ZERO
	tgt.global_position = Vector3(tx, tgt.global_position.y, 0); tgt.velocity = Vector3.ZERO
	g.facing = 1.0 if tx > gx else -1.0
	await frames(30)
func gust_active() -> bool:
	return g.ggb_combat != null and g.ggb_combat.phase == "gust"
func side_b(dir_key: int, hold_frames: int) -> Dictionary:
	var x0: float = tgt.global_position.x
	var dmg0: float = tgt.damage_percent
	key(dir_key, true); key(KEY_G, true)
	var active_frames := 0
	var max_hitstun := 0.0
	var max_fall := 0.0
	var n := 0
	var released := false
	while n < 300:
		await physics_frame; n += 1
		if n == hold_frames and not released:
			key(KEY_G, false); key(dir_key, false); released = true
		if gust_active(): active_frames += 1
		max_hitstun = maxf(max_hitstun, tgt.hitstun)
		if gust_active() and not g.is_grounded(): max_fall = maxf(max_fall, -g.velocity.y)
		if n > 10 and not gust_active() and released: break
	if not released: key(KEY_G, false); key(dir_key, false)
	await frames(60)
	var strokes := 0
	if g.ggb_combat and g.ggb_combat.gust:
		pass
	return {"dx": tgt.global_position.x - x0, "dmg": tgt.damage_percent - dmg0, "active": active_frames,
		"hitstun": max_hitstun, "max_fall": max_fall, "pushes": g.ggb_combat.gust.pushes.size() if g.ggb_combat else 0,
		"last_move": g.last_move}
func run() -> void:
	var fps: int = Engine.physics_ticks_per_second
	print("physics fps ", fps)
	for ch in ["teknium", "doge_man", "turbofit"]:
		await setup(ch, -1.0, 0.8)
		var r := await side_b(KEY_D, 3)
		print("TAP ", ch, " ", r)
		check(r.last_move == "WING GUST", ch + " D+G routes to WING GUST")
		check(r.dx > 1.2 and r.dx < 4.0, ch + " tap pushes target right 1.2-4 m (got %.2f)" % r.dx)
		check(r.dmg == 0.0 and r.hitstun == 0.0, ch + " zero damage, no hitstun")
		check(absf(float(r.active) / fps - 0.75) < 0.06, ch + " tap lasts ~0.75 s (got %.3f)" % (float(r.active) / fps))
	# Hold
	await setup("teknium", -1.0, 0.8)
	var h := await side_b(KEY_D, 200)
	print("HOLD ", h)
	check(absf(float(h.active) / fps - (0.15 + 2.067 + 0.25)) < 0.08, "hold lasts ~2.47 s incl. startup/recovery (got %.3f)" % (float(h.active) / fps))
	check(h.dx > 2.3, "hold pushes further than tap (got %.2f)" % h.dx)
	# Early release during hold
	await setup("teknium", -1.0, 0.8)
	var e := await side_b(KEY_D, 60)
	print("HOLD_1s ", e)
	check(float(e.active) / fps > 0.9 and float(e.active) / fps < 1.6, "releasing at 1 s ends the gust early (got %.3f)" % (float(e.active) / fps))
	# Target behind is not pushed
	await setup("teknium", 0.5, -1.5)
	g.facing = 1.0
	var b := await side_b(KEY_D, 3)
	check(absf(b.dx) < 0.05, "target behind GGB is not pushed (got %.3f)" % b.dx)
	# Facing left
	await setup("teknium", 1.0, -0.8)
	var l := await side_b(KEY_A, 3)
	check(l.dx < -1.2, "A+G pushes target left (got %.2f)" % l.dx)
	# Out of range
	await setup("teknium", -3.0, 2.5)
	var o := await side_b(KEY_D, 3)
	check(absf(o.dx) < 0.05, "target 5.5 m away is not pushed (got %.3f)" % o.dx)
	# Airborne: hover once per airtime
	await setup("teknium", -1.0, 0.8)
	key(KEY_SPACE, true); await frames(3); key(KEY_SPACE, false); await frames(14)
	var a := await side_b(KEY_D, 3)
	check(a.max_fall <= 0.85 and a.max_fall >= 0.0, "air gust hovers (max fall %.2f m/s)" % a.max_fall)
	# Interrupt: GGB hit mid-gust cancels cleanly and resets the pose
	await setup("teknium", -1.0, 0.8)
	key(KEY_D, true); key(KEY_G, true); await frames(20)
	check(gust_active(), "gust active at 20 frames")
	g.receive_hit_from(8.0, Vector3(-1, 0.3, 0), 4.0, tgt)
	await frames(2)
	key(KEY_G, false); key(KEY_D, false)
	check(not gust_active(), "getting hit cancels the gust")
	var gv = g.get_node("VisualRoot/GGBVisual")
	var streak_vis := false
	for s in g.ggb_combat.gust.streaks: streak_vis = streak_vis or s.visible
	check(not streak_vis, "wind streaks hidden after cancel")
	await frames(90)
	check(gv.model.transform.basis.is_equal_approx(Basis.IDENTITY), "model pose back to rest after cancel")
	# Neutral special still Sticky Goo; down still Steel
	await setup("teknium", -1.0, 2.0)
	key(KEY_G, true); await frames(3); key(KEY_G, false); await frames(5)
	check(g.last_move == "STICKY GOO", "neutral G is still Sticky Goo")
	await frames(40)
	key(KEY_S, true); key(KEY_G, true); await frames(3); key(KEY_G, false); key(KEY_S, false); await frames(5)
	check(g.last_move == "STEEL FORM", "S+G is still Steel Form")
	print("WING_GUST_TEST fails=", fails)
	quit(1 if fails else 0)
