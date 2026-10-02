extends Node3D
## Hermes Weaver stage (replaces Sky, Mike 2026-09-30: "add it and replace the sky level").
## Ported from the Hermes Weaver greybox trial. Collision authority:
##  - MainPlatform = the arena's existing solid body (stage_layouts "weaver"), so ledge grab works on it.
##  - Two elliptical one-way movers are AnimatableBody3D in pass_through_platforms, owned here.
## Hermes god, threads and smoke are presentation only.
var arena: Node3D
var movers: Array = []            # [{body, index}]
var clock := 0.0
var god: Node3D
var gold_mat: StandardMaterial3D
var environment: Environment
var saved_env := {}
var main_mesh: MeshInstance3D
var main_trim: Array = []

const MAIN_HALF := 7.0            # main platform x in [-7, 7], top y = 0
const MOVERS := [
	{"name":"Mover_L_Marble", "dir":-1, "cx":10.0, "cy":0.6, "rx":1.5, "ry":3.0, "period":31.0, "w":3.0, "spin":1,
	 "style":"glide", "color":"e8dcc2", "trim":"d4a640"},
	{"name":"Mover_R_Crystal", "dir":1, "cx":10.0, "cy":0.6, "rx":1.5, "ry":3.0, "period":22.0, "w":3.0, "spin":-1,
	 "style":"breathe", "color":"9fd4ff", "trim":"f4fbff", "hold":1.4, "phase":0.37},
]
const BELT_Y := -0.2
const God = preload("res://scripts/hermes_weaver_god.gd")

func _ready() -> void:
	name = "WeaverStage"
	arena = get_parent()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	environment = arena.find_children("*", "WorldEnvironment", false, false)[0].environment
	for key in ["background_mode", "background_color", "ambient_light_color", "ambient_light_energy", "glow_enabled", "glow_intensity", "glow_hdr_threshold", "glow_bloom"]:
		saved_env[key] = environment.get(key)
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0b1220")
	environment.ambient_light_color = Color("dbe6ed")
	environment.ambient_light_energy = 0.7
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_hdr_threshold = 1.0
	environment.glow_bloom = 0.05
	_dress_main()
	_build_movers()
	god = God.new()
	god.name = "HermesGod"
	add_child(god)
	if not god.setup(self, BELT_Y, -12.0):
		push_warning("Hermes Weaver: 3D Hermes failed to load")
		remove_child(god); god.queue_free(); god = null
	_build_smoke()
	_build_hud_backing()

func _dress_main() -> void:
	gold_mat = StandardMaterial3D.new(); gold_mat.albedo_color = Color(1.0,0.8,0.4); gold_mat.metallic = 0.5; gold_mat.roughness = 0.3
	gold_mat.emission_enabled = true; gold_mat.emission = Color(1.0,0.75,0.35); gold_mat.emission_energy_multiplier = 0.6
	# Base platform meshes are presentation-hidden in production; draw our own deck (collision stays on MainPlatform).
	var body: Node3D = arena.get_node("MainPlatform")
	main_mesh = MeshInstance3D.new(); main_mesh.name = "WeaverDeck"
	var bm := BoxMesh.new(); bm.size = Vector3(MAIN_HALF*2, 1.0, 4.0); main_mesh.mesh = bm
	main_mesh.material_override = God.marble_material(false)
	main_mesh.position = body.position
	add_child(main_mesh)
	for y in [0.46, -0.46]:
		main_trim.append(_box(main_mesh, Vector3(0, y, 2.02), Vector3(MAIN_HALF*2, 0.08, 0.05), gold_mat))

func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new(); var shape := BoxMesh.new(); shape.size = size; mesh.mesh = shape
	mesh.material_override = mat; mesh.position = pos; parent.add_child(mesh); return mesh

func _build_movers() -> void:
	for i in MOVERS.size():
		var d: Dictionary = MOVERS[i]
		var p0 := mover_point(i, 0.0)
		var size := Vector3(d.w, 0.3, 3)
		var b := AnimatableBody3D.new()
		b.name = d.name
		b.position = Vector3(p0.x, p0.y - 0.15, 0)
		b.collision_layer = 2; b.collision_mask = 0
		add_child(b)
		var slab := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; slab.mesh = bm; b.add_child(slab)
		var c := CollisionShape3D.new(); var s := BoxShape3D.new(); s.size = size; c.shape = s; b.add_child(c)
		b.add_to_group("pass_through_platforms")
		b.set_meta("top_y", p0.y); b.set_meta("half_width", size.x/2); b.set_meta("thickness", size.y)
		var trim_mat := StandardMaterial3D.new(); trim_mat.albedo_color = Color(d.trim)
		var trim_box := _box(b, Vector3(0,-0.2,0), Vector3(d.w*0.8,0.12,2.6), trim_mat)
		if d.style == "glide":
			slab.material_override = God.marble_material(false)
			trim_box.material_override = gold_mat
		else:
			slab.material_override = _crystal_material()
		movers.append({"body": b, "index": i})
	_update_movers()

func _crystal_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62,0.86,1.0,0.78); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.25; m.roughness = 0.06; m.rim_enabled = true; m.rim = 0.7; m.rim_tint = 0.2
	m.clearcoat_enabled = true; m.clearcoat = 0.8
	m.emission_enabled = true; m.emission = Color(0.45,0.75,1.0); m.emission_energy_multiplier = 0.35
	return m

func mover_u(i: int, t: float) -> float:
	var d: Dictionary = MOVERS[i]
	var P: float = d.period
	var x := fposmod(t/P + float(d.get("phase", 0.0)), 1.0)
	if d.style == "breathe":
		var h: float = float(d.get("hold", 0.0)) / P
		if x < h: return 0.0
		return smoothstep(0.0, 1.0, (x-h)/(1.0-h))
	return x

func mover_point(i: int, t: float) -> Vector2:
	var d: Dictionary = MOVERS[i]
	var spin: float = float(d.get("spin", 1))
	var th: float = PI*0.5 - spin*TAU*mover_u(i, t)
	var outx: float = d.cx + d.rx*cos(th)
	return Vector2(outx*d.dir, d.cy + d.ry*sin(th))

func _update_movers() -> void:
	for m in movers:
		var p := mover_point(m.index, clock)
		var b: AnimatableBody3D = m.body
		b.position = Vector3(p.x, p.y-0.15, 0)
		b.set_meta("top_y", p.y)

func _build_smoke() -> void:
	var grad := Gradient.new(); grad.set_color(0, Color(1,1,1,1)); grad.set_color(1, Color(1,1,1,0))
	var gtex := GradientTexture2D.new(); gtex.gradient = grad; gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5,0.5); gtex.fill_to = Vector2(1.0,0.5); gtex.width = 128; gtex.height = 128
	for spec in [[-8.0, -1.2, 110, Vector3(15,1.2,1.5), 3.2], [-2.5, -2.4, 80, Vector3(16,1.4,1.0), 3.8]]:
		var ps := CPUParticles3D.new(); ps.name = "Smoke"
		ps.position = Vector3(0, spec[1], spec[0]); ps.amount = spec[2]; ps.lifetime = 9.0
		ps.preprocess = 9.0; ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX; ps.emission_box_extents = spec[3]
		ps.direction = Vector3(0.15,1,0); ps.spread = 25; ps.gravity = Vector3(0,0.02,0)
		ps.initial_velocity_min = 0.08; ps.initial_velocity_max = 0.25
		ps.scale_amount_min = spec[4]*0.7; ps.scale_amount_max = spec[4]*1.3
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
		ramp.colors = PackedColorArray([Color(0.62,0.84,1.0,0.0), Color(0.62,0.84,1.0,0.42), Color(0.95,0.98,1.0,0.32), Color(1,1,1,0.0)])
		ps.color_ramp = ramp
		var quad := QuadMesh.new(); quad.size = Vector2(1,1)
		var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true; mat.albedo_texture = gtex; mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		quad.material = mat; ps.mesh = quad
		add_child(ps)

func _build_hud_backing() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 0
	add_child(hud_layer)
	for rect in [Rect2(0,0,1280,65), Rect2(0,595,1280,125)]:
		var backing := ColorRect.new()
		backing.name = "HUDContrast"
		backing.position = rect.position
		backing.size = rect.size
		backing.color = Color(0.015,0.025,0.045,0.88)
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(backing)

func _physics_process(delta: float) -> void:
	clock += delta
	_update_movers()
	if god:
		god.animate(clock)
		god.update_threads()

func _exit_tree() -> void:
	# Leave no stale one-way exceptions pointing at freed movers, and restore the shared deck/env.
	for f in arena.get("fighters") if arena.get("fighters") != null else []:
		if not is_instance_valid(f): continue
		for m in movers:
			if f._ignored_platforms.has(m.body):
				f.remove_collision_exception_with(m.body)
				f._ignored_platforms.erase(m.body)
			if f.get("_drop_platform") == m.body: f._drop_platform = null
	if environment:
		for key in saved_env: environment.set(key, saved_env[key])
