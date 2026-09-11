extends SceneTree
func _initialize():call_deferred("run")
func run():
    var v=load("res://scripts/ggb_visual.gd").new()
    root.add_child(v)
    var body=v.meshes[0]
    var body_points:PackedVector3Array=body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var failed=false
    for angle in [-0.24,0.38,1.0]:
        for side in 2:
            var wing=v.wings[side]
            wing.rotation.z=(-1.0 if side==0 else 1.0)*angle
            var mesh=v.meshes[side+1]
            var points:PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
            var closest=INF
            var to_body=body.global_transform.affine_inverse()*mesh.global_transform
            for p in points:
                var local=to_body*p
                for b in body_points:
                    closest=minf(closest,local.distance_squared_to(b))
            closest=sqrt(closest)*body.global_basis.get_scale().x
            print("attachment angle=",angle," side=",side," gap=",closest)
            if closest>0.13:
                printerr("FAIL: flight wing separates from body at flap extremum")
                failed=true
    v.free()
    if not failed:print("PASS: both wings remain attached throughout full flight arc")
    quit(1 if failed else 0)
