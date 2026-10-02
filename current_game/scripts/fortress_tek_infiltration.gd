extends Node3D
# Fortress background cameo: Solid Teknium infiltrates the fortress.
# Mike's low-poly Teknium (23 bones, albedo-only, 512px) with Tek's retargeted clips, plus
# generic shadow ninjas. Decorative only: no collision, physics, lights, audio or text.
# Runs a ~40 s pass every 5-10 min of Fortress play; while waiting it is hidden and its
# AnimationPlayer is off, so the only cost is one float subtraction per frame.
# The Fortress stage owns the clock (advance); pause freezes it.

const MODEL := preload("res://assets/solid_teknium/solid_teknium_v002_light.glb")
const TEK_SCALE := 0.8
const STEP := 0.24          # seconds per path contact while walking
const LF := 1.0 / 24.0      # Laser Blast clip frame (same timing as the in-game move)
const INTRO := 1.6          # ninjas take position before Teknium appears
const STOP := 0.96          # route time where he stops to fire
const SHOTS := [1.05, 3.35] # Laser Blast clip starts, one per ninja
const RESUME := 3.35 + 56 * LF + 0.15
const BEAM_TIME := 0.3
const FALL_DELAY := 0.25
const PLANT_TIME := 1.6
const BACK_TIME := 1.5
const FUSE_TIME := 0.85
const BOOM_TIME := 1.35
const SHUTTER_TIME := 1.1
const DOOR_POS := Vector3(-12.0, 15.38, -15.22)
const C4_POS := Vector3(-11.86, 15.05, -15.17)

var contacts: Array[Vector3] = []
var clock := 0.0
var active_pass := false
var wait_remaining := 0.0
var schedule_rng := RandomNumberGenerator.new()
var phase := "waiting"
var plant_route := 0.0
var back_route := 0.0
var pivot: Node3D
var model: Node3D
var anim: AnimationPlayer
var gun: Node3D
var clip := ""
var ninjas: Array = []
var ninja_parts: Array = []
var fallen: Array = [false, false]
var hits: Array = [0, 0]
var tele_line: MeshInstance3D
var beam: MeshInstance3D
var flash: MeshInstance3D
var c4: Node3D
var c4_led: MeshInstance3D
var door: Node3D
var door_panel: MeshInstance3D
var scorch: MeshInstance3D
var fireball: MeshInstance3D
var smoke: Array = []
var m_solid: StandardMaterial3D
var m_glow: StandardMaterial3D

# ---------------------------------------------------------------- helpers
func glow(c: Color, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	if alpha < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
func mesh(shape: Mesh, m: Material, parent: Node3D) -> MeshInstance3D:
	var n := MeshInstance3D.new(); n.mesh = shape; n.material_override = m; n.layers = 2
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(n); return n
func solid(parent: Node3D, pieces: Array, m: Material) -> MeshInstance3D:
	# Several vertex-coloured boxes merged into one mesh = one draw call.
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for piece in pieces:
		var cube := BoxMesh.new(); cube.size = piece[1]
		var arrays := cube.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in arrays[Mesh.ARRAY_INDEX]:
			st.set_color(Color(piece[2])); st.set_normal(nrm[index]); st.add_vertex(v[index] + piece[0])
	return mesh(st.commit(), m, parent)
func add_line(a: Vector3, b: Vector3, spacing: float) -> void:
	var count := maxi(1, int(ceil(a.distance_to(b) / spacing)))
	for i in range(1, count + 1): contacts.append(a.lerp(b, float(i) / count))
func nearest(p: Vector3) -> int:
	var best := 0
	for i in contacts.size():
		if contacts[i].distance_to(p) < contacts[best].distance_to(p): best = i
	return best

# ---------------------------------------------------------------- build
func _ready() -> void:
	name = "TekInfiltrationCameo"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	m_solid = StandardMaterial3D.new(); m_solid.vertex_color_use_as_albedo = true; m_solid.roughness = 0.95
	m_glow = glow(Color.WHITE); m_glow.vertex_color_use_as_albedo = true
	# Service route: entry deck, three flights, upper walkway, upper service door.
	contacts.append(Vector3(-21.4, 1.74, -8.2))
	add_line(contacts[-1], Vector3(-18, 1.74, -8.2), 0.4)
	for i in 20: contacts.append(Vector3(-18 + 0.4 * (i + 0.5), 1.74 + 3.74 * (i + 1) / 20.0, -8.2))
	add_line(contacts[-1], Vector3(-10, 5.48, -9.6), 0.4)
	for i in 24: contacts.append(Vector3(-10 - 8.0 / 24 * (i + 0.5), 5.48 + 4.5 * (i + 1) / 24.0, -9.6))
	add_line(contacts[-1], Vector3(-18, 9.98, -8.2), 0.4)
	for i in 24: contacts.append(Vector3(-18 + 8.0 / 24 * (i + 0.5), 9.98 + 4.5 * (i + 1) / 24.0, -8.2))
	add_line(contacts[-1], Vector3(-10.6, 14.48, -8.2), 0.35)
	add_line(contacts[-1], Vector3(-10.6, 14.48, -14.1), 0.4)
	add_line(contacts[-1], Vector3(-12, 14.48, -14.1), 0.35)
	add_line(contacts[-1], Vector3(-12, 14.48, -16.5), 0.35)
	plant_route = (nearest(Vector3(-12, 14.48, DOOR_POS.z + 0.5)) - 1) * STEP
	back_route = (nearest(Vector3(-10.9, 14.48, -14.1)) - 1) * STEP
	# Solid Teknium.
	pivot = Node3D.new(); pivot.name = "SolidTeknium"; pivot.scale = Vector3.ONE * TEK_SCALE; add_child(pivot)
	model = MODEL.instantiate(); pivot.add_child(model)
	model.rotation.y = PI / 2.0   # model faces +X; the pivot yaws it along the route
	for g in model.find_children("*", "GeometryInstance3D", true, false):
		g.layers = 2; g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for c in ["Idle", "Walk", "Run", "Block"]:
		anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	gun = model.find_child("SolidTek_Blaster", true, false)
	for i in 2: _build_ninja(i)
	_build_fx()
	_build_door.call_deferred()
	schedule_rng.randomize()
	wait_remaining = schedule_rng.randf_range(300.0, 600.0)
	_sleep()

func _build_ninja(i: int) -> void:
	var ninja := Node3D.new(); ninja.name = "ShadowNinja%d" % (i + 1); ninja.top_level = true; add_child(ninja)
	var torso := Node3D.new(); ninja.add_child(torso); torso.position.y = 0.72
	solid(torso, [[Vector3(0, 0.22, 0), Vector3(0.36, 0.46, 0.23), "343846"], [Vector3(0, 0.02, 0), Vector3(0.38, 0.08, 0.26), "9a1c24"],
		[Vector3(0, 0.57, 0), Vector3(0.23, 0.25, 0.24), "272a35"], [Vector3(0, 0.575, -0.118), Vector3(0.2, 0.06, 0.012), "14151b"],
		[Vector3(0, 0.36, 0.14), Vector3(0.05, 0.62, 0.04), "0c0c0f"], [Vector3(0, 0.72, 0.14), Vector3(0.035, 0.16, 0.035), "4a2a1a"]], m_solid)
	# Red eyes: unshaded, so they read in the dark without a light.
	solid(torso, [[Vector3(-0.055, 0.585, -0.095), Vector3(0.07, 0.03, 0.075), "ff1a0d"],
		[Vector3(0.055, 0.585, -0.095), Vector3(0.07, 0.03, 0.075), "ff1a0d"]], m_glow)
	var arms: Array = []; var legs: Array = []
	for side in [-1.0, 1.0]:
		var arm := Node3D.new(); torso.add_child(arm); arm.position = Vector3(side * 0.23, 0.38, 0)
		solid(arm, [[Vector3(0, -0.16, 0), Vector3(0.13, 0.34, 0.14), "343846"], [Vector3(0, -0.38, -0.02), Vector3(0.11, 0.14, 0.12), "1a1c24"]], m_solid); arms.append(arm)
		var leg := Node3D.new(); ninja.add_child(leg); leg.position = Vector3(side * 0.11, 0.72, 0)
		solid(leg, [[Vector3(0, -0.27, 0), Vector3(0.15, 0.52, 0.18), "30333f"], [Vector3(0, -0.64, -0.03), Vector3(0.15, 0.12, 0.25), "15161c"]], m_solid); legs.append(leg)
	ninjas.append(ninja); ninja_parts.append([torso, arms, legs])

func _build_fx() -> void:
	var cyl := CylinderMesh.new(); cyl.top_radius = 1; cyl.bottom_radius = 1; cyl.height = 1; cyl.radial_segments = 6; cyl.rings = 1
	var ball := SphereMesh.new(); ball.radius = 1; ball.height = 2; ball.radial_segments = 8; ball.rings = 4
	tele_line = mesh(cyl, glow(Color(0.05, 0.95, 0.85), 0.8), self); tele_line.top_level = true
	beam = mesh(cyl, glow(Color(0.75, 1.0, 1.0)), self); beam.top_level = true
	flash = mesh(ball, glow(Color(0.85, 1.0, 1.0)), self); flash.top_level = true
	c4 = Node3D.new(); c4.top_level = true; add_child(c4); c4.position = C4_POS
	solid(c4, [[Vector3.ZERO, Vector3(0.22, 0.14, 0.06), "c8b98f"], [Vector3(0, 0, 0.035), Vector3(0.23, 0.03, 0.01), "2a2a2a"]], m_solid)
	c4_led = solid(c4, [[Vector3(0.07, 0.045, 0.035), Vector3(0.035, 0.035, 0.02), "ff1a0d"]], m_glow)
	fireball = mesh(ball, glow(Color(1.0, 0.55, 0.15), 0.9), self); fireball.top_level = true
	for k in 3:
		var puff := mesh(ball, glow(Color(0.3, 0.31, 0.33), 0.7), self); puff.top_level = true; smoke.append(puff)

func _build_door() -> void:
	# The service door stays on the stage between passes (closed); one merged mesh.
	door = Node3D.new(); door.name = "TekCameoServiceDoor"; get_parent().add_child(door); door.position = DOOR_POS
	door_panel = solid(door, [[Vector3.ZERO, Vector3(1.0, 1.78, 0.06), "4f5d66"],
		[Vector3(0, -0.62, 0.035), Vector3(0.92, 0.12, 0.012), "c99a3a"], [Vector3(0, 0.62, 0.035), Vector3(0.92, 0.12, 0.012), "c99a3a"],
		[Vector3(0.36, -0.05, 0.04), Vector3(0.07, 0.16, 0.02), "1b2027"]], m_solid)
	scorch = solid(door, [[Vector3(0, -0.3, 0.035), Vector3(0.9, 0.9, 0.01), "050505"]], m_glow); scorch.hide()

# ---------------------------------------------------------------- clock API
func duration() -> float: return INTRO + _t_shutter_end()
func _fire_time(i: int) -> float: return float(SHOTS[i]) + 29 * LF
func _t_walk1_end() -> float: return RESUME + (plant_route - STOP)
func _t_plant_end() -> float: return _t_walk1_end() + PLANT_TIME
func _t_back_end() -> float: return _t_plant_end() + BACK_TIME
func _t_boom() -> float: return _t_back_end() + FUSE_TIME
func _t_walk2_start() -> float: return _t_boom() + BOOM_TIME * 0.8
func _t_walk2_end() -> float: return _t_walk2_start() + (route_end() - back_route)
func _t_shutter_end() -> float: return _t_walk2_end() + SHUTTER_TIME
func route_end() -> float: return (contacts.size() - 3) * STEP

func advance(delta: float) -> void:
	if not active_pass:
		wait_remaining -= delta
		if wait_remaining <= 0.0: trigger_for_test()
		return
	clock += delta
	if clock >= duration():
		wait_remaining = schedule_rng.randf_range(300.0, 600.0)
		_sleep()
		return
	update_sequence(clock)
func _sleep() -> void:
	active_pass = false; phase = "waiting"; clock = 0.0
	hide(); anim.active = false; _reset_door()
func trigger_for_test() -> void:
	active_pass = true; clock = 0.0; anim.active = true; show(); update_sequence(0.0)
func seed_schedule_for_test(value: int) -> void:
	schedule_rng.seed = value; wait_remaining = schedule_rng.randf_range(300.0, 600.0); _sleep()
func snapshot_for_test(t: float) -> void:
	if t >= duration(): _sleep(); return
	active_pass = true; anim.active = true; clock = t; show(); update_sequence(t)
func sequence_state() -> Dictionary:
	return {"hits": hits.duplicate(), "fallen": fallen.duplicate(), "phase": phase}
func _reset_door() -> void:
	if not is_instance_valid(door): return
	door_panel.position = Vector3.ZERO; door_panel.rotation = Vector3.ZERO; door_panel.show(); scorch.hide()

# ---------------------------------------------------------------- Teknium
func path_pose(r: float, backwards := false) -> void:
	var k := clampi(int(r / STEP), 0, contacts.size() - 3)
	position = contacts[k + 1].lerp(contacts[k + 2], clampf(fmod(r, STEP) / STEP, 0, 1))
	var ahead: Vector3 = contacts[mini(k + 3, contacts.size() - 1)] - contacts[k]
	ahead.y = 0
	face(-ahead if backwards else ahead)
func face(dir: Vector3) -> void:
	if dir.length() > 0.001: pivot.rotation.y = atan2(-dir.z, dir.x)
func play(c: String, blend := 0.12) -> void:
	if clip != c:
		clip = c; anim.speed_scale = 1.0; anim.play(c, blend)
	elif not anim.is_playing(): anim.play(c)

# ---------------------------------------------------------------- sequence
func update_sequence(time: float) -> void:
	var t := maxf(0.0, time - INTRO)
	tele_line.hide(); beam.hide(); flash.hide(); gun.visible = false
	c4.visible = false; fireball.hide()
	for p in smoke: p.hide()
	if t < _t_boom(): _reset_door()
	pivot.visible = true
	if t < STOP:
		phase = "enter"; path_pose(t); play("Walk")
	elif t < RESUME:
		phase = "laser"; path_pose(STOP); _laser(t)
	elif t < _t_walk1_end():
		phase = "climb"; path_pose(STOP + t - RESUME); play("Walk")
	elif t < _t_plant_end():
		phase = "plant"; path_pose(plant_route); face(Vector3(0, 0, -1))
		var u := t - _t_walk1_end()
		play("CrouchHold" if u < PLANT_TIME * 0.82 else "Idle", 0.22)
		c4.visible = u > PLANT_TIME * 0.4
		c4_led.visible = fmod(u * 3.0, 1.0) < 0.5
	elif t < _t_back_end():
		phase = "retreat"; path_pose(lerpf(plant_route, back_route, (t - _t_plant_end()) / BACK_TIME), true); play("Run")
		c4.visible = true; c4_led.visible = fmod(t * 5.0, 1.0) < 0.5
	elif t < _t_walk2_start():
		phase = "boom"; path_pose(back_route); face(DOOR_POS - position); play("Block", 0.15)
		if t < _t_boom():
			c4.visible = true; c4_led.visible = fmod(t * 12.0, 1.0) < 0.5
		else:
			_explosion(t - _t_boom()); _door_blown(t - _t_boom())
	elif t < _t_walk2_end():
		phase = "enter_door"; path_pose(back_route + t - _t_walk2_start()); play("Walk")
		_explosion(t - _t_boom()); _door_blown(t - _t_boom())
	else:
		phase = "shutter"; path_pose(route_end()); pivot.visible = false
		_explosion(t - _t_boom())
		# A fresh shutter drops in behind him; the fortress resets for next time.
		var s := (t - _t_walk2_end()) / SHUTTER_TIME
		door_panel.show(); door_panel.rotation = Vector3.ZERO
		door_panel.position = Vector3(0, lerpf(1.9, 0.0, smoothstep(0.0, 1.0, s)), 0)
		scorch.visible = s < 0.7
	for i in 2: _update_ninja(i, time, t)

func _laser(t: float) -> void:
	var target_index := 0 if t < SHOTS[1] else 1
	var target := _ninja_spot(target_index) + Vector3(0, 1.0, 0)
	face(target - position)
	var start: float = SHOTS[target_index]
	if t < start:
		play("Idle"); return
	# Tek's Laser Blast clip, sampled on the cameo clock. The gun is just in his hand.
	var f := clampf(t - start, 0.0, 56 * LF) / LF
	if clip != "LaserBlast":
		clip = "LaserBlast"; anim.play("LaserBlast", 0.0)
	anim.seek(f * LF, true); anim.pause()
	gun.visible = f >= 3.0 and f < 44.0
	if f < 10.0 or f >= 35.0: return
	var muzzle_pos: Vector3 = gun.global_position + (target - gun.global_position).normalized() * 0.2
	var aim := target
	aim.y = lerpf(muzzle_pos.y, target.y, 0.5)
	if f < 28.0:
		_stretch(tele_line, muzzle_pos, muzzle_pos.lerp(aim, clampf((f - 10.0) / 8.0, 0, 1)), 0.018)
	elif f < 29.0:
		flash.global_position = muzzle_pos; flash.scale = Vector3.ONE * 0.14; flash.show()
	else:
		var fade := 1.0 - (t - _fire_time(target_index)) / BEAM_TIME
		if fade <= 0.0: return
		_stretch(beam, muzzle_pos, aim, 0.045 * fade + 0.02)
		flash.global_position = aim; flash.scale = Vector3.ONE * (0.08 + 0.18 * (1.0 - fade)); flash.show()

func _stretch(n: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	var length := maxf(a.distance_to(b), 0.001)
	var rot := Basis(Quaternion(Vector3.UP, (b - a).normalized())) if length > 0.002 else Basis()
	n.global_transform = Transform3D(rot * Basis.from_scale(Vector3(radius, length, radius)), (a + b) * 0.5)
	n.show()

func _explosion(a: float) -> void:
	if a < 0.0: return
	var f := a / BOOM_TIME
	if f < 0.7:
		fireball.global_position = C4_POS + Vector3(0, 0, 0.15)
		fireball.scale = Vector3.ONE * lerpf(0.15, 1.05, smoothstep(0.0, 0.18, f)) * (1.0 - smoothstep(0.35, 0.7, f))
		fireball.show()
	for k in smoke.size():
		var life := clampf((a - 0.08 * k) / 2.4, 0, 1)
		if life <= 0.0 or life >= 1.0: continue
		var p: MeshInstance3D = smoke[k]
		var ang := TAU * k / smoke.size()
		p.global_position = C4_POS + Vector3(cos(ang) * 0.5 * life, 0.2 + 1.3 * life, 0.35 + sin(ang) * 0.3 * life)
		p.scale = Vector3.ONE * lerpf(0.25, 0.8, life) * (1.0 - life * 0.6)
		p.show()

func _door_blown(a: float) -> void:
	if not is_instance_valid(door): return
	scorch.show()
	if a > 1.4:
		door_panel.hide(); return
	door_panel.show()
	door_panel.position = Vector3(0.4 * a, 2.2 * a - 5.5 * a * a, 1.6 * a)
	door_panel.rotation = Vector3(-3.5 * a, 0.8 * a, 1.6 * a)

# ---------------------------------------------------------------- ninjas
func _ninja_spot(i: int) -> Vector3:
	return Vector3(-18.8 + i * 0.75, 1.74, -8.2 - i * 0.22)
func _update_ninja(i: int, time: float, t: float) -> void:
	var ninja: Node3D = ninjas[i]
	var fire := _fire_time(i)
	var fall_at := fire + FALL_DELAY
	hits[i] = 1 if t >= fire else 0
	fallen[i] = t >= fall_at
	if t >= fall_at + 3.0:
		ninja.visible = false; return
	ninja.visible = true
	var torso: Node3D = ninja_parts[i][0]
	var arms: Array = ninja_parts[i][1]; var legs: Array = ninja_parts[i][2]
	var reaction := sin(PI * (t - fire) / 0.5) if t >= fire and t - fire < 0.5 else 0.0
	var dest := _ninja_spot(i)
	var entry_f := clampf(time / (INTRO - 0.15), 0, 1)
	ninja.position = Vector3(-21.65 - i * 0.35, 1.74, -8.2).lerp(dest, smoothstep(0, 1, entry_f))
	ninja.rotation = Vector3(0, -PI / 2 if entry_f < 1 else PI / 2, 0)
	var ready := 1.0 if entry_f >= 1 else 0.0
	torso.rotation = Vector3(reaction * 0.5 - 0.15 * ready, 0, reaction * 0.2)
	ninja.position += Vector3(reaction * 0.14, -0.06 * ready, reaction * 0.05)
	for side in 2:
		var stride := sin(time * 16 + side * PI) * 0.6 if entry_f < 1 else 0.0
		legs[side].rotation = Vector3(stride + (0.25 if side == 0 else -0.2) * ready, 0, 0)
		arms[side].rotation = Vector3(-stride - reaction * 0.9 - (0.9 if side == 1 else 0.3) * ready, 0, (-1 if side == 0 else 1) * reaction * 0.5)
	if fallen[i]:
		var fall_age: float = t - fall_at
		var lip := clampf(fall_age / 0.7, 0, 1)
		ninja.position.z = lerpf(dest.z, -6.62, smoothstep(0, 1, lip))
		ninja.rotation.y = lerpf(PI / 2, 0, lip)
		torso.rotation.x = 0.3 + lip * 0.7
		for side in 2:
			arms[side].rotation.z = (-1 if side == 0 else 1) * (0.8 + lip * 0.7)
		if fall_age > 0.7:
			var fall := fall_age - 0.7
			ninja.position += Vector3(fall * 0.38, -1.8 * fall - 2.1 * fall * fall, fall * 0.85)
			ninja.rotation.x = -fall * 2.4; ninja.rotation.z = fall * (1.1 if i == 0 else -1.2)
