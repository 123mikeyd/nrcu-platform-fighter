extends Node3D
# Bounded cosmetic pool; no physics, animation writes, combat timers or RNG use.
const LIMIT := 12
var pool: Array[Dictionary] = []
var last_move := ""
var last_transition := ""
var burst_count := 0
var sequence := 0
var ambient_time := 0.0
func _ready():
    for i in LIMIT:
        var mesh=MeshInstance3D.new()
        mesh.mesh=QuadMesh.new()
        mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        mesh.material_override=ShaderMaterial.new()
        mesh.material_override.shader=preload("res://scripts/mephisto_wisp.gdshader")
        mesh.visible=false
        add_child(mesh)
        pool.append({"mesh":mesh,"age":0.0,"duration":0.0,"origin":Vector3.ZERO,"drift":Vector3.ZERO,"size":.3})
func reset():
    for w in pool:
        w.duration=0.0
        w.mesh.visible=false
    last_move=""
    last_transition=""
    ambient_time=0.0
func live_count() -> int:
    var count:=0
    for w in pool:
        if w.duration>0.0: count+=1
    return count
func wisp_ages() -> Array:
    var result=[]
    for w in pool: result.append(w.age)
    return result
func emit_wisp(origin: Vector3, burst: bool):
    for w in pool:
        if w.duration>0.0: continue
        sequence+=1
        var phase=float(sequence)*2.39996
        w.age=0.0
        w.duration=.68 if burst else 1.35
        w.origin=origin
        # Broad upward curling shadow, readable at the match camera, not fog.
        w.drift=Vector3(sin(phase)*.28,.30 if burst else .24,cos(phase)*.08)
        w.size=.58 if burst else .98
        w.mesh.material_override.set_shader_parameter("seed",phase)
        w.mesh.material_override.set_shader_parameter("opacity",.52 if burst else .66)
        w.mesh.visible=true
        return
func tick(delta: float, companion):
    var visual=companion.get_parent().get_parent()
    var camera=get_viewport().get_camera_3d()
    var center=visual.global_position+Vector3(0,1.25,0)
    for w in pool:
        if w.duration<=0.0: continue
        w.age+=delta
        if w.age>=w.duration:
            w.duration=0.0;w.mesh.visible=false;continue
    var move: String=visual.shadow_move
    if not move.is_empty() and move!=last_move:
        burst_count+=1
        # World-space hand origins; query only, never solve or retime bones.
        var sk: Skeleton3D=companion.forms[0].find_children("*","Skeleton3D",true,false)[0]
        for hand in ["RightHand","LeftHand"]:
            var index=sk.find_bone(hand)
            if index>=0: emit_wisp(sk.global_transform*sk.get_bone_global_pose(index).origin,true)
    last_move=move
    if companion.transition!=last_transition and companion.transition in ["reveal","switch"]:
        for i in 3:
            emit_wisp(companion.global_transform*Vector3((i-1)*.22,.5,-.15),true)
    last_transition=companion.transition
    if not companion.hidden and (companion.forms[0].visible or companion.forms[1].visible):
        ambient_time+=delta
        if ambient_time>=.24:
            ambient_time=fmod(ambient_time,.24)
            var phase=float(sequence)*2.39996
            emit_wisp(companion.global_transform*Vector3(cos(phase)*.32,.50,-.15+sin(phase)*.14),false)
    for w in pool:
        if w.duration<=0.0: continue
        var life: float=w.age/w.duration
        w.mesh.global_position=w.origin+w.drift*life+Vector3(sin(life*TAU)*.085,0,0)
        if camera: w.mesh.global_basis=camera.global_basis.orthonormalized()
        w.mesh.scale=Vector3(1.15,.85,1.0)*w.size*(.8+life*.55)
        w.mesh.material_override.set_shader_parameter("life",life)
        w.mesh.material_override.set_shader_parameter("readable_center",center)
