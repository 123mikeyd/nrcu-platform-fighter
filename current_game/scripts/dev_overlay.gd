extends Node3D
## Dev Mode overlay (training-mode style). Pure observer: reads fighter state,
## receiving shapes and raw keys; never edits moves, damage, timing or input.
## Hurtbox drawing calls the same pilot.sync() attacks already call before
## their contact queries, so the drawn shapes match what attacks test against.

const COL_HURT := Color(1.0, 0.25, 0.8, 0.95)
const COL_HURT_OFF := Color(1.0, 0.25, 0.8, 0.3)
const COL_FALLBACK := Color(0.2, 0.95, 1.0, 0.95)
const COL_MOVE := Color(0.85, 0.85, 0.85, 0.55)
const COL_PHASE := {"startup": Color(1.0, 0.9, 0.15), "active": Color(1.0, 0.15, 0.1), "recovery": Color(0.55, 0.6, 0.75)}
const COL_PROJ := Color(1.0, 0.55, 0.1)
const COL_HIT := Color(1.0, 1.0, 1.0)
const SEG := 20

var main: Node
var lines: MeshInstance3D
var mesh := ImmediateMesh.new()
var ui: CanvasLayer
var top_label: Label
var perf_label: Label
var log_label: Label
var input_labels: Array[Label] = []
var state_labels: Dictionary = {}   # fighter -> Label

var _prev := {}          # fighter -> {damage, health, hitstun}
var _press_frame := {}   # fighter -> frame of last attack/special press
var _held := {}          # fighter -> last raw control dictionary
var _history := {}       # fighter -> Array of {text, frames}
var hit_log: Array[String] = []
var markers: Array[Dictionary] = []  # {pos, text, frames_left}
var _anim_cache := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000  # observe after fighters have ticked
	lines = MeshInstance3D.new()
	lines.name = "DevLines"
	lines.mesh = mesh
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10
	lines.material_override = mat
	add_child(lines)
	ui = CanvasLayer.new()
	ui.layer = 5
	ui.name = "DevUI"
	add_child(ui)
	top_label = _label(Vector2(12, 58), 15, Color(0.6, 1.0, 0.7))
	perf_label = _label(Vector2(1010, 58), 14, Color(0.8, 0.9, 1.0))
	log_label = _label(Vector2(12, 470), 14, Color(1, 1, 1))
	for i in 2:
		var l := _label(Vector2(12 + i * 1150, 150), 15, Color(1, 0.95, 0.6))
		input_labels.append(l)
	DevMode.changed.connect(_refresh_visibility)
	_refresh_visibility()

func _label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(l)
	return l

func _refresh_visibility() -> void:
	visible = DevMode.enabled
	ui.visible = DevMode.enabled
	if not DevMode.enabled:
		mesh.clear_surfaces()
		hit_log.clear()
		markers.clear()

func fighters() -> Array:
	return main.fighters.filter(func(f): return is_instance_valid(f) and f.visible) if main else []

# ---- input ------------------------------------------------------------------
func _unhandled_key_input(event: InputEvent) -> void:
	if not DevMode.enabled or not (event is InputEventKey) or not event.pressed or event.echo: return
	if not main or main.setup.visible or DevMode.menu_paused: return
	match event.keycode:
		KEY_F2: DevMode.toggle_freeze()
		KEY_F3: DevMode.step_frame()
		KEY_F5: DevMode.cycle_speed()
		_: return
	get_viewport().set_input_as_handled()

func raw_controls(f) -> Dictionary:
	var r := {"left": false, "right": false, "up": false, "down": false, "jump": false, "attack": false, "special": false}
	if f.control_type != "human": return r
	if f.input_device >= 0:
		var x := Input.get_joy_axis(f.input_device, JOY_AXIS_LEFT_X)
		var y := Input.get_joy_axis(f.input_device, JOY_AXIS_LEFT_Y)
		r.left = x < -0.35 or Input.is_joy_button_pressed(f.input_device, JOY_BUTTON_DPAD_LEFT)
		r.right = x > 0.35 or Input.is_joy_button_pressed(f.input_device, JOY_BUTTON_DPAD_RIGHT)
		r.up = y < -0.35 or Input.is_joy_button_pressed(f.input_device, JOY_BUTTON_DPAD_UP)
		r.down = y > 0.35 or Input.is_joy_button_pressed(f.input_device, JOY_BUTTON_DPAD_DOWN)
		r.jump = Input.is_joy_button_pressed(f.input_device, JOY_BUTTON_A)
		r.attack = Input.is_joy_button_pressed(f.input_device, JOY_BUTTON_X)
		r.special = Input.is_joy_button_pressed(f.input_device, JOY_BUTTON_B)
	elif f.player_index in [1, 2]:
		var keys := [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE, KEY_F, KEY_G] if f.player_index == 1 else [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_K, KEY_L]
		var names := ["left", "right", "up", "down", "jump", "attack", "special"]
		for i in keys.size(): r[names[i]] = Input.is_key_pressed(keys[i])
	return r

static func input_text(r: Dictionary) -> String:
	var h := (1 if r.right else 0) - (1 if r.left else 0)
	var v := (1 if r.up else 0) - (1 if r.down else 0)
	var arrows := {Vector2i(0,0): "•", Vector2i(1,0): "→", Vector2i(-1,0): "←", Vector2i(0,1): "↑", Vector2i(0,-1): "↓", Vector2i(1,1): "↗", Vector2i(-1,1): "↖", Vector2i(1,-1): "↘", Vector2i(-1,-1): "↙"}
	var s: String = arrows[Vector2i(h, v)]
	if r.jump: s += " JUMP"
	if r.attack: s += " BASIC"
	if r.special: s += " SPECIAL"
	return s

# ---- per-tick observation (pauses with the game) ------------------------------
func _physics_process(_delta: float) -> void:
	if not DevMode.enabled or get_tree().paused: return
	for f in fighters():
		_track_inputs(f)
	for f in fighters():
		_track_hits(f)
	for m in markers: m.frames_left -= 1
	markers = markers.filter(func(m): return m.frames_left > 0)

func _track_inputs(f) -> void:
	var r := raw_controls(f)
	var old: Dictionary = _held.get(f, {})
	if (r.attack and not old.get("attack", false)) or (r.special and not old.get("special", false)):
		_press_frame[f] = DevMode.frame
	_held[f] = r
	var hist: Array = _history.get(f, [])
	var text := input_text(r)
	if hist.is_empty() or hist[0].text != text:
		hist.push_front({"text": text, "frames": 1})
		if hist.size() > 14: hist.pop_back()
	else:
		hist[0].frames += 1
	_history[f] = hist

func _track_hits(f) -> void:
	var dmg := float(f.damage_percent)
	var hp := float(f.get("health")) if f.get("health") != null else 0.0
	var stun := float(f.hitstun)
	var p: Dictionary = _prev.get(f, {"damage": dmg, "health": hp, "hitstun": stun})
	var dealt := maxf(dmg - p.damage, p.health - hp)
	if dealt > 0.001:
		var attacker = _resolve_fighter(f.get("last_damage_source") if f.get("last_damage_source") != null else f.get("hit_source"))
		var who := ("P%d %s" % [attacker.player_index, attacker.fighter_name]) if attacker else "?"
		var startup := ""
		if attacker and _press_frame.has(attacker):
			var gap: int = DevMode.frame - int(_press_frame[attacker])
			if gap <= 90: startup = "  press→hit %df" % gap
		var line := "f%d  %s → P%d %s  %.1f%%  hitstun %df  launch %.1f%s" % [DevMode.frame, who, f.player_index, f.fighter_name, dealt, roundi(stun * 60.0), f.velocity.length(), startup]
		hit_log.push_front(line)
		if hit_log.size() > 7: hit_log.pop_back()
		markers.append({"pos": _hurt_center(f), "frames_left": 45, "text": "%.0f" % dealt})
	_prev[f] = {"damage": dmg, "health": hp, "hitstun": stun}

func _resolve_fighter(node):
	var n = node
	for i in 4:
		if n == null or not is_instance_valid(n): return null
		if n in main.fighters: return n
		n = n.get("source") if n.get("source") != null else n.get_parent()
	return null

func _hurt_center(f) -> Vector3:
	var pilot = f.get_node_or_null("BodyHurtboxes")
	if pilot and not pilot.shapes.is_empty():
		var c := Vector3.ZERO
		for s in pilot.shapes: c += s.global_position
		return c / pilot.shapes.size()
	return f.global_position + Vector3.UP

# ---- drawing (runs while frozen) ---------------------------------------------
func _process(_delta: float) -> void:
	if not DevMode.enabled or not main: return
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var any := false
	var fs := fighters()
	for f in fs:
		if DevMode.is_on("movement"):
			for c in f.get_children():
				if c is CollisionShape3D and not c.disabled: any = _shape(c.shape, c.global_transform, COL_MOVE) or any
		if DevMode.is_on("hurtboxes"):
			var pilot = f.get_node_or_null("BodyHurtboxes")
			if pilot and pilot.has_method("sync"):
				pilot.sync()
				var live: bool = pilot.get("body") == null or pilot.body.collision_layer != 0
				for s in pilot.shapes: any = _shape(s.shape, s.global_transform, COL_HURT if live else COL_HURT_OFF) or any
			else:
				for c in f.get_children():
					if c is CollisionShape3D and not c.disabled: any = _shape(c.shape, c.global_transform, COL_FALLBACK) or any
	if DevMode.is_on("hitboxes"):
		for h in DevMode.hitboxes:
			var col: Color = COL_PHASE.get(h.phase, COL_PHASE.active)
			any = _capsule_ab(h.a, h.b, h.radius, col) or any
	if DevMode.is_on("projectiles"):
		for p in get_tree().get_nodes_in_group("projectiles"):
			if p is Node3D and p.is_inside_tree():
				_cross(p.global_position, 0.3, COL_PROJ); any = true
	if DevMode.is_on("hits"):
		for m in markers:
			var k: float = m.frames_left / 45.0
			_circle(m.pos, 0.35 + (1.0 - k) * 0.25, Vector3.RIGHT, Vector3.UP, Color(COL_HIT, k)); any = true
	if not any:  # ImmediateMesh surfaces cannot be empty
		mesh.surface_add_vertex(Vector3.ZERO); mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_end()
	_update_text(fs)

func _v(p: Vector3, c: Color) -> void:
	mesh.surface_set_color(c)
	mesh.surface_add_vertex(p)

func _seg(a: Vector3, b: Vector3, c: Color) -> void:
	_v(a, c); _v(b, c)

func _circle(center: Vector3, r: float, u: Vector3, w: Vector3, c: Color, from := 0.0, to := TAU) -> void:
	for i in SEG:
		var t0 := lerpf(from, to, float(i) / SEG)
		var t1 := lerpf(from, to, float(i + 1) / SEG)
		_seg(center + (u * cos(t0) + w * sin(t0)) * r, center + (u * cos(t1) + w * sin(t1)) * r, c)

func _cross(p: Vector3, s: float, c: Color) -> void:
	_seg(p - Vector3.RIGHT * s, p + Vector3.RIGHT * s, c)
	_seg(p - Vector3.UP * s, p + Vector3.UP * s, c)
	_circle(p, s * 0.8, Vector3.RIGHT, Vector3.UP, c)

func _capsule_ab(a: Vector3, b: Vector3, r: float, c: Color) -> bool:
	var axis := b - a
	var up := axis.normalized() if axis.length_squared() > 1e-8 else Vector3.UP
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 1e-6: side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var depth := up.cross(side).normalized()
	# Side-view silhouette (the camera looks down -Z) plus depth rings.
	_circle(a, r, side, up, c, PI, TAU)
	_circle(b, r, side, up, c, 0.0, PI)
	_seg(a + side * r, b + side * r, c)
	_seg(a - side * r, b - side * r, c)
	_circle(a, r, side, depth, Color(c, c.a * 0.45))
	_circle(b, r, side, depth, Color(c, c.a * 0.45))
	return true

func _shape(shape: Shape3D, xf: Transform3D, c: Color) -> bool:
	var scale := maxf(xf.basis.x.length(), xf.basis.z.length())
	var up := xf.basis.y.normalized()
	if shape is CapsuleShape3D:
		var half := maxf(0.0, shape.height * 0.5 - shape.radius) * xf.basis.y.length()
		return _capsule_ab(xf.origin - up * half, xf.origin + up * half, shape.radius * scale, c)
	if shape is SphereShape3D:
		_circle(xf.origin, shape.radius * scale, Vector3.RIGHT, Vector3.UP, c)
		_circle(xf.origin, shape.radius * scale, Vector3.RIGHT, Vector3.BACK, Color(c, c.a * 0.45))
		return true
	if shape is CylinderShape3D:
		var h: float = shape.height * 0.5 * xf.basis.y.length()
		return _capsule_ab(xf.origin - up * h, xf.origin + up * h, shape.radius * scale, c)
	if shape is BoxShape3D:
		var e: Vector3 = shape.size * 0.5
		var pts := []
		for i in 8: pts.append(xf * Vector3(e.x * (1 if i & 1 else -1), e.y * (1 if i & 2 else -1), e.z * (1 if i & 4 else -1)))
		for pair in [[0,1],[2,3],[4,5],[6,7],[0,2],[1,3],[4,6],[5,7],[0,4],[1,5],[2,6],[3,7]]: _seg(pts[pair[0]], pts[pair[1]], c)
		return true
	return false

func _anim_player(f) -> AnimationPlayer:
	if _anim_cache.has(f) and is_instance_valid(_anim_cache[f]): return _anim_cache[f]
	var root = f.get("_visual_root")
	if root == null: return null
	var found := (root as Node).find_children("*", "AnimationPlayer", true, false)
	for p in found:
		if p.is_playing(): _anim_cache[f] = p; return p
	return found[0] if not found.is_empty() else null

func _update_text(fs: Array) -> void:
	top_label.text = "DEV MODE   frame %d   speed %s%s\nF2 freeze · F3 step 1 frame · F5 speed · Esc → Options to turn off" % [DevMode.frame, DevMode.speed_label(), "   ❚❚ FROZEN" if DevMode.frozen else ""]
	perf_label.visible = DevMode.is_on("perf")
	if perf_label.visible:
		perf_label.text = "FPS %d\nframe %.2f ms\nphysics %.2f ms\ndraw calls %d\nobjects %d\nnodes %d\nVRAM %.0f MB" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
	log_label.visible = DevMode.is_on("hits")
	log_label.text = "HIT LOG (measured)\n" + "\n".join(hit_log) if not hit_log.is_empty() else "HIT LOG (measured)\n—"
	var humans := fs.filter(func(f): return f.player_index in [1, 2])
	for i in 2:
		var l := input_labels[i]
		var f = humans[i] if i < humans.size() else null
		l.visible = DevMode.is_on("inputs") and f != null
		if not l.visible: continue
		var rows: Array[String] = ["P%d INPUTS" % f.player_index if f.control_type == "human" else "P%d BOT" % f.player_index]
		for h in _history.get(f, []): rows.append("%3d  %s" % [h.frames, h.text])
		l.text = "\n".join(rows)
		if i == 1: l.position.x = 1268 - 130
	var cam := get_viewport().get_camera_3d()
	for f in state_labels.keys():
		if not is_instance_valid(f) or f not in fs:
			state_labels[f].queue_free(); state_labels.erase(f)
	for f in fs:
		if not state_labels.has(f):
			state_labels[f] = _label(Vector2.ZERO, 13, f.body_color.lightened(0.35))
		var l: Label = state_labels[f]
		l.visible = DevMode.is_on("states") and cam != null and not cam.is_position_behind(f.global_position + Vector3.UP * 2.4)
		if not l.visible: continue
		var sc = f.state_coordinator
		var bits: Array[String] = ["P%d %s  %.0f%%" % [f.player_index, f.fighter_name, f.damage_percent]]
		bits.append("%s · %s · %s" % [sc.control_lane(), sc.action, sc.locomotion])
		var flags: Array[String] = []
		if f.hitstun > 0: flags.append("HITSTUN %df" % roundi(f.hitstun * 60.0))
		if f.tumble and f.tumble.active: flags.append("TUMBLE")
		if f.get("freeze_remaining") and f.freeze_remaining > 0: flags.append("FROZEN")
		if f.get("shielding"): flags.append("SHIELD")
		if f.get("landing_lag") and f.landing_lag > 0: flags.append("LANDING LAG %df" % roundi(f.landing_lag * 60.0))
		if not flags.is_empty(): bits.append(" ".join(flags))
		var ap := _anim_player(f)
		if ap and ap.current_animation != "":
			bits.append("%s  %.2fs" % [ap.current_animation, ap.current_animation_position])
		l.text = "\n".join(bits)
		var sp := cam.unproject_position(f.global_position + Vector3.UP * 2.4)
		l.position = sp - Vector2(l.size.x * 0.5, l.size.y)
