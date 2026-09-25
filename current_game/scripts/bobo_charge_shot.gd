extends "res://scripts/projectile.gd"
var power := 0.0
func _ready() -> void:
    color = Color(0.3,0.85,1.0)
    super._ready()
    add_to_group("bobo_charge_shots")
    _visual.scale = Vector3.ONE * lerpf(0.6,1.2,power)
func payload_damage() -> float: return lerpf(4,14,power)
func _hit_target(target: Node3D) -> void:
    if _try_absorb(target): return
    preload("res://scripts/body_hurtboxes.gd").deliver(target,payload_damage(),Vector3(direction,0.2,0),lerpf(2,5,power),contact_hit,source)
