extends "res://scripts/fighter.gd"
# Heavy Bag mini-game target: a stationary, hanging layered bag that scores hits.
# It uses the ordinary fighter hurt path (so every move in the game can hit it) but
# never takes damage, knockback or stocks, and never attacks.
signal bag_hit(points: int, layer: int, impact: float)
signal shell_broken(index: int)        # 0..3 = shells, 4 = core shattered

# Breakable layers: every hit wears down the current outer layer by its impact.
const SHELL_HP := [70.0, 90.0, 110.0, 130.0, 160.0]
const SHELL_RADIUS := [0.42, 0.37, 0.32, 0.27, 0.22]
const SHELL_COLORS := [Color("8f1d1d"), Color("b08a55"), Color("3a3f47"), Color("8c96a3"), Color(0.3, 1.0, 1.0)]
var shell_index := 0
var shell_hp := 70.0
var body: MeshInstance3D
var body_mesh: CylinderMesh
var body_mat: StandardMaterial3D
var shards: Array[MeshInstance3D] = []
var shard_vel: Array[Vector3] = []
var shard_spin: Array[Vector3] = []
var shard_time := 0.0
var shattered := false
var scoring := false   # set by the round; hits outside live play don't count

const LAYERS := 5                      # 0 outer shell .. 3 inner shells, 4 = core
const LAYER_COLORS := [Color(1.0, 0.95, 0.85), Color(1.0, 0.85, 0.3), Color(1.0, 0.55, 0.15), Color(1.0, 0.2, 0.15), Color(0.3, 1.0, 1.0)]
const LAYER_POINTS := [10, 25, 50, 100, 250]
# Impact thresholds (damage x launch power) per layer, from tools/calibrate_heavy_bag.gd:
# jabs ~5-18 (outer), most basics ~23-35, strong basics/specials ~45-53, Tek's laser 110 (core).
var layer_thresholds := [0.0, 20.0, 33.0, 50.0, 90.0]
var bag: Node3D
var shells: Array[MeshInstance3D] = []
var meter: MeshInstance3D
var meter_fill := 0.0
var swing := 0.0
var swing_speed := 0.0
var flash_layer := -1
var flash_time := 0.0

func is_heavy_bag() -> bool: return true

func _ready() -> void:
	character_id = "heavy_bag"
	fighter_name = "Heavy Bag"
	super._ready()

func _build_visuals() -> void:
	super._build_visuals()
	for child in _visual_root.get_children():
		_visual_root.remove_child(child)
		child.queue_free()
	get_node("PlayerLabel").visible = false
	bag = Node3D.new(); bag.name = "Bag"; bag.position.y = 2.6   # swing pivot at the chain top
	_visual_root.add_child(bag)
	var leather := StandardMaterial3D.new(); leather.albedo_color = Color("8f1d1d"); leather.roughness = 0.7
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color("1c1c1f"); dark.roughness = 0.6
	body = MeshInstance3D.new(); body_mesh = CylinderMesh.new()
	body_mesh.height = 1.5; body_mesh.radial_segments = 16; body_mesh.rings = 1
	body_mat = leather
	body.mesh = body_mesh; body.material_override = body_mat; body.position.y = -1.6; bag.add_child(body)
	# Shard pool for layer breaks (8 small chunks, reused).
	var shard_mesh := BoxMesh.new(); shard_mesh.size = Vector3(0.22, 0.3, 0.08)
	for i in 10:
		var shard := MeshInstance3D.new(); shard.mesh = shard_mesh
		shard.material_override = StandardMaterial3D.new(); shard.visible = false
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual_root.add_child(shard); shards.append(shard); shard_vel.append(Vector3.ZERO); shard_spin.append(Vector3.ZERO)
	_apply_shell()
	for y in [-0.9, -2.3]:   # top/bottom caps
		var cap := MeshInstance3D.new(); var c := CylinderMesh.new()
		c.top_radius = 0.44; c.bottom_radius = 0.44; c.height = 0.08; c.radial_segments = 16; c.rings = 1
		cap.mesh = c; cap.material_override = dark; cap.position.y = y + (0.04 if y > -1.6 else -0.04); bag.add_child(cap)
	var chain := MeshInstance3D.new(); var line := CylinderMesh.new()
	line.top_radius = 0.02; line.bottom_radius = 0.02; line.height = 4.0; line.radial_segments = 6; line.rings = 1
	chain.mesh = line; chain.material_override = dark; chain.position.y = 1.15; bag.add_child(chain)
	# Layer rings: flash on the bag front to show how deep a hit went (outer -> core).
	for i in LAYERS:
		var ring := MeshInstance3D.new(); var torus := TorusMesh.new()
		var r := 0.43 - i * 0.075
		torus.inner_radius = maxf(r - 0.03, 0.01); torus.outer_radius = r; torus.rings = 16; torus.ring_segments = 4
		ring.mesh = torus
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = LAYER_COLORS[i]; m.no_depth_test = true
		ring.material_override = m
		ring.rotation.x = PI / 2.0   # face the camera (+Z)
		ring.position = Vector3(0, -1.6, 0.45)
		ring.visible = false
		bag.add_child(ring); shells.append(ring)
	# Score meter: a glowing strip up the bag front that fills as the score grows.
	meter = MeshInstance3D.new(); var strip := BoxMesh.new(); strip.size = Vector3(0.08, 1.0, 0.02)
	meter.mesh = strip
	var mm := StandardMaterial3D.new(); mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mm.albedo_color = Color(0.35, 1.0, 0.9)
	meter.material_override = mm
	meter.position = Vector3(0.3, -2.3, 0.43); meter.scale.y = 0.001
	bag.add_child(meter)
	_apply_shell()

func read_controls(_delta: float) -> Dictionary:
	return {"left": false, "right": false, "up": false, "down": false, "jump": false, "attack": false, "special": false, "shield": false}
func can_hit(_target: Node) -> bool: return false
func try_jump() -> bool: return false
func basic_attack(_aim: Vector2, _airborne: bool) -> void: pass
func start_special(_aim: Vector2) -> void: pass
func release_special() -> void: pass
func lose_stock() -> void: pass
func apply_status_damage(_amount: float) -> void: pass
func apply_burn(_caster: Node3D) -> bool: return false

func impact_of(amount: float, base_knockback: float) -> float:
	return maxf(amount, 0.0) * (1.0 + maxf(base_knockback, 0.0) * 0.5)
func layer_for(impact: float) -> int:
	var layer := 0
	for i in LAYERS:
		if impact >= layer_thresholds[i]: layer = i
	return layer

func receive_hit(amount: float, direction: Vector3, base_knockback: float) -> void:
	var source = hit_source
	hit_source = null
	collateral_hit = false
	if not controls_enabled or not scoring or amount <= 0: return
	var impact := impact_of(amount, base_knockback)
	var layer := layer_for(impact)
	# Swing away from the hit; stronger hits swing further.
	swing_speed += signf(direction.x if absf(direction.x) > 0.01 else 1.0) * (0.8 + layer * 0.55)
	flash_layer = layer; flash_time = 0.22 + layer * 0.05
	if layer == LAYERS - 1 and is_instance_valid(source) and source.has_method("begin_counter_hitstop"):
		source.begin_counter_hitstop(0.08)   # core hit: short freeze for weight
	bag_hit.emit(int(LAYER_POINTS[layer]), layer, impact)
	if shattered: return
	shell_hp -= impact
	if shell_hp <= 0.0:
		_break_shell(signf(direction.x if absf(direction.x) > 0.01 else 1.0))
	else:
		_apply_shell()

func _break_shell(side: float) -> void:
	var broken := shell_index
	_burst(SHELL_COLORS[broken], side, broken == LAYERS - 1)
	if broken == LAYERS - 1:
		shattered = true
		bag.visible = false
	else:
		shell_index += 1
		shell_hp = SHELL_HP[shell_index]
		_apply_shell()
	shell_broken.emit(broken)

func _apply_shell() -> void:
	# Current layer's size and colour; it darkens as it takes damage (cracking).
	var r: float = SHELL_RADIUS[shell_index]
	body_mesh.top_radius = r; body_mesh.bottom_radius = r
	var wear := 1.0 - clampf(shell_hp / SHELL_HP[shell_index], 0.0, 1.0)
	body_mat.albedo_color = SHELL_COLORS[shell_index].lerp(Color.BLACK, wear * 0.45)
	var is_core := shell_index == LAYERS - 1
	body_mat.emission_enabled = is_core
	if is_core:
		body_mat.emission = Color(0.2, 0.9, 1.0); body_mat.emission_energy_multiplier = 1.5 + wear * 3.0
	for ring in shells:
		ring.position.z = r + 0.03; ring.scale = Vector3.ONE * (r / 0.42)
	if meter: meter.position = Vector3(r * 0.7, meter.position.y, r + 0.01)

func _burst(color: Color, side: float, big: bool) -> void:
	var center := bag.global_position + Vector3(0, -1.6, 0)
	for i in shards.size():
		var shard := shards[i]
		shard.visible = true
		(shard.material_override as StandardMaterial3D).albedo_color = color
		shard.global_position = center + Vector3(randf_range(-0.35, 0.35), randf_range(-0.6, 0.6), 0.6)   # in front of the bag
		shard.scale = Vector3.ONE * (1.6 if big else 1.0)
		shard_vel[i] = Vector3(side * randf_range(2.5, 6.0) + randf_range(-1.5, 1.5), randf_range(2.5, 6.0), randf_range(0.2, 1.5)) * (1.4 if big else 1.0)
		shard_spin[i] = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	shard_time = 1.1
	flash_layer = LAYERS - 1; flash_time = 0.35   # all rings flash on a break

func receive_contact_hit(amount: float, direction: Vector3, push: float, _point: Vector3, _region := "") -> void:
	receive_hit(amount, direction, push)

func set_meter(fraction: float) -> void:
	meter_fill = clampf(fraction, 0.0, 1.0)

func _physics_process(delta: float) -> void:
	velocity = Vector3.ZERO
	damage_percent = 0.0
	hitstun = 0.0
	if tumble: tumble.clear()
	super._physics_process(delta)
	global_position.x = spawn_position.x
	global_position.z = 0
	velocity.x = 0

func _process(delta: float) -> void:
	if not bag: return
	# Damped pendulum (visual only; the hurtbox never moves).
	swing_speed += -swing * 18.0 * delta - swing_speed * 3.2 * delta
	swing = clampf(swing + swing_speed * delta, -0.55, 0.55)
	bag.rotation.z = -swing
	flash_time = maxf(0.0, flash_time - delta)
	for i in shells.size():
		shells[i].visible = flash_time > 0.0 and i <= flash_layer
	if shard_time > 0.0:
		shard_time -= delta
		for i in shards.size():
			shard_vel[i].y -= 14.0 * delta
			shards[i].global_position += shard_vel[i] * delta
			shards[i].rotation += shard_spin[i] * delta
			shards[i].visible = shard_time > 0.0
	meter.scale.y = lerpf(meter.scale.y, maxf(meter_fill * 1.4, 0.001), minf(1.0, delta * 8.0))
	meter.position.y = -2.3 + meter.scale.y * 0.5

func _handle_blast_zone() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO

func reset_fighter(new_spawn: Vector3, reset_stocks := false) -> void:
	super.reset_fighter(new_spawn, reset_stocks)
	swing = 0.0; swing_speed = 0.0; flash_time = 0.0; meter_fill = 0.0
	shell_index = 0; shell_hp = SHELL_HP[0]; shattered = false; shard_time = 0.0
	if meter: meter.scale.y = 0.001
	if bag:
		bag.visible = true
		_apply_shell()
		for shard in shards: shard.visible = false

func _update_move_visuals(delta := 0.0, interrupted := false) -> void:
	super._update_move_visuals(delta, interrupted)
	if _visual_root: _visual_root.scale = Vector3.ONE
