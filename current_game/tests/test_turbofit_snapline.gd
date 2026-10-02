extends SceneTree
# Headless logic test for the TurboFit Snapline Up-B review MVP (real keys through the real controller).
var failures := 0
var log_lines: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("FAIL: " + message)
	else: print("ok   " + message)
func key(code: int, down: bool) -> void:
	var e := InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = down
	Input.parse_input_event(e); Input.flush_buffered_events()
func tap(codes: Array, frames := 2) -> void:
	for c in codes: key(c, true)
	for i in frames: await physics_frame
	for c in codes: key(c, false)

func run() -> void:
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena); await process_frame
	var slots = load("res://scripts/match_config.gd").default_slots()
	slots[0].character = "turbofit"; slots[1].kind = "human"; slots[1].character = "doge_man"
	slots[2].kind = "empty"; slots[3].kind = "empty"
	check(arena.start_match(slots, false), "match starts")
	var t = arena.fighters[0]
	var snap = t.get_node_or_null("TurboFitSnapline")
	check(snap != null, "Snapline component exists on TurboFit")
	check(arena.fighters[1].get_node_or_null("TurboFitSnapline") == null, "Doge has no Snapline component")
	var visual = t.get_node("VisualRoot/TurboFitVisual")
	for i in 90: await physics_frame
	check(t.is_on_floor(), "Turbo settled on floor")

	# ---------- AIR (primary use): jump, start falling, Up-B ----------
	await tap([KEY_SPACE], 3)
	var guard := 0
	while not (t.velocity.y < -1.0) and guard < 120: await physics_frame; guard += 1
	var y_press: float = t.global_position.y
	await tap([KEY_W, KEY_G], 2)
	check(snap.active() and snap.kind == "AIR", "air Up-B starts Snapline AIR")
	check(t.recovery_spent and t.jumps_used == 2, "recovery + jumps spent on start")
	check(visual.current_clip == "SnaplineAir", "SnaplineAir clip presented")
	var phases := {}; var min_y := y_press; var y_kick := 0.0; var y_top := -INF; var cushion_seen := false
	var guitar_seen := false; var whip_seen := false; var pos_jump := 0.0; var prev: Vector3 = t.global_position
	var frames := 0; var retrigger_tested := false
	while snap.active() and frames < 200:
		await physics_frame; frames += 1
		phases[snap.phase] = true
		pos_jump = maxf(pos_jump, (t.global_position - prev).length()); prev = t.global_position
		if snap.phase in ["draw", "whip"]: min_y = minf(min_y, t.global_position.y)
		if snap.phase == "reel" and y_kick == 0.0: y_kick = t.global_position.y
		if snap.cushion.visible: cushion_seen = true
		if snap.guitar.visible: guitar_seen = true
		if snap.barb.visible: whip_seen = true
		if frames == 10 and not retrigger_tested:
			retrigger_tested = true; var s0: int = snap.starts
			await tap([KEY_W, KEY_G], 2); frames += 2
			check(snap.starts == s0, "Up-B during Snapline does not restart it")
	var y_end: float = t.global_position.y
	check(phases.has("draw") and phases.has("whip") and phases.has("reel"), "went draw -> whip -> reel: " + str(phases.keys()))
	check(absf(frames / 60.0 - 42.0 / 30.0) < 0.1, "air move duration ~1.40 s (got %.3f)" % (frames / 60.0))
	check(y_press - min_y < 0.6, "fall is stalled during the draw (dropped %.2f)" % (y_press - min_y))
	check(y_end - y_kick > 2.5, "reel rises > 2.5u (rose %.2f)" % (y_end - y_kick))
	check(guitar_seen and whip_seen and cushion_seen, "guitar, whip string and air cushion all shown")
	check(pos_jump < 0.4, "no teleport (max step %.3f)" % pos_jump)
	check(not snap.guitar.visible and not snap.barb.visible, "FX hidden after finish")
	check(t.recovery_spent and t.jumps_used == 2, "still spent after finish (no helpless, no refund mid-air)")
	for i in 20:
		await physics_frame
		y_top = maxf(y_top, t.global_position.y)
	check(visual.current_clip in ["FallLoop", "Jump"], "exits into native air clip (" + visual.current_clip + ")")
	check(y_top - y_end < 0.3, "apex at end of reel, then falls (extra rise %.2f)" % (y_top - y_end))
	var s1: int = snap.starts
	await tap([KEY_W, KEY_G], 2)
	check(snap.starts == s1 and not snap.active(), "second Up-B in same airtime refused")
	guard = 0
	while not t.is_on_floor() and guard < 400: await physics_frame; guard += 1
	for i in 3: await physics_frame
	check(t.is_on_floor() and not t.recovery_spent, "landing refunds recovery")
	print("AIR y_press=%.2f min_y=%.2f y_kick=%.2f y_end=%.2f frames=%d" % [y_press, min_y, y_kick, y_end, frames])

	# ---------- GROUND start ----------
	for i in 30: await physics_frame
	var gy: float = t.global_position.y
	await tap([KEY_W, KEY_G], 2)
	check(snap.active() and snap.kind == "GROUND", "ground Up-B starts Snapline GROUND")
	check(visual.current_clip == "SnaplineGround", "SnaplineGround clip presented")
	var refunded := false; var gframes := 0; var left_floor_early := false
	while snap.active() and gframes < 220:
		await physics_frame; gframes += 1
		if not t.recovery_spent: refunded = true
		if snap.phase in ["draw", "whip"] and t.global_position.y > gy + 0.05: left_floor_early = true
	check(not refunded, "no refund while grounded during the move")
	check(not left_floor_early, "stays planted until the hop kick")
	check(t.global_position.y - gy > 2.5, "ground Snapline rises > 2.5u (rose %.2f)" % (t.global_position.y - gy))
	guard = 0
	while not t.is_on_floor() and guard < 400: await physics_frame; guard += 1
	for i in 3: await physics_frame

	# ---------- facing left ----------
	await tap([KEY_A], 4)
	for i in 20: await physics_frame
	check(t.facing < 0, "facing left")
	var x0: float = t.global_position.x
	await tap([KEY_W, KEY_G], 2)
	while snap.active(): await physics_frame
	check(t.global_position.x < x0 - 0.2, "latch leans forward when facing left (dx %.2f)" % (t.global_position.x - x0))
	guard = 0
	while not t.is_on_floor() and guard < 400: await physics_frame; guard += 1
	for i in 3: await physics_frame

	# ---------- hit interrupt ----------
	await tap([KEY_SPACE], 3)
	for i in 8: await physics_frame
	await tap([KEY_W, KEY_G], 2)
	for i in 12: await physics_frame
	check(snap.active(), "active before interrupt")
	t.hitstun = 0.3
	await physics_frame; await physics_frame
	check(not snap.active() and not snap.guitar.visible and snap.cancels >= 1, "hitstun cancels Snapline and hides FX")
	check(t.recovery_spent, "interrupted Snapline stays spent")
	print("STATS starts=%d completes=%d cancels=%d" % [snap.starts, snap.completes, snap.cancels])
	if failures == 0: print("PASS: Snapline air/ground/facing/interrupt/refund")
	else: print("FAILURES: %d" % failures)
	quit(1 if failures else 0)
