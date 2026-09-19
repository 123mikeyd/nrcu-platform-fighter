extends "res://tests/test_core_collision_pose.gd"
class CountingSampler:
	extends "res://scripts/core/collision/committed_pose_sampler.gd"
	var attempts := 0
	func _instantiate_source(source: PackedScene) -> Node:
		attempts += 1
		return super._instantiate_source(source)

var assertions := 0
func expect(ok: bool, label: String) -> void:
	assertions += 1
	check(ok,label)

func fixture(kind: int, path: NodePath, enabled := true, root_path := NodePath(".."), library_name := "") -> PackedScene:
	var model := Node3D.new()
	model.name = "Model"
	var rig := Skeleton3D.new()
	rig.name = "Rig"
	model.add_child(rig); rig.owner = model
	rig.add_bone("Root")
	var other := Skeleton3D.new()
	other.name = "Other"
	model.add_child(other); other.owner = model
	other.add_bone("Root")
	var player := AnimationPlayer.new()
	player.name = "Player"
	model.add_child(player); player.owner = model
	player.root_node = root_path
	var animation := Animation.new()
	var track := animation.add_track(kind)
	animation.track_set_path(track,path)
	animation.track_set_enabled(track,enabled)
	var library := AnimationLibrary.new()
	library.add_animation("Test",animation)
	player.add_animation_library(library_name,library)
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	return packed

func denied(packed: PackedScene, label: String) -> void:
	var sampler := CountingSampler.new()
	expect(not sampler.pose_safe_state(packed.get_state()),label+" denied by SceneState preflight")
	expect(sampler.configure(packed,NodePath("Rig"),NodePath("Player")) == ERR_UNAVAILABLE,label+" configure rejects")
	expect(sampler.attempts == 0,label+" zero instantiation attempts")
	expect(sampler.sample_rest().is_empty(),label+" empty source")

func run() -> void:
	for kind in [Animation.TYPE_METHOD,Animation.TYPE_AUDIO,Animation.TYPE_ANIMATION,Animation.TYPE_VALUE,Animation.TYPE_BEZIER]:
		for enabled in [true,false]:
			denied(fixture(kind,NodePath("Rig:Root"),enabled),"kind %s enabled %s" %[kind,enabled])
	for path in ["Rig","Rig:Missing","Rig:Root:position",".:position","Missing:Root","Missing/../Rig:Root","/root/Rig:Root","%Rig:Root"]:
		denied(fixture(Animation.TYPE_POSITION_3D,NodePath(path)),"target "+path)
	denied(fixture(Animation.TYPE_POSITION_3D,NodePath("Rig:Root"),true,NodePath("Missing")),"missing animation root")
	var valid := fixture(Animation.TYPE_ROTATION_3D,NodePath("../Rig:Root"),true,NodePath("."),"combat")
	var sampler := CountingSampler.new()
	expect(sampler.pose_safe_state(valid.get_state()),"named library relative root preflight")
	expect(sampler.configure(valid,NodePath("Rig"),NodePath("Player")) == OK,"named library configure")
	expect(sampler.attempts == 1,"positive control instantiation seam reached once")
	expect(not sampler.sample("combat/Test",0,0).is_empty(),"named library clip sampled")
	# Generic preflight accepts a real bone on either rig; configure must enforce selection.
	var wrong := fixture(Animation.TYPE_POSITION_3D,NodePath("Other:Root"))
	var before := sampler.attempts
	expect(sampler.configure(wrong,NodePath("Rig"),NodePath("Player")) == ERR_UNAVAILABLE,"other skeleton rejected")
	expect(sampler.attempts == before,"selected skeleton rejection before instance")
	expect(sampler.sample_rest().is_empty(),"failed reconfigure clears prior source")
	# Scene inheritance is not AnimationLibrary naming: reject unresolved wrappers.
	var base := fixture(Animation.TYPE_POSITION_3D,NodePath("Rig:Root"))
	var base_path := "user://collision_pose_preflight_base.tscn"
	expect(ResourceSaver.save(base,base_path) == OK,"save wrapper base fixture")
	var inherited_path := "user://collision_pose_preflight_inherited.tscn"
	var file := FileAccess.open(inherited_path,FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="'+base_path+'" id="1"]\n[node name="Inherited" instance=ExtResource("1")]\n')
	file.close()
	var inherited: PackedScene = load(inherited_path)
	expect(inherited.get_state().get_base_scene_state() != null,"fixture really inherited")
	denied(inherited,"inherited library wrapper")
	var wrapper := Node3D.new()
	var child: Node = load(base_path).instantiate()
	wrapper.add_child(child); child.owner = wrapper
	var wrapped := PackedScene.new()
	wrapped.pack(wrapper)
	wrapper.free()
	expect(wrapped.get_state().get_node_instance(1) != null,"fixture really instanced")
	denied(wrapped,"instanced library wrapper")
	DirAccess.remove_absolute(base_path)
	DirAccess.remove_absolute(inherited_path)
	for node in [Timer.new(),AnimationTree.new()]:
		var unsafe := PackedScene.new()
		unsafe.pack(node)
		node.free()
		denied(unsafe,"unsafe node type")
	print("ASSERTIONS ",assertions," FAILURES ",failures)
	if not failures: print("PASS: collision pose SceneState track preflight zero instance attempts")
	quit(1 if failures else 0)
