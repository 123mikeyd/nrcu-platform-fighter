extends Node
# Installed v003 Tyson: 0..60 at 60fps. No source asset edits.
# Provisional balance: .12 startup, .30 defense, .30 whiff recovery;
# triggered hook .18 startup + .10 pressure + .37 recovery, incoming *1.5.
const ACTIVE_START := 0.12
const ACTIVE_END := 0.42
const WHIFF_END := 0.72
const HOOK_START := 0.18
const HOOK_END := 0.28
const HOOK_TOTAL := 0.65
const MULTIPLIER := 1.5
const REACH := 3.1
var actor
var phase := "idle"
var elapsed := 0.0
var locked_facing := 1.0
var incoming := 0.0
var targets: Array = []
var pressure: MeshInstance3D
var flash: StandardMaterial3D
var meshes: Array = []
var whoosh_count := 0
var impact_count := 0
func _ready():
    actor = get_parent()
    flash = StandardMaterial3D.new()
    flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    flash.albedo_color = Color(0.7,0.9,1,0.22)
    for mesh in actor._visual_root.get_node("DogeVisual").model.find_children("*","MeshInstance3D",true,false):
        meshes.append([mesh,mesh.material_overlay])
    pressure = MeshInstance3D.new()
    pressure.name = "CounterPressureCrescent"
    var geometry := ImmediateMesh.new()
    geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in 32:
        var a := lerpf(-PI/2,PI/2,float(i)/32)
        var b := lerpf(-PI/2,PI/2,float(i+1)/32)
        var outer_a := Vector3(0.65+2.45*cos(a),1.25+0.85*sin(a),0.15)
        var outer_b := Vector3(0.65+2.45*cos(b),1.25+0.85*sin(b),0.15)
        var inner_a := outer_a-Vector3(0.18,0,0)
        var inner_b := outer_b-Vector3(0.18,0,0)
        for vertex in [outer_a,inner_a,outer_b,outer_b,inner_a,inner_b]: geometry.surface_add_vertex(vertex)
    geometry.surface_end()
    pressure.mesh = geometry
    var material := StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.albedo_color = Color(0.78,0.93,1,0.65)
    pressure.material_override = material
    actor.add_child(pressure)
    pressure.hide()
func start():
    if phase != "idle" or not actor.controls_enabled or actor.stocks <= 0 or actor.hitstun > 0 or actor.freeze_remaining > 0 or actor.magic_locked() or actor.shielding: return
    phase = "stance"; elapsed = 0; incoming = 0; targets.clear()
    locked_facing = actor.facing
    actor.velocity.x = 0
    actor.attack_cooldown = WHIFF_END
    actor.last_move = "TYSON COUNTER"
func active() -> bool:
    return phase == "stance" and elapsed >= ACTIVE_START and elapsed < ACTIVE_END and actor.controls_enabled and actor.stocks > 0 and actor.hitstun <= 0 and actor.freeze_remaining <= 0 and not actor.magic_locked() and not actor.shielding
func intercept(amount: float, source: Node) -> bool:
    if amount <= 0 or not active(): return false
    if is_instance_valid(source) and (not source.controls_enabled or not source.can_hit(actor)): return false
    incoming = amount
    phase = "hook"; elapsed = 0
    actor.attack_cooldown = HOOK_TOTAL
    actor.last_move = "COUNTER HOOK"
    whoosh_count += 1
    sound(false)
    present()
    return true
func cancel():
    phase = "idle"; elapsed = 0; incoming = 0; targets.clear()
    if is_instance_valid(pressure): pressure.hide()
    for pair in meshes:
        if is_instance_valid(pair[0]): pair[0].material_overlay = pair[1]
func tick(delta: float):
    if phase == "idle": return
    if not actor.controls_enabled or actor.stocks <= 0 or actor.hitstun > 0 or actor.freeze_remaining > 0 or actor.magic_locked():
        cancel(); return
    actor.facing = locked_facing
    actor.velocity.x = 0
    var previous := elapsed
    elapsed += delta
    if phase == "hook" and previous < HOOK_END and elapsed >= HOOK_START:
        strike()
    if elapsed >= (WHIFF_END if phase == "stance" else HOOK_TOTAL): cancel()
func strike():
    # Short attached pressure volume, not a projectile or attacker teleport.
    var query := PhysicsShapeQueryParameters3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(REACH-0.4,1.7,0.9)
    query.shape = box
    query.transform.origin = actor.global_position + Vector3(locked_facing*(REACH+0.4)/2,1.25,0)
    query.collision_mask = 7
    query.exclude = [actor.get_rid()]
    preload("res://scripts/body_hurtboxes.gd").prepare(actor,query)
    for hit in actor.get_world_3d().direct_space_state.intersect_shape(query,64):
        var target = preload("res://scripts/body_hurtboxes.gd").resolve(hit.collider)
        if not actor.can_hit(target) or target in targets: continue
        var ray := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*1.25,target.global_position+Vector3.UP,3)
        var excluded: Array[RID] = []
        for fighter in get_tree().get_nodes_in_group("fighters"):
            excluded.append(fighter.get_rid())
        ray.exclude = excluded
        if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
        targets.append(target)
        var before: float = target.damage_percent
        var blocked: bool = target.shielding
        target.receive_hit_from(incoming*MULTIPLIER,Vector3(locked_facing,0.38,0),7.0,actor)
        if not blocked and target.damage_percent > before:
            actor.begin_counter_hitstop(0.065)
            target.begin_counter_hitstop(0.065)
            impact_count += 1
            sound(true)
func source_time() -> float:
    if phase == "stance":
        if elapsed < ACTIVE_START: return lerpf(0,0.25,elapsed/ACTIVE_START)
        if elapsed < ACTIVE_END: return 0.25
        return lerpf(0.25,0,clampf((elapsed-ACTIVE_END)/(WHIFF_END-ACTIVE_END),0,1))
    return lerpf(0.25,0.45,clampf(elapsed/HOOK_START,0,1)) if elapsed < HOOK_START else lerpf(0.45,1,clampf((elapsed-HOOK_START)/(HOOK_TOTAL-HOOK_START),0,1))
func present():
    if phase == "idle": return
    var view = actor._visual_root.get_node("DogeVisual")
    view.tyson_followup = true
    view.sync_pose("idle",locked_facing,0.4,0.42,0.18,0.6,actor.is_grounded(),actor.velocity,false,0,"TysonTwoPiece",source_time(),1.0)
    flash.albedo_color.a = 0.10+0.16*(0.5+0.5*sin(elapsed*TAU*9))
    for pair in meshes: pair[0].material_overlay = flash if active() else pair[1]
    pressure.visible = phase == "hook" and elapsed >= HOOK_START and elapsed < HOOK_END
    pressure.scale.x = locked_facing
func sound(impact: bool):
    # Original synthesized pressure/noise; no external/licensing dependency.
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = 22050
    var duration := 0.20 if impact else 0.14
    var samples := int(duration*stream.mix_rate)
    var data := PackedByteArray(); data.resize(samples*2)
    var rng := RandomNumberGenerator.new(); rng.seed = 812 if impact else 194
    for i in samples:
        var t := float(i)/stream.mix_rate
        var envelope := pow(1-float(i)/samples,2)
        var wave := (rng.randf_range(-1,1)*0.40 + sin(TAU*(70 if impact else 430)*t)*0.60) if impact else rng.randf_range(-1,1)*sin(PI*float(i)/samples)
        data.encode_s16(i*2,int(wave*envelope*24000))
    stream.data = data
    var player := AudioStreamPlayer3D.new()
    player.stream = stream; player.volume_db = -3 if impact else -8
    actor.add_child(player); player.finished.connect(player.queue_free); player.play()
