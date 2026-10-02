extends RefCounted
# Batch ONLY v8 static dressing. Keep source nodes hidden for attachment/contact audit.
# Geometry, material, shadow mode and transforms are retained; no quality reduction.
static func build(stage):
    for title in ["ConnectedServiceStairsV8","AttachedUnderdeckSupportsV8","ServiceEntryVestibuleV8"]:
        var group:Node3D=stage.get_node(title)
        var batches:Dictionary={}
        for part in group.find_children("*","MeshInstance3D",true,false):
            var shape:Mesh=part.mesh
            if not shape is BoxMesh and not shape is CylinderMesh:continue
            var key:String=("box" if shape is BoxMesh else "cylinder")+"_"+str(part.material_override.get_instance_id())+"_"+str(part.cast_shadow)
            if not batches.has(key):batches[key]=[]
            batches[key].append(part)
        for key in batches:
            var parts:Array=batches[key]
            var prototype:Mesh=parts[0].mesh.duplicate()
            if prototype is BoxMesh:prototype.size=Vector3.ONE
            else:prototype.top_radius=0.5;prototype.bottom_radius=0.5;prototype.height=1.0
            var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=prototype;mm.instance_count=parts.size()
            var inst:=MultiMeshInstance3D.new();inst.name="StaticBatch_"+key;inst.multimesh=mm;inst.material_override=parts[0].material_override;inst.layers=parts[0].layers;inst.cast_shadow=parts[0].cast_shadow;group.add_child(inst)
            for i in parts.size():
                var part:MeshInstance3D=parts[i]
                var size:Vector3=part.mesh.size if part.mesh is BoxMesh else Vector3(part.mesh.bottom_radius*2,part.mesh.height,part.mesh.bottom_radius*2)
                var local:Transform3D=group.global_transform.affine_inverse()*part.global_transform
                local.basis=local.basis*Basis.from_scale(size)
                mm.set_instance_transform(i,local)
                part.set_meta("batch_transform",local);part.set_meta("batch_instance",inst);part.set_meta("batch_index",i)
                part.hide()
