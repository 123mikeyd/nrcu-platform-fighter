extends Node3D
## Read-only Teknium source-style arcs. Geometry from teknium_magic.update_arcs;
## endpoints/time are committed presentation data, never contact queries.
var visuals: Dictionary = {}
func present(relations: Array):
	var live := {}
	for relation in relations:
		var id: String = relation.activation_id
		live[id] = true
		if not is_instance_valid(visuals.get(id)):
			var arc := MeshInstance3D.new()
			arc.name = "CommittedGrabArcs"
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color(.65,.86,1)
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			arc.material_override = material
			add_child(arc)
			visuals[id] = arc
		var arc: MeshInstance3D = visuals[id]
		if arc.get_meta("committed",{}) == relation: continue
		arc.set_meta("committed",relation.duplicate(true))
		var start: Vector3 = arc.to_local(relation.start)
		var center: Vector3 = arc.to_local(relation.center)
		var elapsed: float = relation.elapsed
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for strand in 4:
			var previous := start
			for point in range(1,7):
				var t := point/6.0
				var next := start.lerp(center+Vector3(0,(strand-1.5)*0.16,0.18*sin(strand)),t)
				next += Vector3(0,sin(point*4+elapsed*32+strand)*0.055,cos(point*3+elapsed*29+strand)*0.055)*sin(t*PI)
				segment(mesh,previous,next)
				previous = next
		for strand in 3:
			var previous := center+Vector3(-0.28,0.36-strand*0.28,0.36)
			for point in range(1,8):
				var t := point/7.0
				var next := center+Vector3(-0.28+t*0.56,0.36-strand*0.28+sin(point*4+elapsed*30+strand)*0.07,0.36+sin(t*PI)*0.04)
				segment(mesh,previous,next)
				previous = next
		mesh.surface_end()
		arc.mesh = mesh
	# Reconcile releases even at an unchanged tick (pause/cancel/rematch).
	for id in visuals.keys():
		if not live.has(id):
			if is_instance_valid(visuals[id]): visuals[id].free()
			visuals.erase(id)
func segment(mesh: ImmediateMesh,a: Vector3,b: Vector3):
	var side := (b-a).cross(Vector3.BACK).normalized()*0.012
	for point in [a-side,a+side,b+side,a-side,b+side,b-side]: mesh.surface_add_vertex(point)
