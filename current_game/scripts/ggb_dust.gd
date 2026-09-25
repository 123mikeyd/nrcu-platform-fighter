extends Node3D
# Compact floor-local dust; never a body flash or stage-wide effect.
var elapsed:=0.0
const DURATION:=0.42
var puffs:Array[MeshInstance3D]=[]
func _ready():
    for i in 8:
        var puff=MeshInstance3D.new()
        var sphere=SphereMesh.new()
        sphere.radius=0.14
        sphere.height=0.20
        sphere.radial_segments=8
        sphere.rings=4
        puff.mesh=sphere
        var mat=StandardMaterial3D.new()
        mat.albedo_color=Color(0.48,0.43,0.33,0.55)
        mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.roughness=1.0
        mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
        puff.material_override=mat
        add_child(puff)
        puffs.append(puff)
    _process(0)
func _process(delta):
    elapsed+=delta
    if elapsed>=DURATION:
        queue_free()
        return
    var t=elapsed/DURATION
    for i in puffs.size():
        var angle=TAU*i/puffs.size()
        puffs[i].position=Vector3(cos(angle)*(0.78+t*0.55),0.08+sin(t*PI)*0.18,sin(angle)*(0.65+t*0.35))
        puffs[i].scale=Vector3.ONE*(1+t*0.8)
        puffs[i].material_override.albedo_color.a=0.55*(1-t)
