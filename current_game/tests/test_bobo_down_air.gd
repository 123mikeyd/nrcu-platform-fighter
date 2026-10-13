extends SceneTree
## godot --headless --path . -s res://tests/test_bobo_down_air.gd
var fails := 0
var arena
var b
var tgt
var hold_b := false
var hold_b_y := 0.0
var hold_t := false
var hold_t_pos := Vector3.ZERO
func _initialize() -> void: call_deferred("run")
func check(ok: bool, msg: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + msg)
	if not ok: fails += 1
func step() -> void:
	# physics_frame fires before node physics: pin suspended fighters here.
	await physics_frame
	if hold_b:
		b.global_position.y = hold_b_y; b.velocity = Vector3.ZERO
	if hold_t and tgt.hitstun <= 0.0:
		tgt.global_position = hold_t_pos; tgt.velocity = Vector3.ZERO
func frames(n: int) -> void:
	for i in n: await step()
func setup() -> void:
	if arena: arena.queue_free(); await process_frame; await process_frame
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena); await process_frame
	var slots = load("res://scripts/match_config.gd").default_slots()
	slots[0].character = "bobo"; slots[1].kind = "human"; slots[1].character = "teknium"
	slots[2].kind = "empty"; slots[3].kind = "empty"
	arena.start_match(slots, false)
	b = arena.fighters[0]; tgt = arena.fighters[1]
	await frames(240)
func reset_b(pos: Vector3, suspend: bool) -> void:
	hold_b = suspend; hold_b_y = pos.y
	b.global_position = pos; b.velocity = Vector3.ZERO
	b.facing = 1.0; b.attack_cooldown = 0.0; b.landing_lag = 0.0; b.hitstun = 0.0
	if b.down_air.active: b.down_air.cancel()
	await physics_frame
	b.global_position = pos; b.velocity = Vector3.ZERO
func park_target(pos: Vector3) -> void:
	hold_t = true; hold_t_pos = pos
	tgt.global_position = pos; tgt.velocity = Vector3.ZERO; tgt.hitstun = 0.0
	if tgt.tumble: tgt.tumble.clear()
func claw_bottom() -> Vector3:
	# Lowest point of the two live claw hulls (same data the move queries).
	var v = b._visual_root.get_node("BoboVisual")
	var sk: Skeleton3D = v.model.find_children("*", "Skeleton3D", true, false)[0]
	var best := Vector3(0, INF, 0)
	for event in b.thrust_manifest.hits:
		var tr: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(str(event.bone)))
		var zs := []
		for p in event.hull_points:
			var w: Vector3 = tr * Vector3(p[0], p[1], p[2])
			zs.append(w.z)
			if w.y < best.y: best = w
		if print_z: print("  hull %s z %.2f..%.2f" % [event.bone, zs.min(), zs.max()])
	return best
var print_z := false
func top_of(f) -> float:
	var top := 2.0
	for c in f.get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			top = c.position.y + c.shape.height * 0.5
	return f.global_position.y + top
func hand_pose() -> Transform3D:
	var v = b._visual_root.get_node("BoboVisual")
	var sk: Skeleton3D = v.contact.sk
	return sk.get_bone_global_pose(sk.find_bone("LeftHand"))
func run() -> void:
	await setup()
	var floor_y: float = b.global_position.y
	var v = b._visual_root.get_node("BoboVisual")
	var lib: AnimationLibrary = v.animation_player.get_animation_library("")
	check(lib.has_animation("DownAir") and lib.has_animation("AirIdle"), "DownAir + AirIdle clips loaded into player Bobo's library")
	check(absf(lib.get_animation("DownAir").length - 41.0 / 30.0) < 0.002, "DownAir clip spans Blender f1-f41 (%.4f s)" % lib.get_animation("DownAir").length)
	# --- 1. grounded down + attack is still the old crouch Down A ---
	park_target(Vector3(8, floor_y, 0))
	await reset_b(Vector3(-4, floor_y, 0), false)
	await frames(20)
	check(b.is_grounded(), "Bobo grounded for the Down A check")
	b.basic_attack(Vector2(0, 1), not b.is_grounded())
	check(b.down_a_active and not b.down_air.active and b.last_move == "LOW CLAW", "grounded down+attack = LOW CLAW Down A (last_move %s)" % b.last_move)
	await frames(10)
	b.cancel_down_a()
	await frames(10)
	# --- 2. air down + attack starts the move, clip advances, no target in reach ---
	await reset_b(Vector3(-4, floor_y + 5.0, 0), true)
	check(not b.is_grounded(), "Bobo airborne (suspended)")
	b.basic_attack(Vector2(0, 1), true)
	check(b.down_air.active and b.last_move == "CLAW HAMMER DROP", "air down+attack starts CLAW HAMMER DROP (last_move %s)" % b.last_move)
	await frames(1)
	await process_frame
	check(v.current_clip == "DownAir", "visual shows DownAir (got %s)" % v.current_clip)
	var h0 := hand_pose()
	var e0: float = b.down_air.elapsed
	await frames(12)
	var e1: float = b.down_air.elapsed
	check(e1 > e0 + 0.15, "move clock advances (%.3f -> %.3f)" % [e0, e1])
	check(h0.origin.distance_to(hand_pose().origin) > 5.0, "LeftHand pose actually moves during wind-up (%.1f rig units)" % h0.origin.distance_to(hand_pose().origin))
	# flip is not attack- or special-cancelable
	while b.down_air.active and b.down_air.elapsed < 0.65: await step()
	check(b.down_air.in_flip(), "in the flip at %.2f s" % b.down_air.elapsed)
	b.basic_attack(Vector2(1, 0), true)
	b.start_special(Vector2(0, -1))
	check(b.down_air.active and b.last_move == "CLAW HAMMER DROP" and b.special_move.is_empty(), "flip ignores attack / special presses")
	check(not b.try_jump(), "flip ignores jump")
	var guard := 0
	while b.down_air.active and guard < 120: await step(); guard += 1
	await frames(2)
	await process_frame
	check(not b.down_air.active and b.attack_cooldown <= 0.0, "move completes in the air after %d more frames" % guard)
	check(v.current_clip == "AirIdle" and v.air_idle_on, "settles into the approved AirIdle while still airborne (got %s)" % v.current_clip)
	# Measure the claw spike point for target placement (dry run, no target near).
	await reset_b(Vector3(-4, floor_y + 5.0, 0), true)
	b.basic_attack(Vector2(0, 1), true)
	while b.down_air.active and b.down_air.elapsed < b.down_air.ACTIVE_END - 0.01: await step()
	print_z = true
	var cb := claw_bottom()
	print_z = false
	var rel: Vector3 = cb - b.global_position
	print("claw bottom rel to Bobo at e=%.3f: %s" % [b.down_air.elapsed, rel])
	check(rel.y < 1.0 and absf(rel.x) < 1.2, "claws are low (below the belly) at the spike (rel %s)" % rel)
	await frames(60)
	# --- 3. hit lands in the active window only, below the claws, and spikes ---
	var bx := -2.0
	var by := floor_y + 6.0
	var tpos := Vector3(bx + rel.x, by + rel.y - (top_of(tgt) - tgt.global_position.y) + 0.2, 0)
	park_target(tpos)
	await reset_b(Vector3(bx, by, 0), true)
	var d0: float = tgt.damage_percent
	b.basic_attack(Vector2(0, 1), true)
	var hit_e := -1.0
	var min_vy := 99.0
	var vx := 0.0
	for i in 70:
		await step()
		if tgt.damage_percent > d0 and hit_e < 0.0: hit_e = b.down_air.elapsed
		if tgt.hitstun > 0.0:
			min_vy = minf(min_vy, tgt.velocity.y)
			if vx == 0.0: vx = tgt.velocity.x
	var dealt: float = tgt.damage_percent - d0
	print("spike: dealt=%s contacts=%s min_vy=%s vx=%s" % [dealt, b.down_air.contacts, min_vy, vx])
	check(is_equal_approx(dealt, b.down_air.DAMAGE), "spike deals %s%% once (got %s)" % [b.down_air.DAMAGE, dealt])
	var cf: float = b.down_air.contacts[-1].frame if b.down_air.contacts.size() else -1.0
	check(cf >= 15.0 - 0.01 and cf <= 17.0 + 0.01, "contact happened inside active f15-17 (f%.2f)" % cf)
	check(min_vy < -1.0, "spike sends the target downward (min vy %.2f)" % min_vy)
	check(vx * b.facing >= 0.0, "spike drifts slightly toward Bobo's facing, never backward (vx %.2f)" % vx)
	hold_t = false
	await frames(150)
	# --- 4. no hit on a target above Bobo's head or far beside him ---
	for case in [["above head", Vector3(bx, by + 2.6, 0)], ["far beside", Vector3(bx + 3.2, by - 0.8, 0)]]:
		await setup()
		park_target(case[1])
		await reset_b(Vector3(bx, by, 0), true)
		d0 = tgt.damage_percent
		b.basic_attack(Vector2(0, 1), true)
		guard = 0
		while b.down_air.active and guard < 120: await step(); guard += 1
		check(tgt.damage_percent == d0, "no hit on a target %s (dmg +%s)" % [case[0], tgt.damage_percent - d0])
	# --- 5. no hit during the flip: target slid under the claws only after f17 ---
	await setup()
	park_target(Vector3(bx + 6.0, by, 0))
	await reset_b(Vector3(bx, by, 0), true)
	d0 = tgt.damage_percent
	b.basic_attack(Vector2(0, 1), true)
	while b.down_air.active and b.down_air.elapsed <= b.down_air.ACTIVE_END + 0.01: await step()
	park_target(tpos)
	var low_seen := 99.0
	guard = 0
	while b.down_air.active and guard < 120:
		await step(); guard += 1
		low_seen = minf(low_seen, claw_bottom().y - b.global_position.y)
	check(tgt.damage_percent == d0, "target parked under Bobo during flip/jets/settle is never hit (dmg +%s)" % (tgt.damage_percent - d0))
	check(low_seen < rel.y + 0.4, "the claws do pass low again during the flip (min rel y %.2f), so the no-hit check is meaningful" % low_seen)
	hold_t = false
	# --- 6. landing mid-move ends it with its landing lag ---
	park_target(Vector3(8, floor_y, 0))
	await reset_b(Vector3(-4, floor_y + 0.6, 0), false)
	b.basic_attack(Vector2(0, 1), not b.is_grounded())
	check(b.down_air.active, "short-hop height down air starts")
	var seen_lag := 0.0
	guard = 0
	while guard < 60:
		await step(); guard += 1
		seen_lag = maxf(seen_lag, b.landing_lag)
		if not b.down_air.active and b.is_grounded() and seen_lag > 0.0: break
	check(not b.down_air.active, "landing cut the move")
	check(is_equal_approx(b.down_air.last_landing_lag, b.down_air.LANDING_LAG) and seen_lag > b.down_air.LANDING_LAG - 0.02, "landing lag %.2f s applied (seen %.3f)" % [b.down_air.LANDING_LAG, seen_lag])
	b.basic_attack(Vector2(1, 0), false)
	check(not b.thrust_active, "no ground attack during landing lag")
	await frames(30)
	b.attack_cooldown = 0.0
	b.basic_attack(Vector2(1, 0), false)
	check(b.thrust_active, "side claws work again after the landing lag")
	print("RESULT ", "PASS" if fails == 0 else "FAIL", " fails=", fails)
	print("BOBO_DOWN_AIR_COMPLETE");quit(1 if fails else 0)
