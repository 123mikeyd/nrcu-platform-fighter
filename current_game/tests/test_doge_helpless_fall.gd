extends SceneTree
# Helpless-fall install test (copy). Real key input; logs bone motion, inputs, landing, both facings, miss + success.
# Optional evidence: HELPLESS_TEST_OUT=<file> writes the JSON rows there.
var OUT := OS.get_environment("HELPLESS_TEST_OUT")
var arena; var checks := []; var fails := []; var log_rows := []
func ck(ok, label):
	checks.append({"test": label, "pass": bool(ok)})
	if not ok: fails.append(label); print("FAIL ", label)
	else: print("PASS ", label)
func fr(n := 1):
	for i in n: await physics_frame; await process_frame
func key(k, d):
	var e := InputEventKey.new(); e.physical_keycode = k; e.keycode = k; e.pressed = d
	Input.parse_input_event(e); Input.flush_buffered_events()
func tap(k):
	key(k, true); await fr(2); key(k, false); await fr(1)
func pose_sig(sk: Skeleton3D) -> Array:
	var out := []
	for n in ["Hips", "LeftArm", "RightArm", "LeftUpLeg", "RightLeg", "Head"]:
		out.append(sk.get_bone_pose_rotation(sk.find_bone(n)))
	return out
func sig_delta(a: Array, b: Array) -> float:
	var m := 0.0
	for i in a.size(): m = maxf(m, (a[i] as Quaternion).angle_to(b[i]))
	return m
func _initialize(): call_deferred("run")
func run():
	arena = load("res://scenes/main.tscn").instantiate(); root.add_child(arena); await process_frame
	var config = load("res://scripts/match_config.gd")
	for i in 4:
		var row = arena.setup.rows[i]; row.character.select(config.CHARACTERS.find("doge_man" if i == 0 else "ggb")); row.kind.select(0 if i < 2 else 2); row.team.select(i % 2); row.device.select(0)
	arena.setup._refresh(); arena.setup._start(); await fr(170)
	for b in arena.find_children("*", "StaticBody3D", true, false):
		if b.name in ["LeftPlatform", "RightPlatform", "TopPlatform"]: b.collision_layer = 0; b.collision_mask = 0
	var a = arena.fighters[0]; var t = arena.fighters[1]; var m = a.air_doge
	var view = a._visual_root.get_node("DogeVisual"); var ap: AnimationPlayer = view.animation_player
	var sk: Skeleton3D = m.skeleton
	ck(ap.has_animation("HelplessFall"), "clip registered")
	ck(ap.get_animation("HelplessFall").loop_mode == Animation.LOOP_LINEAR, "clip loops")
	for branch in ["miss", "success"]:
		for face in [-1, 1]:
			var tag := "%s face=%d" % [branch, face]
			a.reset_fighter(Vector3(-2, 6.5, 0), true); t.reset_fighter(Vector3(12 if branch == "miss" else 6, 4, 0), true)
			await fr(2)
			key(KEY_A if face < 0 else KEY_D, true); await fr(2); key(KEY_A if face < 0 else KEY_D, false)
			var move_before = a.last_move
			key(KEY_W, true); key(KEY_G, true); await fr(2); key(KEY_W, false); key(KEY_G, false)
			ck(m.active(), "accepted " + tag)
			var placed := false; var entered := -1; var landed := -1; var prev := []; var max_entry_step := 0.0; var max_fall_step := 0.0
			var max_land_step := 0.0; var helpless_frames := 0; var moving_frames := 0; var facing_ok := true; var inputs_blocked := true
			var lm_at_fall := ""
			for i in 360:
				await fr(1)
				if branch == "success" and m.phase == "catch" and not placed:
					t.global_position += m.center() - t._visual_root.get_node("GGBVisual").body_center_world(); t.global_position.z = 0; t.velocity = Vector3(-face * 2, 1, 0); placed = true
				var s := pose_sig(sk)
				var step := sig_delta(s, prev) if prev.size() > 0 else 0.0
				prev = s
				if m.phase == "fall":
					if entered < 0: entered = i; lm_at_fall = a.last_move
					helpless_frames += 1
					if i > entered and (view.current_clip != "HelplessFall" or ap.current_animation != "HelplessFall"): facing_ok = false
					if i - entered <= 10: max_entry_step = maxf(max_entry_step, step)
					else:
						max_fall_step = maxf(max_fall_step, step)
						if step > 0.0005: moving_frames += 1
					if absf(view.model.rotation.y - face * PI / 2) > 0.01 or a.facing != face: facing_ok = false
					# mash everything during helpless; none may start a move
					if i - entered in [4, 12, 20]:
						key(KEY_SPACE, true); key(KEY_F, true); key(KEY_G, true); key(KEY_W, true)
					elif i - entered in [6, 14, 22]:
						key(KEY_SPACE, false); key(KEY_F, false); key(KEY_G, false); key(KEY_W, false)
					# hold opposite direction for drift
					if i - entered == 2: key(KEY_D if face < 0 else KEY_A, true)
				if entered >= 0 and m.phase == "fall" and (a.last_move != lm_at_fall or a.jumps_used < 2): inputs_blocked = false
				if m.phase == "landing" and landed < 0: landed = i; key(KEY_A, false); key(KEY_D, false)
				if landed >= 0 and m.phase == "landing": max_land_step = maxf(max_land_step, step)
				log_rows.append({"tag": tag, "i": i, "phase": m.phase, "clip": view.current_clip, "anim": ap.current_animation, "step": step, "y": a.global_position.y, "vx": a.velocity.x})
				if landed >= 0 and i > landed + 25: break
			key(KEY_SPACE, false); key(KEY_F, false); key(KEY_G, false); key(KEY_W, false); key(KEY_A, false); key(KEY_D, false)
			ck(entered >= 0, "entered helpless " + tag)
			ck(helpless_frames > 20, "helpless lasted %d frames %s" % [helpless_frames, tag])
			ck(facing_ok, "HelplessFall clip + facing held " + tag)
			ck(inputs_blocked, "jump/attack/special blocked in helpless " + tag)
			ck(moving_frames > helpless_frames * 0.5, "wiggle moving %d/%d %s" % [moving_frames, helpless_frames, tag])
			ck(landed >= 0, "landed " + tag)
			ck(not m.active(), "released after landing " + tag)
			ck(branch == "miss" or m.damage_count == 1, "success throw dealt damage " + tag)
			ck(max_land_step < 0.6, "landing blend smooth (max %.3f rad/frame) %s" % [max_land_step, tag])
			ck(max_entry_step < 0.4, "entry blend smooth (max %.3f rad/frame) %s" % [max_entry_step, tag])
			print("STEPS ", tag, " entry_max=%.3f fall_max=%.3f land_max=%.3f" % [max_entry_step, max_fall_step, max_land_step])
			await fr(20)
	# long drop: keeps looping (no freeze) for > 2 loops
	for b in arena.find_children("*", "StaticBody3D", true, false):
		if b.name == "MainPlatform": b.collision_layer = 0; b.collision_mask = 0
	a.reset_fighter(Vector3(-2, 6.5, 0), true); t.reset_fighter(Vector3(12, 40, 0), true); await fr(2)
	key(KEY_W, true); key(KEY_G, true); await fr(2); key(KEY_W, false); key(KEY_G, false)
	var sigs := []; var times := []
	for i in 300:
		await fr(1)
		if m.phase == "fall": sigs.append(pose_sig(sk)); times.append(ap.current_animation_position)
		if not m.active() or sigs.size() > 230: break
	var wraps := 0
	for i in range(1, times.size()): if times[i] < times[i - 1]: wraps += 1
	var late_motion := sig_delta(sigs[sigs.size() - 1], sigs[sigs.size() - 15]) if sigs.size() > 20 else 0.0
	ck(wraps >= 1 and sigs.size() > 60, "long drop loops (%d wraps over %d frames)" % [wraps, sigs.size()])
	ck(late_motion > 0.005, "still moving late in long drop")
	if OUT != "": FileAccess.open(OUT, FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "fails": fails, "rows": log_rows}, " "))
	print("HELPLESS_TEST_DONE pass=%d fail=%d" % [checks.size() - fails.size(), fails.size()])
	quit()
