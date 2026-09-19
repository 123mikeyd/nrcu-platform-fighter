extends SceneTree
const POLICY := "res://scripts/core/collision/committed_pose_policy.gd"
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; print("FAIL: ",message)
func _initialize() -> void: call_deferred("run")
func metadata(id: String) -> Dictionary:
	var profile: Resource = load("res://data/collision/generated/"+id+".tres")
	var model: Node = load(profile.source_asset).instantiate()
	var skeleton: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
	var player: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
	var names := []; var parents := []; var rests := []; var clips := {}
	for b in skeleton.get_bone_count():
		names.append(String(skeleton.get_bone_name(b))); parents.append(skeleton.get_bone_parent(b)); rests.append(skeleton.get_bone_rest(b))
	for clip in player.get_animation_list(): clips[String(clip)] = player.get_animation(clip).length
	var placement := Transform3D.IDENTITY
	var ancestor: Node = skeleton
	while ancestor != null:
		if ancestor is Node3D: placement = ancestor.transform * placement
		ancestor = ancestor.get_parent()
	var source := {"skeleton_placement":placement,"source_asset":profile.source_asset,"source_sha256":FileAccess.get_sha256(profile.source_asset),"skeleton_path":model.get_path_to(skeleton),"player_path":model.get_path_to(player),"names":names,"parents":parents,"rests":rests,"clips":clips}
	print("IMPORTED ",id," ",source.skeleton_path," ",clips)
	model.free()
	return {"character_id":id,"source_asset":profile.source_asset,"source_sha256":profile.source_sha256,"visual_scale":profile.visual_scale,"foot_origin":profile.foot_origin,"sources":[source]}
func context() -> Dictionary:
	return {"generation":1,"lifecycle_revision":0,"status":"normal","locomotion":"idle","action":"","grounded":true,"facing":1.0,"air_jumps_left":2,"velocity":Vector3.ZERO,"presentation":{},"strike_id":"","recovery_id":"","force_id":"","grab":{},"caught":{}}
func run() -> void:
	var tek := metadata("teknium"); var turbo := metadata("turbofit")
	check(ResourceLoader.exists(POLICY),"committed policy exists")
	if not ResourceLoader.exists(POLICY): quit(1); return
	var policy = load(POLICY).new()
	check(policy.configure(tek).is_empty(),"configure real Teknium")
	var pose: Dictionary = policy.sample(context(),0)
	check(pose.get("ok",false) and pose.get("clip","") == "Idle" and pose.get("source_seconds",-1) == 0.0,"actual Idle request")
	var kit = load("res://scripts/core/kits/turbofit_kit.gd").new()
	kit.start("air",Vector2.RIGHT,true,1.0); kit.tick(.18)
	check(policy.configure(turbo).is_empty(),"configure actual Turbo")
	var c := context(); c.grounded = false; c.presentation = kit.snapshot().presentation
	pose = policy.sample(c,0)
	check(pose.get("ok",false) and pose.get("clip","") == "AirSideKick" and is_equal_approx(pose.get("source_seconds",-1),.18),"real air kit maps source seconds")
	if not failures: print("PASS: committed pose policy initial tracer")
	quit(1 if failures else 0)
