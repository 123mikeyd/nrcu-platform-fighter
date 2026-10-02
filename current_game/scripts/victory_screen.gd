extends Control
# Melee-style after-fight screen: the winner plays a short pose-in that ends on a
# freeze frame; everyone who lost claps in the back row. Own 3D world inside a
# SubViewport, so the arena and fighter logic are untouched. No flashing
# overlays (Mike's rule): dark backdrop, a soft slide/slam-in only.
# Clips: Mixamo retargets, approved by Mike
# 2026-09-30 ("just use what ever and I will fix turbo later").

const DemoStyle = preload("res://scripts/demo_style.gd")
const LIBS := {
	"teknium": "res://assets/victory/teknium_victory_v2.tres",   # v2 = dance pool + clap (v1 kept for rollback)
	"doge_man": "res://assets/victory/doge_man_victory_v1.tres",
	"turbofit": "res://assets/victory/turbofit_victory_v1.tres",
	"witcheer": "res://assets/victory/witcheer_victory_v1.tres",
}
const VISUALS := {
	"teknium": "res://scripts/teknium_visual.gd",
	"doge_man": "res://scripts/doge_visual.gd",
	"turbofit": "res://scripts/turbofit_visual.gd",
	"witcheer": "res://scripts/witcheer_visual.gd",
	"ggb": "res://scripts/ggb_visual.gd",
	"ice_mage": "res://scripts/ice_mage_visual.gd",
}
# Not shown yet (their visuals need a live Fighter owner): mephisto, bobo.
# Witcheer has no retargeted pose-in; their own authored Celebration is used.
const NATIVE_POSE := {"witcheer": "Celebration"}
# Freeze partway through a clip (seconds) instead of on its last frame.
# Witcheer: just after the kicked leg starts to drop (Mike 2026-09-30); peak is ~0.73 s.
const FREEZE_AT := {"witcheer": 0.80}
# Dance pool: a winner whose library has "VictoryDance_*" clips picks one at random
# and loops it instead of pose-in + freeze. Teknium only (Mike 2026-09-30): Gangnam A,
# Gangnam B, Robot, Tut.
const DANCE_PREFIX := "VictoryDance_"
var dance_rng := RandomNumberGenerator.new()
var force_dance := ""           # tests/captures: pick this dance instead of random
# Visuals face +X at facing 1.0; turn them toward the camera with a slight 3/4.
const FACE_CAMERA := -PI / 2.0
# TurboFit's imported rig faces the opposite way from the Meshy rigs (checked: toe
# direction pointed away from the camera without this).
const YAW_FIX := {"turbofit": PI}
# Victory-screen floor placement (visual.position.y), replacing each visual's in-game
# clip offset. Teknium's visual keeps its Idle offset (-0.224) after _ready, which sank
# every Mixamo victory clip ~23 cm through the podium; TurboFit's retargets sit ~11 cm low.
# Measured from evaluated skinned soles at clip start (tests/test_victory_grounding.gd).
# Doge's pose-in ending in a hop (+0.23) is authored and kept. GGB keeps its hover.
const GROUND_Y := {
	"teknium": 0.008,
	"doge_man": 0.018,
	"turbofit": 0.11,
	"witcheer": {"victory/VictoryClap": -0.09, "Celebration": -0.044},
}
const WINNER_TURN := 0.22
const LOSER_TURN := 0.12

var viewport: SubViewport
var container: SubViewportContainer   # built only while the screen shows (mobile tests: no idle SubViewports)
var world_root: Node3D
var stage: Node3D
var title: Label
var actors: Array = []          # [{id, visual, player, role}]
var _serial := 0

func _ready() -> void:
	name = "VictoryScreen"
	dance_rng.randomize()
	theme = DemoStyle.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = Label.new()
	title.name = "VictoryTitle"
	title.position = Vector2(0, 26)
	title.size = Vector2(1280, 90)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.pivot_offset = Vector2(640, 45)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("f2d27a"))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	hide()

func _ensure_view() -> void:
	if container: return
	container = SubViewportContainer.new()
	container.name = "VictoryView"
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	move_child(container, 0)
	viewport = SubViewport.new()
	viewport.name = "VictoryViewport"
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	world_root = Node3D.new()
	world_root.name = "VictoryWorld"
	viewport.add_child(world_root)
	_build_world()

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.045, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.09)
	env.fog_density = 0.035
	var we := WorldEnvironment.new()
	we.environment = env
	world_root.add_child(we)
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-28), 0)
	key.light_energy = 1.35
	key.shadow_enabled = true
	world_root.add_child(key)
	var rim := OmniLight3D.new()
	rim.name = "WarmRim"
	rim.position = Vector3(0, 3.6, -2.4)
	rim.light_color = Color(1.0, 0.78, 0.45)
	rim.light_energy = 2.4
	rim.omni_range = 8.0
	world_root.add_child(rim)
	var spot := SpotLight3D.new()
	spot.name = "WinnerSpot"
	spot.position = Vector3(0, 6.5, 3.2)
	spot.look_at_from_position(spot.position, Vector3(0, 0, 0.9))
	spot.light_color = Color(1.0, 0.93, 0.8)
	spot.light_energy = 3.2
	spot.spot_range = 12.0
	spot.spot_angle = 24.0
	world_root.add_child(spot)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 7.5
	disc.bottom_radius = 7.5
	disc.height = 0.1
	floor_mesh.mesh = disc
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.09, 0.1, 0.13)
	floor_mat.roughness = 0.85
	floor_mesh.material_override = floor_mat
	floor_mesh.position.y = -0.05
	world_root.add_child(floor_mesh)
	var podium := MeshInstance3D.new()
	var pd := CylinderMesh.new()
	pd.top_radius = 1.25
	pd.bottom_radius = 1.32
	pd.height = 0.16
	podium.mesh = pd
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.36, 0.27, 0.13)
	pmat.metallic = 0.55
	pmat.roughness = 0.4
	podium.material_override = pmat
	podium.name = "Podium"
	podium.position = Vector3(0, 0.08, 1.0)
	world_root.add_child(podium)
	var cam := Camera3D.new()
	cam.name = "VictoryCamera"
	cam.fov = 34.0
	cam.position = Vector3(0, 2.25, 9.4)
	world_root.add_child(cam)
	cam.look_at(Vector3(0, 1.15, 0), Vector3.UP)
	cam.current = true
	stage = Node3D.new()
	stage.name = "Actors"
	world_root.add_child(stage)

# winners / losers: Arrays of {"id": String, "color": Color}
func show_results(winners: Array, losers: Array, headline: String) -> void:
	clear()
	_serial += 1
	_ensure_view()
	show()
	title.text = headline
	var w_count := winners.size()
	for i in w_count:
		var x := (i - (w_count - 1) / 2.0) * 1.6
		_spawn(winners[i], Vector3(x, 0.16, 1.0), "winner", i)
	# back row: alternate left/right of the winner, never straight behind them
	const COLUMNS := [-2.05, 2.05, -3.45, 3.45]
	for i in losers.size():
		_spawn(losers[i], Vector3(COLUMNS[i % 4], 0.0, -1.9), "loser", i)
	_slam_title()

func _spawn(entry: Dictionary, at: Vector3, role: String, index: int) -> void:
	var id: String = entry.get("id", "")
	if not VISUALS.has(id): return
	var holder := Node3D.new()
	holder.name = "%s_%s_%d" % [role, id, index]
	holder.position = at
	var turn := WINNER_TURN if role == "winner" else LOSER_TURN
	if at.x > 0.01: turn = -turn
	holder.rotation.y = FACE_CAMERA + turn + float(YAW_FIX.get(id, 0.0))
	stage.add_child(holder)
	var visual: Node3D = load(VISUALS[id]).new()
	if "palette" in visual and entry.has("color"): visual.set("palette", entry.color)
	holder.add_child(visual)
	visual.set_process(false)       # presentation only; no fighter owner here
	visual.set_physics_process(false)
	if role == "loser":
		holder.scale = Vector3.ONE * 0.9
	var player: AnimationPlayer = visual.get("animation_player")
	var rec := {"id": id, "visual": visual, "player": player, "role": role}
	actors.append(rec)
	if player == null: return
	if LIBS.has(id) and not player.has_animation_library("victory"):
		player.add_animation_library("victory", load(LIBS[id]))
	if role == "winner":
		var dances := _dance_pool(player)
		if not dances.is_empty():
			var pick: String = "victory/" + DANCE_PREFIX + force_dance
			if force_dance == "" or not player.has_animation(pick):
				pick = dances[dance_rng.randi_range(0, dances.size() - 1)]
			player.play(pick, 0.15)   # clip is loop_mode LINEAR: dances until the screen clears
			rec["clip"] = pick
			rec["looping"] = true
			rec["frozen"] = true      # settled: winner_frozen() callers treat a looping dance as done
			_ground(rec)
			return
		var clip := "victory/VictoryPose" if player.has_animation("victory/VictoryPose") else String(NATIVE_POSE.get(id, ""))
		if clip != "" and player.has_animation(clip):
			player.play(clip, 0.15)
			rec["clip"] = clip
			var serial := _serial
			if FREEZE_AT.has(id): rec["freeze_at"] = float(FREEZE_AT[id])
			else: player.animation_finished.connect(func(_n): _freeze(rec, serial), CONNECT_ONE_SHOT)
	else:
		if player.has_animation("victory/VictoryClap"):
			player.play("victory/VictoryClap", 0.2)
			# desync the claps a little so the crowd doesn't move in lockstep
			player.seek(fmod(0.23 * (index + 1), player.current_animation_length), true)
			rec["clip"] = "victory/VictoryClap"
	_ground(rec)

# Put the evaluated soles on the surface (podium top / floor) for the chosen clip.
func _ground(rec: Dictionary) -> void:
	var g = GROUND_Y.get(rec.id)
	if g is Dictionary: g = g.get(rec.get("clip", ""))
	if g == null or not rec.has("clip"): return
	rec.visual.position.y = float(g)

func _dance_pool(player: AnimationPlayer) -> Array:
	var out := []
	if player.has_animation_library("victory"):
		for n in player.get_animation_library("victory").get_animation_list():
			if String(n).begins_with(DANCE_PREFIX): out.append("victory/" + String(n))
	out.sort()
	return out

func _process(_delta: float) -> void:
	for rec in actors:
		if rec.has("freeze_at") and not rec.get("frozen", false) and is_instance_valid(rec.player) 				and rec.player.current_animation_position >= rec.freeze_at:
			_freeze(rec, _serial)

func _freeze(rec: Dictionary, serial: int) -> void:
	if serial != _serial or not is_instance_valid(rec.player): return
	# hold the pose-in's freeze frame (its last frame, or FREEZE_AT)
	var clip: String = rec.get("clip", "")
	if clip != "" and rec.player.has_animation(clip):
		var at: float = rec.get("freeze_at", rec.player.get_animation(clip).length)
		rec.player.play(clip)
		rec.player.seek(at, true)
		rec.player.pause()
	rec["frozen"] = true

func _slam_title() -> void:
	title.scale = Vector2(1.6, 1.6)
	title.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(title, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "modulate:a", 1.0, 0.18)

func winner_frozen() -> bool:
	for a in actors:
		if a.role == "winner" and not a.get("frozen", false): return false
	return not actors.is_empty()

func clear() -> void:
	_serial += 1
	actors.clear()
	if container:
		container.queue_free()   # frees the whole 3D world with its actors
		container = null
		viewport = null
		world_root = null
		stage = null
	hide()
