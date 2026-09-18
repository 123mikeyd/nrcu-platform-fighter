extends "res://scripts/projectile.gd"
# Reuse authoritative swept terrain/body contact and reflect/absorb contracts.
var power := 0.0
func _ready() -> void:
    color = Color(0.3,1,0.38)
    super._ready()
    add_to_group("teknium_charge_shots")
    _visual.scale = Vector3.ONE * lerpf(0.55,1.7,power)
    var ring := MeshInstance3D.new(); var torus := TorusMesh.new()
    torus.inner_radius=0.28; torus.outer_radius=0.34; ring.mesh=torus
    ring.rotation.z=PI/2; ring.scale=Vector3.ONE*lerpf(0.6,1.8,power)
    var mat := StandardMaterial3D.new(); mat.albedo_color=Color(1,0.78,0.18); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    ring.material_override=mat; add_child(ring)
func payload_damage() -> float: return lerpf(5.0,24.0,power)
func _hit_target(target: Node3D) -> void:
    if _try_absorb(target): return
    preload("res://scripts/body_hurtboxes.gd").deliver(target,payload_damage(),Vector3(direction,0.2,0),lerpf(3,8,power),contact_hit,source)
