extends RefCounted
## One match-owned source/policy/snapshot per entity. Never reads a renderer.
const Sampler = preload("res://scripts/core/collision/committed_pose_sampler.gd")
const Policy = preload("res://scripts/core/collision/committed_pose_policy.gd")
const Snapshot = preload("res://scripts/core/collision/collision_snapshot.gd")
var sampler = Sampler.new()
var policy = Policy.new()
var builder = Snapshot.new()
var character_id := ""
var source_asset := ""
var source_sha256 := ""
var lifecycle_revision := 0
var _record: Dictionary = {}
var _contact_record: Dictionary = {}

func configure(profile: Resource, revision: String) -> PackedStringArray:
	invalidate("profile replacement")
	if profile == null or profile.get_script() != preload("res://scripts/core/collision/character_collision_profile.gd"):
		return PackedStringArray(["unsupported collision profile"])
	if profile.character_id not in ["teknium","turbofit"]: return PackedStringArray(["unsupported collision character"])
	if not profile.source_asset.ends_with(".glb") or not FileAccess.file_exists(profile.source_asset):
		return PackedStringArray(["missing or unsupported collision pose source asset"])
	var errors: PackedStringArray = builder.configure(profile,profile.source_asset,FileAccess.get_sha256(profile.source_asset),revision,"conservative_affine")
	if not errors.is_empty(): return errors
	var packed: PackedScene = load(profile.source_asset)
	if profile.character_id == "teknium":
		packed = preload("res://scripts/core/presentation/teknium_swing_source.gd").assembled_source(packed)
		if packed == null: return PackedStringArray(["invalid trusted Teknium swing derivation"])
	var skeleton_path := NodePath("Teknium_Master_Armature/Skeleton3D" if profile.character_id == "teknium" else "TurboFit_Master_Rig/Skeleton3D")
	if sampler.configure(packed,skeleton_path,NodePath("AnimationPlayer")) != OK:
		return PackedStringArray(["unsupported collision pose source/path"])
	var rest := sampler.sample_rest()
	for h in profile.hurtboxes:
		if not rest.has(h.bone_name): return PackedStringArray(["missing imported hurtbox bone: "+h.bone_name])
	# Source has passed the sampler's script/track SceneState preflight. Capture
	# actual immutable metadata, not guessed durations or renderer clocks.
	var model := packed.instantiate()
	var skeleton: Skeleton3D = model.get_node(skeleton_path)
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	var names := []; var parents := []; var rests := []; var clips := {}
	for b in skeleton.get_bone_count():
		names.append(String(skeleton.get_bone_name(b))); parents.append(skeleton.get_bone_parent(b)); rests.append(skeleton.get_bone_rest(b))
	for clip in player.get_animation_list(): clips[String(clip)] = player.get_animation(clip).length
	var placement := Transform3D.IDENTITY
	var ancestor: Node = skeleton
	while ancestor != null:
		if ancestor is Node3D: placement = ancestor.transform * placement
		ancestor = ancestor.get_parent()
	model.free()
	var source := {"skeleton_placement":placement,"source_asset":profile.source_asset,"source_sha256":profile.source_sha256,"skeleton_path":skeleton_path,"player_path":NodePath("AnimationPlayer"),"names":names,"parents":parents,"rests":rests,"clips":clips}
	if profile.character_id == "teknium": source.derived_source = preload("res://scripts/core/presentation/teknium_swing_source.gd").identity()
	errors = policy.configure({"character_id":profile.character_id,"source_asset":profile.source_asset,"source_sha256":profile.source_sha256,"visual_scale":profile.visual_scale,"foot_origin":profile.foot_origin,"sources":[source]})
	if not errors.is_empty(): return errors
	character_id = profile.character_id; source_asset = profile.source_asset; source_sha256 = profile.source_sha256
	return PackedStringArray()

func invalidate(reason: String) -> void:
	lifecycle_revision += 1
	_contact_record.clear()
	sampler.reset(); policy.reset(); builder.reset()
	_record = {"ok":false,"diagnostics":PackedStringArray([reason]),"primitives":[],"has_bounds":false,"geometry_mode":"generated_hurtboxes"}

func commit(context: Dictionary, local_tick: int, actor_transform: Transform3D, participation: Dictionary, phase: String = "contacts") -> void:
	context = context.duplicate(true)
	context.lifecycle_revision = lifecycle_revision
	var request: Dictionary = policy.sample(context,local_tick)
	if not request.get("ok",false):
		_record = {"ok":false,"diagnostics":request.get("diagnostics",["invalid committed pose"]),"primitives":[],"has_bounds":false,"geometry_mode":"generated_hurtboxes","pose_request":request}
		if phase == "contacts": _contact_record = _record.duplicate(true)
		return
	var pose := sampler.sample(request.clip,request.source_seconds,request.time_policy)
	var revision := {"source_asset":source_asset,"source_sha256":source_sha256,"clip":request.clip,"seconds":request.source_seconds,"policy":request.time_policy,"episode_id":str(request.episode_id)}
	_record = builder.build(str(context.entity_id),pose,actor_transform * request.modelplacement,revision,participation)
	_record.merge({"geometry_mode":"generated_hurtboxes","pose_request":request,"local_tick":local_tick,"lifecycle_revision":lifecycle_revision})
	if phase == "contacts": _contact_record = _record.duplicate(true)

func telemetry() -> Dictionary:
	var result := _record.duplicate(true)
	result.contact_snapshot = _contact_record.duplicate(true)
	return result
