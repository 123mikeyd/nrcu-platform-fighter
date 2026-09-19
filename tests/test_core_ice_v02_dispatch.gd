extends SceneTree
## Characterization of unchanged upstream dispatch, NOT optional core Ice parity.
const STEP := 1.0/60.0
var failures := 0
var checks := 0
var routes := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func run():
	var actor = load("res://scripts/fighter.gd").new()
	actor.character_id = "ice_mage"
	root.add_child(actor)
	actor.set_physics_process(false)
	check(actor.humanoid_air_basic != null and actor.humanoid_air_side != null, "real upstream aerial authorities installed")
	if failures: actor.free(); quit(1); return
	# No floor: real is_grounded() must accept air. Manual hooks characterize
	# dispatch/clock ownership, not native input, landing or contact parity.
	for facing in [-1.0,1.0]:
		for aim in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			actor.reset_fighter(Vector3(0,10,0))
			actor.facing = facing
			check(not actor.is_grounded(), "air dispatch prerequisite")
			var side := absf(aim.y) <= .1 and absf(aim.x) > .1
			var expected_move := "up" if aim.y < -.1 else ("down" if aim.y > .1 else "neutral")
			var expected_clip := "humanoid_air_side/Superman" if side else "humanoid_air_"+expected_move+"/"+("Up" if expected_move == "up" else ("Down" if expected_move == "down" else "Neutral"))
			var expected_duration := 10.0/24.0 if side else (.6 if expected_move == "up" else (38.0/30.0 if expected_move == "down" else .5))
			var expected_direction: float = signf(aim.x) if absf(aim.x) > .1 else facing
			actor.basic_attack(aim,true)
			var selected = actor.humanoid_air_side if side else actor.humanoid_air_basic
			var other = actor.humanoid_air_basic if side else actor.humanoid_air_side
			var other_elapsed: float = other.elapsed # reset cancels, but retains old age
			check(selected.active and not other.active, "public air dispatch accepts exactly the expected module")
			check(actor.ice_attack_clip.is_empty(), "v0.2 public air does NOT select IceStrike")
			check(selected.view.current_clip == expected_clip, "public air accepted source identity")
			check(selected.elapsed == 0, "public air accepted age zero")
			check(actor.attack_cooldown == expected_duration, "public air declared duration")
			check(selected.direction == expected_direction and actor.facing == expected_direction, "aim/facing and vertical diagonal priority")
			if not side: check(selected.move == expected_move, "public air basic aimed branch")
			# Match fighter's owner order: decrement budget, then actual air hooks.
			# _tick_character_move alone does not advance these authorities.
			actor.attack_cooldown = maxf(0,actor.attack_cooldown-STEP)
			actor._tick_character_move(STEP)
			actor.humanoid_air_basic.after_tick(STEP)
			actor.humanoid_air_side.after_tick(STEP)
			check(selected.active and selected.elapsed == STEP, "selected public authority advances exactly one tick")
			check(other.elapsed == other_elapsed and not other.active, "unselected public authority remains idle")
			check(actor.attack_cooldown == expected_duration-STEP, "public cooldown advances exactly one tick")
			check(actor.ice_attack_clip.is_empty(), "public air tick does not enter authored helper")
			routes += 1
	actor.free()
	if failures == 0: print("PASS: Ice v0.2 public aerial dispatch characterization; routes=%d checks=%d" % [routes,checks])
	quit(1 if failures else 0)
