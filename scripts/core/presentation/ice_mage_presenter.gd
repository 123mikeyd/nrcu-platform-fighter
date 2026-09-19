extends Node3D
## Detached committed snapshot consumer; never binds a fighter or writes gameplay.
const MODEL = preload("res://assets/ice_mage/ice_mage_combat.glb")
var model: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var output: Dictionary = {}
var play_count := 0
var _materials: Array[Material] = []
func _ready() -> void:
	scale = Vector3.ONE * 1.15
	position.y = .035
	model = MODEL.instantiate()
	add_child(model)
	animation_player = model.find_children("*","AnimationPlayer",true,false)[0]
	skeleton = model.find_children("*","Skeleton3D",true,false)[0]
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for name in animation_player.get_animation_library_list():
		var original := animation_player.get_animation_library(name)
		var library := AnimationLibrary.new()
		for clip in original.get_animation_list():
			var animation: Animation = original.get_animation(clip).duplicate(true)
			animation.loop_mode = Animation.LOOP_NONE
			library.add_animation(clip,animation)
		animation_player.remove_animation_library(name)
		animation_player.add_animation_library(name,library)
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original = mesh.get_active_material(surface)
			if original is StandardMaterial3D:
				var material: StandardMaterial3D = original.duplicate()
				material.emission_enabled = false
				_materials.append(material)
				mesh.set_surface_override_material(surface,material)
var _last_tick := -1
var _elapsed := 0.0
var _blend_elapsed := 0.0
var _from: Array[Transform3D] = []
func reset() -> void:
	output.clear()
	_last_tick = -1
	_elapsed = 0
	_blend_elapsed = 0
	_from.clear()
	animation_player.stop()
	skeleton.reset_bone_poses()
	model.rotation.y = PI/2
	position = Vector3(0,.035,0)
func present(snapshot: Dictionary, tick: int) -> void:
	if tick < _last_tick: reset()
	var delta := maxf(0,tick-_last_tick)/60.0 if _last_tick >= 0 else 0.0
	_last_tick = tick
	var stopped: bool = snapshot.get("hitstop",false) or snapshot.get("stopped",false)
	var authored := false
	var request: Dictionary = snapshot.get("presentation",{})
	var relation: Dictionary = snapshot.get("electrocution",{})
	var status: String = snapshot.get("status","normal")
	var clip := "Idle"
	var identity := "idle"
	var fallback := ""
	var elapsed := 0.0
	var facing: float = snapshot.get("facing",1.0)
	if not snapshot.get("enabled",true) or status in ["ko","disabled","respawning","eliminated"]:
		identity = "inactive"
		fallback = "Inactive: Idle fallback"
	elif snapshot.get("frozen",false) or status == "frozen":
		identity = "frozen"
		fallback = "Frozen: Idle fallback (no frozen clip)"
	elif not str(relation.get("activation_id","")).is_empty():
		authored = true
		clip = "Electrocution"
		identity = "electrocution:" + str(relation.activation_id)
		elapsed = maxf(0,float(relation.get("elapsed",0)))
	elif snapshot.get("hit",false) or status == "hitstun":
		identity = "hit:" + str(snapshot.get("hit_id","hit"))
		fallback = "Hit: Idle fallback (no hit clip)"
	elif request.get("clip","") in ["IceStrike","IceCast"] and not str(request.get("activation_id","")).is_empty():
		authored = true
		clip = request.clip
		identity = str(request.activation_id)
		elapsed = maxf(0,float(request.get("elapsed",0)))
		facing = float(request.get("facing",facing))
	elif snapshot.get("shielding",false) or snapshot.get("action","") in ["block","movement_lock"]:
		identity = "shield"
		fallback = "Shield: Idle fallback (no shield clip)"
	elif not snapshot.get("grounded",true) or snapshot.get("locomotion","") in ["jump_startup","rising","falling","fast_fall"]:
		identity = str(snapshot.get("locomotion","airborne"))
		fallback = "Airborne: Idle fallback (no jump/fall clip)"
	else:
		var velocity: Vector3 = snapshot.get("velocity",Vector3.ZERO)
		if absf(velocity.x) > .2: clip = "Run" if absf(velocity.x) >= 4 else "Walk"
		identity = clip.to_lower()
	stopped = stopped or identity in ["frozen","inactive"]
	var changed: bool = output.is_empty() or output.clip != clip or output.identity != identity
	if not authored: elapsed = 0.0 if changed else _elapsed + (0.0 if stopped else delta)
	# Reconcile lifecycle replacements before freezing a complete blended pose.
	if not changed and (stopped or is_equal_approx(elapsed,_elapsed)): return
	if changed:
		_from.clear()
		for bone in skeleton.get_bone_count(): _from.append(skeleton.get_bone_pose(bone))
		_blend_elapsed = .1 if output.is_empty() or authored or stopped or delta == 0 else 0.0
		animation_player.play(clip,0)
		play_count += 1
	else:
		_blend_elapsed += maxf(0,elapsed-_elapsed)
	_elapsed = elapsed
	var length := animation_player.get_animation(clip).length
	var seconds := fmod(elapsed,length) if clip in ["Idle","Walk","Run"] else minf(elapsed,length)
	animation_player.seek(seconds,true)
	var blend := clampf(_blend_elapsed/.1,0,1)
	if blend < 1:
		for bone in skeleton.get_bone_count(): skeleton.set_bone_pose(bone,_from[bone].interpolate_with(skeleton.get_bone_pose(bone),blend))
	skeleton.force_update_all_bone_transforms()
	model.rotation.y = facing*PI/2
	output = {"clip":clip,"identity":identity,"seconds":seconds,"elapsed":elapsed,"blend":blend,"fallback":fallback}
