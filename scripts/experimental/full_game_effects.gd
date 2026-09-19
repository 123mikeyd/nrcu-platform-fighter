extends Node3D
## Read-only committed shot presentation; provisional simple FX, no hit volumes.
var visuals: Dictionary = {}
func present(shots: Array):
	var live := {}
	for shot in shots:
		var id: String = shot.activation_id
		live[id] = true
		if not is_instance_valid(visuals.get(id)):
			var mesh := MeshInstance3D.new()
			mesh.name = "CommittedProjectile"
			var sphere := SphereMesh.new()
			sphere.radius = 0.14
			sphere.height = 0.28
			if shot.kind == "sound_orb":
				sphere.radius = 1.15
				sphere.height = 2.3
			mesh.mesh = sphere
			if shot.kind == "sound_wave":
				var ring := TorusMesh.new()
				ring.inner_radius = 0.38
				ring.outer_radius = 0.46
				mesh.mesh = ring
				mesh.rotation.z = PI / 2
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.material_override = material
			add_child(mesh)
			visuals[id] = mesh
		var mesh: MeshInstance3D = visuals[id]
		mesh.global_position = shot.position
		mesh.rotation.y = 0 if shot.facing > 0 else PI
		var color := Color("61e6b3") if shot.source == 1 else Color("ffb665")
		color.a = float(shot.get("opacity",1.0))
		mesh.material_override.albedo_color = color
	for id in visuals.keys():
		if not live.has(id):
			if is_instance_valid(visuals[id]): visuals[id].free()
			visuals.erase(id)
