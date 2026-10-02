extends Node3D
# Double-jump air cushion. Visual only: not a platform,
# no physics. One soft fade per air jump, no flashing. Fixed-size pool, no leaks.
# Styles (Mike 2026-09-30): Tek "ring" (soft ring), Doge "puff" (dust puff),
# TurboFit "whoosh" (two rings sinking away). Neutral color for everyone.
const LIFE := {"ring": 0.36, "puff": 0.38, "whoosh": 0.38}
const FOLLOW := 0.07  # ride the feet for ~2 frames, then stay behind in the air
var clock := -1.0
var origin := Vector3.ZERO
var cur_style := "ring"
var rings: Array = []
var puffs: Array = []
var puff_dirs: Array = []

func _ready() -> void:
	top_level = true
	for i in 2:
		var m := MeshInstance3D.new(); var tor := TorusMesh.new()
		tor.inner_radius = 0.8; tor.outer_radius = 1.0; tor.rings = 32; tor.ring_segments = 6
		m.mesh = tor; m.material_override = _mat(); m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m); rings.append(m)
	for i in 10:
		var p := MeshInstance3D.new(); var s := SphereMesh.new()
		s.radius = 0.1; s.height = 0.2; s.radial_segments = 8; s.rings = 4
		p.mesh = s; p.material_override = _mat(); p.visible = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p); puffs.append(p)
		var a := TAU * i / 10.0
		puff_dirs.append(Vector3(cos(a), -0.2 + 0.1 * float(i % 2), sin(a) * 0.8))

func _mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.97, 1.0, 0.0)
	return m

func fire(at: Vector3, style: String) -> void:
	if not LIFE.has(style): return
	origin = at + Vector3(0, 0.2, 0); clock = 0.0; cur_style = style
	_hide_all()

func clear() -> void:
	clock = -1.0; _hide_all()

func _hide_all() -> void:
	for m in rings: m.visible = false
	for p in puffs: p.visible = false

func _process(delta: float) -> void:
	if clock < 0.0: return
	clock += delta
	if clock < FOLLOW and get_parent() is Node3D: origin = (get_parent() as Node3D).global_position + Vector3(0, 0.05, 0)
	var t: float = clock / LIFE[cur_style]
	if t >= 1.0: clear(); return
	var ease_out := 1.0 - pow(1.0 - t, 2.0)
	var fade := 1.0 - t * t
	match cur_style:
		"ring":
			var r := 0.2 + 0.65 * ease_out
			_ring(rings[0], origin, r, 1.0 * fade, 0.45)
			_ring(rings[1], origin + Vector3(0, 0.02, 0), r * 0.94, 0.6 * fade, 0.45)
		"puff":
			for i in puffs.size():
				var p: MeshInstance3D = puffs[i]
				p.visible = true
				p.global_position = origin + puff_dirs[i] * (0.15 + 0.7 * ease_out)
				p.scale = Vector3.ONE * (1.0 + 0.8 * ease_out)
				p.material_override.albedo_color = Color(0.92, 0.95, 1.0, 0.6 * fade)
		"whoosh":
			_ring(rings[0], origin + Vector3(0, -0.25 * ease_out, 0), 0.25 + 0.55 * ease_out, 0.85 * fade)
			var t2 := clampf((clock - 0.06) / LIFE[cur_style], 0.0, 1.0)
			var e2 := 1.0 - pow(1.0 - t2, 2.0)
			if t2 > 0.0:
				_ring(rings[1], origin + Vector3(0, -0.2 - 0.5 * e2, 0), 0.18 + 0.4 * e2, 0.75 * (1.0 - t2))

func _ring(m: MeshInstance3D, at: Vector3, r: float, alpha: float, flat := 0.3) -> void:
	m.visible = alpha > 0.01
	m.global_transform = Transform3D(Basis().scaled(Vector3(r, flat * r, r * 0.55)), at)
	m.material_override.albedo_color.a = alpha
