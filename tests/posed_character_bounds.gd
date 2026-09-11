extends RefCounted
func bounds(model):
    var result={}
    for mesh in model.find_children("*","MeshInstance3D",true,false):
        if not mesh.is_visible_in_tree():continue
        var sk=mesh.get_node_or_null(mesh.skeleton)
        var m=mesh.mesh
        var transforms=[]
        if sk is Skeleton3D and mesh.skin != null:
            for b in mesh.skin.get_bind_count():
                var bone=sk.find_bone(mesh.skin.get_bind_name(b)) if mesh.skin.get_bind_name(b)!=&"" else mesh.skin.get_bind_bone(b)
                transforms.append(sk.global_transform*sk.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(b))
        var lo=Vector3(INF,INF,INF); var hi=Vector3(-INF,-INF,-INF)
        for s in m.get_surface_count():
            var a=m.surface_get_arrays(s)
            var verts=a[Mesh.ARRAY_VERTEX]
            var stride=4
            if a[Mesh.ARRAY_BONES]!=null:stride=a[Mesh.ARRAY_BONES].size()/verts.size()
            for vi in verts.size():
                var p=mesh.global_transform*verts[vi]
                if not transforms.is_empty():
                    p=Vector3.ZERO
                    for j in stride:
                        p+=(transforms[a[Mesh.ARRAY_BONES][vi*stride+j]]*verts[vi])*a[Mesh.ARRAY_WEIGHTS][vi*stride+j]
                lo=lo.min(p);hi=hi.max(p)
        result[str(mesh.name)]={"min":[lo.x,lo.y,lo.z],"max":[hi.x,hi.y,hi.z],"height":hi.y-lo.y}
    return result
