extends Node3D
# Approved Gumy mesh and manually reviewed hinge placement; no skeletal retarget.
const MODEL=preload("res://assets/ggb/ggb.glb")
# Source scene named GGB / Tek evaluated heights:
# 0.91314601898 / 1.89958596230, antenna included; replaces the old attachment.
# Placement only: no controller, collider, hit geometry, material or wing changes.
const PRESENTATION_SCALE := 0.48186128424 * 1.02 # Mike 2026-09-27: ~2% bigger (review)
# Provisional in-game review values, not final art approval. Parent-space units
# keep hover presentation-only; steel retains the approved floor placement.
const NORMAL_HOVER := 0.426 # Mike 2026-09-30: +0.026 so idle bob spans ~1.30-1.42 (was 0.40; review)
const IDLE_FLAP_AMPLITUDE := 0.30 # buzzier grounded wings (was 0.14; review)
# Grounded bee bob in WORLD units (converted through PRESENTATION_SCALE). Review values.
const IDLE_BOB_WORLD := 0.06
const WALK_BOB_WORLD := 0.045
const IDLE_BOB_HZ := 1.6
const WALK_BOB_HZ := 2.3
var bob_time := 0.0
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
    position.y = 0.0 if active else NORMAL_HOVER
    for i in meshes.size():
        meshes[i].set_surface_override_material(0,lead_material if active else originals[i])
func sync_pose(grounded:bool,velocity:Vector3,drop:bool,facing:float,delta:float,interrupted:bool):
    if not frozen_reaction_originals.is_empty(): return
    # Wing Gust leans the model about world axes; rebuild from rest every sync.
    model.transform = Transform3D.IDENTITY
    set_lead(drop and not interrupted)
    phase+=delta*(26.0 if grounded else 38.0)
    bob_time+=delta
    var amplitude:=IDLE_FLAP_AMPLITUDE if grounded else 0.62
    if interrupted:amplitude=0.0
    for i in wings.size():
        var side:float=-1.0 if i==0 else 1.0
        wings[i].rotation.z=side*(0.70 if is_lead else 0.38+amplitude*sin(phase))
        wings[i].rotation.y=-side*1.25 if is_lead else 0.0
    rotation.y=facing*0.48
    if interrupted or is_lead:
        model.position.y=0.0
    elif grounded:
        var walking:=absf(velocity.x)>0.2
        var amp:=(WALK_BOB_WORLD if walking else IDLE_BOB_WORLD)/PRESENTATION_SCALE
        model.position.y=amp*sin(TAU*(WALK_BOB_HZ if walking else IDLE_BOB_HZ)*bob_time)
    else:
        model.position.y=0.025*sin(phase*0.5)
    model.rotation.z=clampf(-velocity.x*0.009,-0.08,0.08) if not grounded and not is_lead else 0.0

# Wing Gust pose (Mike's Blender lean X8 Y-60 Z-16, facing right; mirrored for left).
# amount 0..1(+overshoot) scales the lean; wing = hinge flap value; recoil = metres backward.
const GUST_LEAN_DEG := Vector3(8.0, -60.0, -16.0) # Blender XYZ euler on the lean empty
func apply_gust_pose(amount: float, wing: float, recoil: float, facing: float) -> void:
    for i in wings.size():
        var side: float = -1.0 if i == 0 else 1.0
        wings[i].rotation.z = side * wing
        wings[i].rotation.y = 0.0
    if amount == 0.0 and recoil == 0.0: return
    # Blender Z-up -> Godot Y-up: Rz_b -> Ry_g, Ry_b -> Rz_g(-), Rx_b -> Rx_g. Mirror flips Y/Z turns.
    var bx := deg_to_rad(GUST_LEAN_DEG.x) * amount
    var by := deg_to_rad(GUST_LEAN_DEG.y) * amount
    var bz := deg_to_rad(GUST_LEAN_DEG.z) * amount
    var lean := Basis(Vector3.UP, bz * facing) * Basis(Vector3.BACK, -by * facing) * Basis(Vector3.RIGHT, bx)
    var pivot := body_center_world()
    var g := model.global_transform
    g = Transform3D(lean, pivot - lean * pivot) * g
    g.origin += Vector3(-facing * recoil, 0.0, 0.0)
    model.global_transform = g

func body_center_world() -> Vector3:
    return meshes[0].to_global(meshes[0].get_aabb().get_center())
