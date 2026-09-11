extends Node3D
# Approved Gumy mesh and manually reviewed hinge placement; no skeletal retarget.
const MODEL=preload("res://assets/ggb/ggb.glb")
# Latest Desktop/3D Stuff/Roots.blend named GGB / Tek evaluated heights:
# 0.91314601898 / 1.89958596230, antenna included; replaces the old attachment.
# Placement only: no controller, collider, hit geometry, material or wing changes.
const PRESENTATION_SCALE := 0.48186128424
var meshes: Array[MeshInstance3D]=[]
var wings: Array[Node3D]=[]
var originals: Array[Material]=[]
var phase:=0.0
var is_lead:=false
var lead_material: StandardMaterial3D
var model: Node3D
var reaction_samples = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ggb/electrocution_samples.json"))
var reaction_originals := {}
var frozen_reaction_originals := {}
func freeze_reaction() -> void:
    frozen_reaction_originals = reaction_originals.duplicate()
    reaction_originals.clear()
func thaw_reaction() -> void:
    for node in frozen_reaction_originals:
        if is_instance_valid(node): node.transform = frozen_reaction_originals[node]
    frozen_reaction_originals.clear()
func present_electrocution(seconds: float) -> void:
    var samples: Array = reaction_samples.samples
    var cursor := clampf(seconds * float(reaction_samples.fps), 0, samples.size()-1)
    var index := int(cursor)
    var next := mini(index+1, samples.size()-1)
    for node_name in samples[index]:
        var node: Node3D = model.find_child(node_name,true,false)
        if not reaction_originals.has(node): reaction_originals[node] = node.transform
        var a: Array = samples[index][node_name].rotation
        var b: Array = samples[next][node_name].rotation
        node.quaternion = Quaternion(a[0],a[1],a[2],a[3]).slerp(Quaternion(b[0],b[1],b[2],b[3]),cursor-index)
func clear_electrocution() -> void:
    for node in reaction_originals:
        if is_instance_valid(node): node.transform = reaction_originals[node]
    reaction_originals.clear()
func _ready():
    scale = Vector3.ONE * PRESENTATION_SCALE
    model=MODEL.instantiate()
    add_child(model)
    meshes.append(model.find_child("Gumy_Mascot",true,false))
    for side in ["L","R"]:
        wings.append(model.find_child("Gumy_WingHinge_"+side,true,false))
        meshes.append(model.find_child("Gumy_Wing_"+side,true,false))
    for mesh in meshes:
        var material=mesh.get_active_material(0).duplicate()
        mesh.set_surface_override_material(0,material)
        originals.append(material)
    lead_material=StandardMaterial3D.new()
    lead_material.albedo_color=Color(0.31,0.31,0.33)
    lead_material.metallic=0.72
    lead_material.roughness=0.88
    lead_material.cull_mode=BaseMaterial3D.CULL_DISABLED
    sync_pose(true,Vector3.ZERO,false,1,0,false)
func set_lead(active:bool):
    is_lead=active
    for i in meshes.size():
        meshes[i].set_surface_override_material(0,lead_material if active else originals[i])
func sync_pose(grounded:bool,velocity:Vector3,drop:bool,facing:float,delta:float,interrupted:bool):
    if not frozen_reaction_originals.is_empty(): return
    set_lead(drop and not interrupted)
    phase+=delta*(8.0 if grounded else 38.0)
    var amplitude:=0.08 if grounded else 0.62
    if interrupted:amplitude=0.0
    for i in wings.size():
        var side:float=-1.0 if i==0 else 1.0
        wings[i].rotation.z=side*(0.70 if is_lead else 0.38+amplitude*sin(phase))
        wings[i].rotation.y=-side*1.25 if is_lead else 0.0
    rotation.y=facing*0.48
    model.position.y=0.025*sin(phase*0.5) if not grounded and not interrupted and not is_lead else 0.0
    model.rotation.z=clampf(-velocity.x*0.009,-0.08,0.08) if not grounded and not is_lead else 0.0
