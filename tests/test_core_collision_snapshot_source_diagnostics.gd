extends SceneTree
func _init() -> void:
	var sampler = preload("res://scripts/core/collision/committed_pose_sampler.gd").new()
	for item in [["res://assets/teknium/teknium_animations.glb","Teknium_Master_Armature/Skeleton3D","Punch"],["res://assets/ice_mage/ice_mage_combat.glb","Armature/Skeleton3D","IceStrike"]]:
		sampler.configure(load(item[0]),NodePath(item[1]),NodePath("AnimationPlayer"))
		var pose: Dictionary = sampler.sample(item[2],0,0)
		for name_ in ["Head","Hips","RightHand"]:
			var b: Basis = pose[name_].basis
			print(item[0]," ",name_," scale=",b.get_scale()," relative lengths=",b.y.length_squared()/b.x.length_squared()," ",b.z.length_squared()/b.x.length_squared()," relative dots=",b.x.dot(b.y)/b.x.length_squared()," ",b.x.dot(b.z)/b.x.length_squared()," ",b.y.dot(b.z)/b.x.length_squared())
	print("PASS: collision snapshot source diagnostics")
	quit()
