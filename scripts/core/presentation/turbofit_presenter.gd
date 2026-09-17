extends Node3D
var canonical = preload("res://scripts/core/presentation/canonical_collision_presenter.gd").new()
func present_canonical(record: Dictionary) -> void:
	canonical.present(self, record)
## Independent render-only consumer of committed Turbofit snapshots.
const MODEL = preload("res://assets/turbofit/turbofit_animations.glb")
const BASIC := ["GoalkeeperKick", "AirSideKick", "AirDownKick", "MeleeHorizontal", "MeleeBackhand"]
var model: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var _materials: Array[Material] = []
var output: Dictionary = {}
var play_count := 0
func _ready() -> void:
	scale = Vector3.ONE * 1.25
	model = MODEL.instantiate()
	add_child(model)
	animation_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	canonical.configure(self)
	# Private nonlooping playback copies preserve inclusive authored endpoints.
	for name in animation_player.get_animation_library_list():
		var source := animation_player.get_animation_library(name)
		var library := AnimationLibrary.new()
		for clip in source.get_animation_list():
			var animation: Animation = source.get_animation(clip).duplicate(true)
			animation.loop_mode = Animation.LOOP_NONE
			library.add_animation(clip, animation)
		animation_player.remove_animation_library(name)
		animation_player.add_animation_library(name, library)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source = mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate()
				material.metallic = minf(material.metallic, 0.08)
				material.roughness = maxf(material.roughness, 0.68)
				material.emission_enabled = true
				material.emission = Color.WHITE
				material.emission_texture = material.albedo_texture
				material.emission_energy_multiplier = 0.25
				_materials.append(material)
				mesh.set_surface_override_material(surface, material)
const MAP := {"idle":"Idle", "walk":"Walk", "run":"Run", "initial_dash":"Run", "turn":"Walk", "brake":"Walk", "jump_startup":"Jump", "rising":"Jump", "falling":"FallLoop", "fast_fall":"FallLoop", "landing":"Landing"}
const LOOPS := ["Idle", "Walk", "Run", "FallLoop", "BlockIdle"]
var _last_tick := -1
var _elapsed := 0.0
var _blend_elapsed := 0.0
var _from: Array[Transform3D] = []
var _facing := 1.0
func reset() -> void:
	canonical.reset(self)
	output.clear()
	_last_tick = -1
	_elapsed = 0.0
	_blend_elapsed = 0.0
	_from.clear()
	_facing = 1.0
	animation_player.stop()
	skeleton.reset_bone_poses()
	model.rotation.y = PI/2
	position = Vector3.ZERO
func present(snapshot: Dictionary, tick: int) -> void:
	if tick < _last_tick: reset()
	var delta := maxf(0, tick - _last_tick)/60.0 if _last_tick >= 0 else 0.0
	_last_tick = tick
	var stopped: bool = snapshot.get("stopped", false) or snapshot.get("paused", false) or snapshot.get("frozen", false) or snapshot.get("hitstop", false) or snapshot.get("status", "") == "frozen"
	var request: Dictionary = snapshot.get("presentation", {})
	var locomotion: String = snapshot.get("locomotion", "idle")
	var clip: String = MAP.get(locomotion, "Idle")
	var identity: String = str(snapshot.get("episode_id", locomotion))
	var fallback := ""
	var basic := false
	var special := false
	var returning := false
	if snapshot.get("hit", false) or snapshot.get("status", "") == "hitstun":
		clip = "HitReactRight"
		identity = str(snapshot.get("hit_id", "hit"))
	elif snapshot.get("shielding", false) or snapshot.get("action", "") in ["block", "movement_lock"]:
		clip = "BlockIdle"
		identity = "shield"
	elif request.get("move", "") == "power_chord" and request.get("phase", "") in ["anticipation", "release"] and not str(request.get("activation_id", "")).is_empty():
		clip = "TwoHandCombo"
		identity = str(request.activation_id) + ":" + str(request.phase)
		returning = request.phase == "release" and float(request.age) > .3333334
		if returning:
			clip = "Idle"
			identity += ":return"
		special = true
	elif request.get("move", "") in ["sound_wave", "sound_orb", "rising_chord"] and request.get("phase", "") in ["active", "recovery"] and not str(request.get("activation_id", "")).is_empty():
		special = true
		identity = str(request.activation_id)
		clip = {"sound_wave":"TwoHandCombo", "sound_orb":"BlockIdle", "rising_chord":"Jump"}[request.move]
		fallback = {"sound_wave":"TEMP: legacy TwoHandCombo; detached wave renderer not provided", "sound_orb":"TEMP: legacy BlockIdle; orb effect renderer not provided", "rising_chord":"TEMP: Rising Chord uses legacy Jump; no dedicated recovery clip"}[request.move]
	elif snapshot.get("action", "") == "recovery" or not str(snapshot.get("recovery_id", "")).is_empty():
		clip = "Jump"
		identity = str(snapshot.get("recovery_id", "recovery"))
		fallback = "TEMP: Rising Chord uses legacy Jump; no dedicated recovery clip"
	elif request.get("clip", "") in BASIC and not str(request.get("activation_id", "")).is_empty():
		clip = request.clip
		identity = str(request.activation_id)
		basic = true
	elif not request.is_empty() and not str(request.get("clip", "")).is_empty():
		fallback = "TEMP: unsupported committed ability; locomotion only"
	elif locomotion in ["turn", "brake", "initial_dash"]:
		fallback = "TEMP: " + locomotion + " uses " + clip
	elif not MAP.has(locomotion):
		fallback = "TEMP: unknown locomotion uses Idle"
	var changed: bool = output.is_empty() or output.clip != clip or output.identity != identity
	var elapsed: float = maxf(0, float(request.get("elapsed", 0))) if basic else maxf(0, float(request.get("age", 0))) if special else maxf(0, float(snapshot.get("elapsed", 0))) if snapshot.has("elapsed") else 0.0 if changed else _elapsed + (0.0 if stopped else delta)
	if not changed and (stopped or is_equal_approx(elapsed, _elapsed)): return
	if changed:
		_from.clear()
		for bone in skeleton.get_bone_count(): _from.append(skeleton.get_bone_pose(bone))
		# A synchronous lifecycle replacement must retire its old pose even when
		# no future clock step is available to finish a transition blend.
		_blend_elapsed = 0.06 if output.is_empty() or basic or special or stopped or delta == 0.0 else 0.0
		if returning:
			_blend_elapsed = maxf(0,elapsed-1.0/3) if not output.is_empty() and not stopped and delta > 0 else 0.20
		animation_player.play(clip, 0)
		play_count += 1
	else:
		_blend_elapsed += maxf(0, elapsed - _elapsed)
	_elapsed = elapsed
	_facing = float(request.get("facing", _facing)) if basic or special else float(snapshot.get("facing", _facing))
	model.rotation.y = _facing*PI/2
	# Turbofit's source visual applies no clip-specific grounding translation.
	position = Vector3.ZERO
	var length := animation_player.get_animation(clip).length
	var seconds := elapsed
	if special:
		if request.move == "sound_wave":
			seconds = elapsed/.7*length
		elif request.move in ["sound_orb", "rising_chord"]:
			seconds = elapsed
		elif returning:
			seconds = elapsed-1.0/3
		elif request.phase == "release":
			seconds = 19.0/30+elapsed
		else:
			var frame := lerpf(1,16,sin(minf(elapsed/.25,1)*PI/2))
			if elapsed > .25: frame = 15+cos((elapsed-.25)*TAU/.9)
			seconds = (frame-1)/30
	elif basic:
		# Never read replaced gameplay cooldown as an animation duration.
		var duration: float = {"GoalkeeperKick":59.0/60, "AirSideKick":0.5, "AirDownKick":38.0/30, "MeleeHorizontal":0.8, "MeleeBackhand":0.8}[clip]
		seconds = clampf(elapsed/duration,0,1)*length
	elif clip in ["Walk", "Run"]:
		var velocity: Vector3 = snapshot.get("velocity", Vector3(2.5 if clip == "Walk" else 7.5,0,0))
		seconds *= clampf(absf(velocity.x)/(2.5 if clip == "Walk" else 7.5),0.55,1.6)
	seconds = fmod(seconds,length) if clip in LOOPS else minf(seconds,length)
	animation_player.seek(seconds,true)
	var blend := clampf(_blend_elapsed/(0.20 if returning else 0.06),0,1)
	if blend < 1:
		for bone in skeleton.get_bone_count(): skeleton.set_bone_pose(bone, _from[bone].interpolate_with(skeleton.get_bone_pose(bone),blend))
	skeleton.force_update_all_bone_transforms()
	output = {"clip":clip,"identity":identity,"seconds":seconds,"elapsed":elapsed,"blend":blend,"fallback":fallback}
