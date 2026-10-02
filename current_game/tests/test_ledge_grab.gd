extends SceneTree
# Ledge grab gameplay checks in the real main scene with raw key events, for every fighter in
# ledge_grab.gd CONFIG (Doge Man, Teknium, TurboFit).
# Optional: LEDGE_TEST_OUT=<dir> writes ledge_test.json there.
var arena
var rows = []
var failures := 0
var checks := 0
var log = []
func _initialize(): call_deferred("run")
func frames(n):
	for i in n: await physics_frame
	await process_frame
func key(code, down):
	var e = InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = down
	Input.parse_input_event(e); Input.flush_buffered_events()
func tap(code):
	key(code, true); await frames(2); key(code, false); await frames(1)
func check(ok, msg, info = ""):
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", msg, " ", info)
	else: print("ok   ", msg, " ", info)
	rows.append({"check": msg, "pass": bool(ok), "info": str(info)})
func build(p1: String, p2: String):
	var ids = load("res://scripts/match_config.gd").CHARACTERS
	arena.setup.rows[0].character.select(ids.find(p1))
	arena.setup.rows[1].character.select(ids.find(p2))
	arena.setup.rows[0].kind.select(0); arena.setup.rows[1].kind.select(0)
	arena.setup.rows[2].kind.select(2); arena.setup.rows[3].kind.select(2)
	arena.setup._start()
	await frames(140)
func hands_mid(f) -> Vector3:
	var sk: Skeleton3D = f.ledge_grab.skeleton
	var lb := sk.find_bone("LeftHand"); var rb := sk.find_bone("RightHand")
	if lb < 0: lb = sk.find_bone("mixamorig_LeftHand"); rb = sk.find_bone("mixamorig_RightHand")
	var l = sk.global_transform * sk.get_bone_global_pose(lb).origin
	var r = sk.global_transform * sk.get_bone_global_pose(rb).origin
	return (l + r) * 0.5
func ledge_of(f, s: float) -> Dictionary:
	for l in f.ledge_grab.ledges():
		if l.side == s: return l
	return {}
func drop_near(f, l: Dictionary, dx := 0.8, above_hang := 0.9):
	var h: Vector3 = f.ledge_grab.hang_spot(l.edge, l.side)
	f.reset_fighter(Vector3(l.edge.x + l.side * 6.0, 4.0, 0), true); await frames(3)
	f.reset_fighter(Vector3(h.x + l.side * (dx - 0.31), h.y + above_hang, 0), true)
	f.velocity = Vector3.ZERO
func wait_phase(f, want: String, max_ticks := 120) -> int:
	for i in max_ticks:
		if f.ledge_grab.phase == want: return i
		await frames(1)
	return -1
func playing(f) -> String:
	return str(f.ledge_grab.view.animation_player.current_animation)

func run_fighter(cid: String, other: String):
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	await build(cid, other)
	var d = arena.player_one; var o = arena.player_two
	var T := cid + " "
	check(d.ledge_grab != null, T + "has the ledge component")
	o.reset_fighter(Vector3(0, 0.1, 0), false)
	for s in [1.0, -1.0]:
		var tag = T + ("R" if s > 0 else "L")
		var l = ledge_of(d, s)
		check(not l.is_empty(), tag + " ledge found", str(l))
		# 1) falling grab
		await drop_near(d, l)
		var t = await wait_phase(d, "catch", 90)
		check(t >= 0, tag + " falling fighter grabs the ledge", "ticks=%d" % t)
		check(d.facing == -s, tag + " faces the stage while hanging", "facing=%s" % d.facing)
		check(d.is_ledge_intangible(), tag + " intangible on grab")
		check(playing(d) == "LedgeCatch", tag + " plays LedgeCatch", playing(d))
		var t2 = await wait_phase(d, "hang", 60)
		check(t2 >= 0, tag + " catch finishes into hang", "ticks=%d" % t2)
		await frames(10)
		var hm = hands_mid(d)
		var body_out = (d.global_position.x - l.edge.x) * s
		check(absf(hm.x - l.edge.x) < 0.35 and absf(hm.y - l.edge.y) < 0.35, tag + " hands at the ledge corner", "hands=%s edge=%s" % [hm, l.edge])
		check(body_out > 0.0, tag + " body hangs outside the stage", "origin_out=%.2f" % body_out)
		check(playing(d) == "LedgeHang", tag + " plays LedgeHang", playing(d))
		var p0 = d.global_position
		var hand_min := Vector3(INF, INF, INF); var hand_max := -hand_min
		for i in 90:
			await frames(1)
			var h := hands_mid(d); hand_min = hand_min.min(h); hand_max = hand_max.max(h)
		check(d.ledge_grab.phase == "hang" and d.global_position.distance_to(p0) < 0.001, tag + " holds position while hanging (1.5 s)")
		check((hand_max - hand_min).length() < 0.08, tag + " hands stay put while hanging", "span=%.3f m" % (hand_max - hand_min).length())
		check(not d.is_ledge_intangible(), tag + " intangibility has expired while hanging")
		# 2) climb with a fresh Up
		await tap(KEY_W)
		check(d.ledge_grab.phase == "climb", tag + " W starts the climb", d.ledge_grab.phase)
		check(playing(d) == "LedgeClimb", tag + " plays LedgeClimb", playing(d))
		for i in 120:
			if d.ledge_grab.phase != "climb": break
			await frames(1)
		await frames(20)
		check(d.ledge_grab.phase == "idle" and d.ledge_grab.last_event == "climbed", tag + " climb completes", d.ledge_grab.last_event)
		check(d.is_grounded(), tag + " standing on the stage after the climb", "pos=%s" % d.global_position)
		check((l.edge.x - d.global_position.x) * s > 0.3, tag + " finished inside the edge", "x=%.2f edge=%.2f" % [d.global_position.x, l.edge.x])
		# TurboFit's passive idle is MoshIdleV004 (the visual swaps Idle -> Mosh on its own).
		check(playing(d) == "Idle" or (cid == "turbofit" and playing(d) == "MoshIdleV004"), tag + " back in the ordinary Idle", playing(d))
		log.append({"fighter": cid, "side": tag, "climb_end_pos": str(d.global_position), "view_y": d.ledge_grab.view.position.y})
		# 3) drop with Down, then no instant regrab
		await drop_near(d, l)
		await wait_phase(d, "hang", 150)
		await frames(5)
		await tap(KEY_S)
		check(d.ledge_grab.phase == "idle" and d.ledge_grab.last_event == "drop", tag + " S drops off the ledge", d.ledge_grab.last_event)
		await frames(20)
		check(d.ledge_grab.phase == "idle", tag + " no instant regrab after dropping")
		# 4) ledge jump
		await drop_near(d, l)
		await wait_phase(d, "hang", 150)
		await frames(5)
		await tap(KEY_SPACE)
		check(d.ledge_grab.last_event == "ledge_jump" and d.velocity.y > 0, tag + " Space ledge-jumps upward", "vy=%.2f" % d.velocity.y)
		var landed = false
		for i in 150:
			await frames(1)
			if d.is_grounded(): landed = true; break
		check(landed and absf(d.global_position.y - l.edge.y) < 0.2 and (l.edge.x - d.global_position.x) * s > 0, tag + " ledge jump lands on the stage", "pos=%s" % d.global_position)
		# 5) holding Down while falling = no grab
		await drop_near(d, l)
		key(KEY_S, true)
		var grabbed = false
		for i in 60:
			await frames(1)
			if d.ledge_grab.active(): grabbed = true; break
		key(KEY_S, false)
		check(not grabbed, tag + " holding S while falling does not grab")
		await frames(5); d.ledge_grab.cancel()
	# 6) Tek only: W+G aim recovery from well below the grab window rises, then catches on the way down
	if cid == "teknium":
		var lr = ledge_of(d, 1.0)
		await drop_near(d, lr, 0.8, -2.4)
		var was_special := false
		key(KEY_W, true); key(KEY_G, true); await frames(3); key(KEY_G, false)
		var tg := -1
		for i in 150:
			if d.teknium_specials.phase != "idle": was_special = true
			if d.ledge_grab.phase == "catch": tg = i; break
			await frames(1)
		key(KEY_W, false)
		check(was_special, T + "W+G recovery started below the ledge", d.teknium_specials.phase)
		check(tg >= 0, T + "W+G recovery can catch the ledge", "ticks=%d event=%s" % [tg, d.ledge_grab.last_event])
		if tg >= 0:
			await frames(3)
			check(playing(d) == "LedgeCatch", T + "ledge owns the pose after a recovery catch", playing(d))
			check(d.teknium_specials.phase == "idle", T + "Tek special cancelled by the grab", d.teknium_specials.phase)
		d.ledge_grab.cancel(); d.reset_fighter(Vector3(0, 0.1, 0), false); await frames(30)
	# 6t) TurboFit only: a guitar that is out when he grabs (mid swing) is put away, and stays away while hanging
	if cid == "turbofit":
		var gm = d.ledge_grab.view.guitar_moves
		var lg = ledge_of(d, 1.0)
		await drop_near(d, lg)
		gm.guitar.visible = true; gm.mode = "swing"
		var tgg = await wait_phase(d, "catch", 90)
		check(tgg >= 0, T + "grabs with the guitar out", "ticks=%d" % tgg)
		var shown := 0
		await wait_phase(d, "hang", 60)
		for i in 30:
			await frames(1)
			if gm.guitar.visible: shown += 1
		check(shown == 0, T + "guitar hidden while hanging", "visible_frames=%d mode=%s" % [shown, gm.mode])
		d.ledge_grab.cancel(); d.reset_fighter(Vector3(0, 0.1, 0), false); await frames(30)
	# 6b) air-hit exit race: hitstun ends inside the grab window, the ledge catch must keep its pose
	var lh = ledge_of(d, 1.0)
	await drop_near(d, lh, 0.8, 0.3)
	d.hitstun = 0.1
	var tc := -1
	for i in 60:
		if d.ledge_grab.phase == "catch": tc = i; break
		await frames(1)
	check(tc >= 0, T + "grabs right after air hitstun ends", "ticks=%d" % tc)
	var bad := 0
	for i in 8:
		await frames(1)
		if d.ledge_grab.active() and playing(d) not in ["LedgeCatch", "LedgeHang"]: bad += 1
	check(bad == 0, T + "air-reaction exit never overwrites the ledge pose", "bad_frames=%d clip=%s" % [bad, playing(d)])
	d.ledge_grab.cancel(); d.reset_fighter(Vector3(0, 0.1, 0), false); await frames(30)
	# 7) hits: intangible on grab, vulnerable (and knocked off) later
	var l = ledge_of(d, 1.0)
	await drop_near(d, l)
	await wait_phase(d, "catch", 90)
	var dmg0 = d.damage_percent
	d.receive_hit_from(10, Vector3(1, 0.3, 0), 5, o)
	check(d.damage_percent == dmg0 and d.ledge_grab.active(), T + "hit during grab intangibility is ignored", "dmg=%.1f" % d.damage_percent)
	await wait_phase(d, "hang", 60); await frames(30)
	d.receive_hit_from(10, Vector3(1, 0.3, 0), 5, o)
	await frames(2)
	check(d.damage_percent > dmg0 and not d.ledge_grab.active(), T + "hit while hanging deals damage and knocks him off", "dmg=%.1f phase=%s" % [d.damage_percent, d.ledge_grab.phase])
	await frames(120)
	# 8) hang timeout
	d.reset_fighter(Vector3(0, 0.1, 0), false); await frames(30)
	await drop_near(d, l)
	await wait_phase(d, "hang", 150)
	var th = 0
	while d.ledge_grab.phase == "hang" and th < 400: await frames(1); th += 1
	check(d.ledge_grab.last_event == "timeout", T + "auto-drops after hanging too long", "ticks=%d event=%s" % [th, d.ledge_grab.last_event])
	# 9) stock loss while hanging clears the ledge
	d.reset_fighter(Vector3(0, 0.1, 0), false); await frames(30)
	await drop_near(d, l)
	await wait_phase(d, "hang", 150)
	d.lose_stock()
	check(not d.ledge_grab.active() and not d.ledge_grab.occupied.has(l.key), T + "stock loss clears ledge state and occupancy")
	for code in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_G, KEY_SPACE, KEY_F]: key(code, false)
	arena.queue_free(); await frames(3)

func run():
	var cfg: Dictionary = load("res://scripts/ledge_grab.gd").CONFIG
	check(cfg.has("doge_man") and cfg.has("teknium") and cfg.has("turbofit"), "ledge CONFIG has Doge Man, Teknium and TurboFit", str(cfg.keys()))
	await run_fighter("doge_man", "teknium")
	await run_fighter("teknium", "doge_man")
	await run_fighter("turbofit", "doge_man")
	var out := OS.get_environment("LEDGE_TEST_OUT")
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
		var f = FileAccess.open(out + "/ledge_test.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows, "log": log}, "  ")); f.close()
	print("LEDGE_TEST_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
