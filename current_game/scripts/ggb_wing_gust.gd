extends Node
# GGB side special: Wing Gust (zero-damage push). Owned by ggb_combat (phase "gust").
# Timing mirrors Mike-approved Blender v001: 60 fps frames.
# Tap: rear back 9f -> 3 flaps (3f power down + 5f up) -> 12f recovery.
# Hold: keep flapping while special is held, ~2 s cap, 2 sputter flaps, 15f recovery.
const F := 1.0 / 60.0
const STARTUP := 9 * F
const REST_W := 0.38
const UP_W := -0.24
const DOWN_W := 1.00
const FULL_FLAPS_MAX := 13          # Blender hold: full flaps f22-126
const SPUTTER := [[0.75, 3, 6], [0.5, 4, 7]]
const RANGE := 3.8                  # gust reach in front of GGB (m)
const IMPULSE := 4.0                # wind speed added per full-power downstroke (m/s)
const RECOIL := 0.05                # visual body nudge per downstroke (m)
const HOVER_FALL := 0.8             # max fall speed while gusting in the air (first use per airtime)

var actor
var view
var facing := 1.0
var stage := ""        # startup | flap | recover
var t := 0.0           # time inside current stage
var flap_amp := 1.0
var flap_dn := 3
var flap_up := 5
var flaps_done := 0
var sputter_index := -1
var held_mode := false
var recover_len := 12 * F
var hover := false
var air_used := false
var pushes := []       # test/debug ledger: {target, amount}
var streaks: Array[MeshInstance3D] = []
var streak_life := []

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.92, 1.0, 0.96, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	for i in 12:
		var m := MeshInstance3D.new()
		var q := QuadMesh.new(); q.size = Vector2(1.0, 0.045)
		m.mesh = q
		m.material_override = mat.duplicate()
		m.top_level = true
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		streaks.append(m)
		streak_life.append({"age": -1.0, "speed": 0.0, "alpha": 0.0, "len": 1.0})

func active() -> bool:
	return not stage.is_empty()

func begin(dir: float) -> void:
	facing = dir
	stage = "startup"; t = 0.0
	flaps_done = 0; sputter_index = -1; held_mode = false
	recover_len = 12 * F
	pushes.clear()
	hover = not actor.is_grounded() and not air_used
	if not actor.is_grounded(): air_used = true

func clear() -> void:
	stage = ""; t = 0.0; hover = false
	for i in streaks.size():
		streaks[i].visible = false
		streak_life[i].age = -1.0

func on_ground() -> void:
	air_used = false

func _flap_len() -> float:
	return float(flap_dn + flap_up) * F

func _start_flap(amp: float, dn: int, up: int) -> void:
	stage = "flap"; t = 0.0
	flap_amp = amp; flap_dn = dn; flap_up = up
	_spawn_streaks(amp)

func _held() -> bool:
	return bool(actor._special_was_down)

# Called from ggb_combat.special_tick (after fighter visuals are synced).
func tick(delta: float) -> bool:
	if stage.is_empty(): return false
	t += delta
	var lean := 1.0
	var wing := UP_W
	var recoil := 0.0
	if stage == "startup":
		var f := t / F
		if f < 6.0:
			var u := smoothstep(0.0, 1.0, f / 6.0)
			lean = 1.08 * u; wing = lerpf(REST_W, UP_W - 0.08, u)
		else:
			var u := smoothstep(0.0, 1.0, clampf((f - 6.0) / 3.0, 0.0, 1.0))
			lean = lerpf(1.08, 1.0, u); wing = lerpf(UP_W - 0.08, UP_W, u)
		if t >= STARTUP:
			_start_flap(1.0, 3, 5)
	elif stage == "flap":
		var f := t / F
		var lo := UP_W + (DOWN_W - UP_W) * flap_amp
		var dn_len := flap_dn * F
		if t - delta < dn_len:
			# Deliver exactly one stroke's impulse across the downstroke frames.
			_push((minf(t, dn_len) - maxf(t - delta, 0.0)) / dn_len)
		if f < flap_dn:
			var u := smoothstep(0.0, 1.0, f / flap_dn)
			wing = lerpf(UP_W, lo, u); recoil = RECOIL * flap_amp * u
		else:
			var u := smoothstep(0.0, 1.0, clampf((f - flap_dn) / flap_up, 0.0, 1.0))
			wing = lerpf(lo, UP_W, u); recoil = RECOIL * flap_amp * (1.0 - u)
		if t >= _flap_len():
			if sputter_index >= 0:
				sputter_index += 1
				if sputter_index < SPUTTER.size():
					var s: Array = SPUTTER[sputter_index]
					_start_flap(s[0], s[1], s[2])
				else:
					_recover(15 * F)
			else:
				flaps_done += 1
				if flaps_done < 3:
					_start_flap(1.0, 3, 5)
				elif _held() and flaps_done < FULL_FLAPS_MAX:
					held_mode = true
					_start_flap(1.0, 3, 5)
				elif held_mode and flaps_done >= FULL_FLAPS_MAX:
					sputter_index = 0
					var s: Array = SPUTTER[0]
					_start_flap(s[0], s[1], s[2])
				else:
					_recover(15 * F if held_mode else 12 * F)
	elif stage == "recover":
		var u := smoothstep(0.0, 1.0, clampf(t / recover_len, 0.0, 1.0))
		lean = 1.0 - u; wing = lerpf(UP_W, REST_W, u)
		if t >= recover_len:
			view.apply_gust_pose(0.0, REST_W, 0.0, facing)
			_tick_streaks(delta)
			stage = ""
			return false
	view.apply_gust_pose(lean, wing, recoil, facing)
	_tick_streaks(delta)
	return true

func _recover(length: float) -> void:
	stage = "recover"; t = 0.0; recover_len = length

func before_move(delta: float) -> void:
	actor.velocity.x = move_toward(actor.velocity.x, 0.0, 30.0 * delta)
	if hover:
		actor.velocity.y = maxf(actor.velocity.y - 25.0 * delta, -HOVER_FALL)
		if actor.velocity.y > 0.0: actor.velocity.y = move_toward(actor.velocity.y, 0.0, 40.0 * delta)

# Spread one stroke's impulse across its downstroke frames (fraction = share of this frame).
func _push(fraction: float) -> void:
	var origin: Vector3 = view.body_center_world()
	var space = actor.get_world_3d().direct_space_state
	for target in actor.get_tree().get_nodes_in_group("fighters"):
		if not actor.can_hit(target): continue
		var c: Vector3 = target.global_position + Vector3.UP * 0.9
		var dx: float = (c.x - origin.x) * facing
		var dy: float = absf(c.y - origin.y)
		if dx < -0.3 or dx > RANGE: continue
		if dy > 1.1 + 0.25 * maxf(dx, 0.0): continue
		var ray := PhysicsRayQueryParameters3D.create(origin, c, 2)
		ray.exclude = [actor.get_rid()]
		if not space.intersect_ray(ray).is_empty(): continue
		var falloff := 1.0 - 0.6 * clampf(dx / RANGE, 0.0, 1.0)
		var amount := facing * IMPULSE * flap_amp * falloff * clampf(fraction, 0.0, 1.0)
		target.wind_push_x += amount
		pushes.append({"target": target.character_id, "amount": amount})

func _spawn_streaks(amp: float) -> void:
	var origin: Vector3 = view.body_center_world()
	var count := 3 if amp >= 0.99 else 2
	var spawned := 0
	for i in streaks.size():
		if spawned >= count: break
		if streak_life[i].age >= 0.0: continue
		var m := streaks[i]
		var y := origin.y + randf_range(-0.55, 0.55)
		m.global_position = Vector3(origin.x + facing * randf_range(0.55, 0.9), y, origin.z + 0.35)
		m.rotation = Vector3.ZERO
		streak_life[i] = {"age": 0.0, "speed": randf_range(7.0, 9.5), "alpha": 0.42 * amp, "len": randf_range(0.6, 1.0)}
		m.visible = true
		spawned += 1

func _tick_streaks(delta: float) -> void:
	for i in streaks.size():
		var s: Dictionary = streak_life[i]
		if s.age < 0.0: continue
		s.age += delta
		var life := 0.32
		if s.age >= life:
			s.age = -1.0; streaks[i].visible = false; continue
		var m := streaks[i]
		m.global_position.x += facing * s.speed * delta
		var k: float = s.age / life
		m.scale = Vector3(s.len * (0.6 + 0.8 * k), 1.0, 1.0)
		var a: float = s.alpha * (1.0 - k) * minf(1.0, k * 6.0)
		(m.material_override as StandardMaterial3D).albedo_color.a = a
