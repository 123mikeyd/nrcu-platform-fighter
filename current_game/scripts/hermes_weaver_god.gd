extends Node3D
## Hermes the Weaver: 3D backdrop god, arm motion synced to the movers, glowing threads, below-belt dissolve.
## Owned by weaver_stage.gd (ported from Hermes_Weaver_Greybox). Purely visual: no collision, no gameplay authority.
var trial                      # trial.gd (for movers / clock / MOVERS)
var model: Node3D
var sk: Skeleton3D
var body_mi: MeshInstance3D
var threads: Array = []        # [{mesh, a_bone, target:Callable, sag, kind}]
var bone_cache := {}
var rest_rot := {}
var z_axis_parent := {}        # bone -> rotation axis (parent space) equivalent to world Z (screen plane spin)
const SCALE := 10.0
const MODEL_BELT := 0.95       # model-space belt height (m)
var belt_y := -0.2
var loaded := false

# arm -> job.  Character .R arms are on screen-LEFT (-X); .L on screen-RIGHT (+X).
const ARMS := {
	"mid_R": {"upper":"upper_arm.R", "fore":"forearm.R", "palm":["f_middle.01.R","hand.R"], "side":-1, "job":"mover", "mover":0},
	"mid_L": {"upper":"upper_arm.L", "fore":"forearm.L", "palm":["f_middle.01.L","hand.L"], "side":1, "job":"mover", "mover":1},
	"top_R": {"upper":"top_upper_arm.R", "fore":"top_forearm.R", "palm":["top_f_middle.01.R","top_hand.R"], "side":-1, "job":"main"},
	"top_L": {"upper":"top_upper_arm.L", "fore":"top_forearm.L", "palm":["top_f_middle.01.L","top_hand.L"], "side":1, "job":"main"},
	"low_R": {"upper":"low_upper_arm.R", "fore":"low_forearm.R", "palm":["low_f_middle.01.R","low_hand.R"], "side":-1, "job":"abyss"},
	"low_L": {"upper":"low_upper_arm.L", "fore":"low_forearm.L", "palm":["low_f_middle.01.L","low_hand.L"], "side":1, "job":"abyss"},
}

func setup(owner_trial, belt: float, z: float) -> bool:
	trial = owner_trial; belt_y = belt
	var ps: PackedScene = load("res://assets/stages/hermes_weaver/hermes_weaver.glb")
	if ps == null: return false
	model = ps.instantiate(); add_child(model)
	model.scale = Vector3.ONE*SCALE
	model.position = Vector3(0, belt_y - MODEL_BELT*SCALE, z)
	var sks = model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty(): return false
	sk = sks[0]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin != null: body_mi = mi
		else: _gild_mask(mi)
	if body_mi:
		body_mi.material_override = marble_material(true, belt_y)
		body_mi.material_override.set_shader_parameter("scale", 0.45)
	for k in ARMS:
		var a = ARMS[k]
		for role in ["upper","fore"]:
			var bn: String = a[role]; var i := sk.find_bone(bn)
			if i < 0: push_warning("missing bone " + bn); continue
			bone_cache[bn] = i
			rest_rot[bn] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
			var parent := sk.get_bone_parent(i)
			var pb: Basis = sk.get_bone_global_rest(parent).basis if parent >= 0 else Basis()
			z_axis_parent[bn] = (pb.inverse() * Vector3(0,0,1)).normalized()
		for pn in a.palm:
			if sk.find_bone(pn) >= 0: bone_cache[k+"_palm"] = sk.find_bone(pn); break
	_build_threads()
	loaded = true
	return true

func _gild_mask(mi: MeshInstance3D):
	var src = mi.get_active_material(0)
	if src is StandardMaterial3D:
		var m: StandardMaterial3D = src.duplicate()
		m.metallic = 0.45; m.roughness = 0.3; m.metallic_specular = 0.9
		m.albedo_color = Color(1.1, 0.95, 0.7)
		m.emission_enabled = true; m.emission = Color(1.0, 0.78, 0.38); m.emission_energy_multiplier = 0.42
		if m.albedo_texture: m.emission_texture = m.albedo_texture
		mi.material_override = m

static func marble_material(dissolve_below_belt := false, belt := -0.2, tint := Color(0.93,0.91,0.86)) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode depth_draw_opaque;
uniform vec3 tint : source_color = vec3(0.93,0.91,0.86);
uniform vec3 vein : source_color = vec3(0.32,0.33,0.36);
uniform float scale = 0.9;
uniform bool dissolve = false;
uniform float belt_y = -0.2;
varying vec3 wpos;
float h(vec3 p){ return fract(sin(dot(p, vec3(127.1,311.7,74.7)))*43758.5453); }
float n3(vec3 p){ vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(h(i),h(i+vec3(1,0,0)),f.x),mix(h(i+vec3(0,1,0)),h(i+vec3(1,1,0)),f.x),f.y),
	           mix(mix(h(i+vec3(0,0,1)),h(i+vec3(1,0,1)),f.x),mix(h(i+vec3(0,1,1)),h(i+vec3(1,1,1)),f.x),f.y),f.z); }
float fbm(vec3 p){ float a=0.5, s=0.0; for(int k=0;k<5;k++){ s+=a*n3(p); p*=2.03; a*=0.5; } return s; }
void vertex(){ wpos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
	vec3 p = wpos*scale;
	float f = fbm(p);
	float cloud = fbm(p*0.45 + 3.1);
	float v = abs(sin((p.x*0.7 + p.y*1.3 + p.z*0.4) + f*7.0));
	float v2 = abs(sin((p.x*-1.1 + p.y*0.6 + p.z*0.9)*1.7 + fbm(p*1.9+7.0)*5.0));
	float veins = 1.0 - smoothstep(0.0, 0.16, v);
	float soft = (1.0 - smoothstep(0.0, 0.35, v2))*0.45;
	vec3 base = tint*(0.80 + 0.2*cloud);
	vec3 col = mix(base, vein, clamp(veins*0.85 + soft*0.6, 0.0, 1.0));
	ALBEDO = col; ROUGHNESS = 0.32 + 0.25*veins; SPECULAR = 0.6;
	if (dissolve) {
		// Smoky dithered dissolve: fully gone a little below the belt, solid a little above.
		float edge = smoothstep(belt_y - 1.1, belt_y + 0.35, wpos.y + (fbm(wpos*1.7)-0.5)*0.9);
		if (edge < h(floor(FRAGCOORD.xyz*0.5))) discard;
	}
}"""
	var m := ShaderMaterial.new(); m.shader = sh
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("dissolve", dissolve_below_belt)
	m.set_shader_parameter("belt_y", belt)
	return m

# ---------- threads ----------
func _thread_material(core: bool) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 col : source_color = vec3(1.0, 0.86, 0.55);
uniform float strength = 1.0;
uniform float flow_speed = 0.25;
void fragment(){
	float across = 1.0 - abs(UV.y*2.0 - 1.0);           // soft edges
	float pulse = 0.75 + 0.25*sin((UV.x*6.0 - TIME*flow_speed*6.2831));  // gentle energy flowing hand -> platform
	ALBEDO = col * strength * pulse * across;
	ALPHA = 1.0;
}"""
	var m := ShaderMaterial.new(); m.shader = sh
	if core: m.set_shader_parameter("col", Color(1.0, 0.93, 0.75)); m.set_shader_parameter("strength", 1.1)
	else: m.set_shader_parameter("col", Color(0.55, 0.8, 1.0)); m.set_shader_parameter("strength", 0.28)
	return m

func _add_thread(arm_key: String, target: Callable, sag: float, kind: String):
	var mi := MeshInstance3D.new(); mi.mesh = ImmediateMesh.new(); mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Thread_%s_%d" % [arm_key, threads.size()]
	add_child(mi)
	threads.append({"mesh": mi, "arm": arm_key, "target": target, "sag": sag, "kind": kind,
		"core": _thread_material(true), "glow": _thread_material(false), "a": Vector3.ZERO, "b": Vector3.ZERO})

func _build_threads():
	for k in ARMS:
		var a = ARMS[k]
		match a.job:
			"mover":
				var idx: int = a.mover
				var w: float = trial.MOVERS[idx].w
				_add_thread(k, func(): return mover_anchor(idx, -0.42*w), 0.10, "mover")
				_add_thread(k, func(): return mover_anchor(idx, 0.42*w), 0.10, "mover")
			"main":
				var sx: float = a.side
				_add_thread(k, func(): return Vector3(sx*(trial.MAIN_HALF-0.6), 0.0, -0.4), 0.02, "main")
			"abyss":
				var sx2: float = a.side
				_add_thread(k, func(): return palm_world(k) + Vector3(sx2*2.2, -9.0, 3.0), 0.0, "abyss")

func mover_anchor(idx: int, dx: float) -> Vector3:
	var b: Node3D = trial.movers[idx].body
	return Vector3(b.position.x + dx, b.get_meta("top_y") - 0.05, 0.0)

func palm_world(arm_key: String) -> Vector3:
	var i: int = bone_cache.get(arm_key+"_palm", -1)
	if i < 0: return Vector3.ZERO
	return sk.global_transform * sk.get_bone_global_pose(i).origin

# ---------- arm motion ----------
func _rot(bn: String, angle: float):
	if not bone_cache.has(bn): return
	var axis: Vector3 = z_axis_parent[bn]
	var rest: Quaternion = rest_rot[bn]
	var q: Quaternion = Quaternion(axis, angle) * rest
	sk.set_bone_pose_rotation(bone_cache[bn], q)

func animate(clock: float):
	if not loaded: return
	for k in ARMS:
		var a = ARMS[k]; var side: float = a.side
		var up := 0.0; var out := 0.0
		match a.job:
			"mover":
				# Hand traces a small loop in lockstep with its platform's ellipse (same phase + direction).
				var d = trial.MOVERS[a.mover]
				var spin: float = float(d.get("spin", 1))
				var th: float = PI*0.5 - spin*TAU*trial.mover_u(a.mover, clock)
				up = sin(th); out = cos(th)
				_rot(a.upper, side*deg_to_rad(11.0)*up)
				_rot(a.fore, -side*deg_to_rad(13.0)*out)
			"main":
				# Holding the main platform steady: a slow, heavy breathing hold.
				var b := sin(clock*TAU/9.0)
				_rot(a.upper, side*deg_to_rad(2.5)*b)
				_rot(a.fore, side*deg_to_rad(3.0)*sin(clock*TAU/9.0 + 1.2))
			"abyss":
				# Hauling threads up out of the smoke: slow alternating pulls.
				var ph := clock*TAU/7.0 + (0.0 if side > 0 else PI)
				_rot(a.upper, -side*deg_to_rad(6.0)*sin(ph))
				_rot(a.fore, side*deg_to_rad(9.0)*sin(ph + 0.9))

func update_threads():
	if not loaded: return
	for t in threads:
		var a: Vector3 = palm_world(t.arm)
		var b: Vector3 = t.target.call()
		t.a = a; t.b = b
		var im: ImmediateMesh = t.mesh.mesh
		im.clear_surfaces()
		for layer in [["glow", 0.34], ["core", 0.075]]:
			_ribbon(im, a, b, t.sag, layer[1], t[layer[0]])

func _ribbon(im: ImmediateMesh, a: Vector3, b: Vector3, sag: float, width: float, mat: Material):
	var seg := 24
	var ctrl := (a+b)*0.5 + Vector3(0, -sag*a.distance_to(b), 0)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, mat)
	for s in seg+1:
		var u := float(s)/seg
		var p := (1.0-u)*(1.0-u)*a + 2.0*(1.0-u)*u*ctrl + u*u*b
		var tan := (2.0*(1.0-u)*(ctrl-a) + 2.0*u*(b-ctrl)).normalized()
		var nrm := Vector3(-tan.y, tan.x, 0.0).normalized()*width*0.5   # face the ortho camera (-Z view)
		im.surface_set_uv(Vector2(u, 0.0)); im.surface_add_vertex(p - nrm)
		im.surface_set_uv(Vector2(u, 1.0)); im.surface_add_vertex(p + nrm)
	im.surface_end()
