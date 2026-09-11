extends SceneTree

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> bool:
    if not value:
        push_error("FAIL: " + message)
        quit(1)
    return value
func run() -> void:
    var fighter = load("res://scripts/fighter.gd").new()
    fighter.character_id = "teknium"
    root.add_child(fighter)
    fighter.set_physics_process(false)
    var visual = fighter.get_node_or_null("VisualRoot/TekniumVisual")
    if not check(visual != null, "Teknium imported presentation replaces placeholder"): return
    if not check(fighter.get_node("VisualRoot").get_child_count() == 1, "no duplicate primitive staff/body/head"): return
    for state in [[true, Vector3.ZERO, false, false, "", "Idle"], [true,Vector3(2,0,0),false,false,"","Walk"], [true,Vector3(7.5,0,0),false,false,"","Run"], [true,Vector3.ZERO,false,true,"","Block"], [true,Vector3.ZERO,true,false,"PROJECTILE","Hit"], [true,Vector3.ZERO,false,false,"PROJECTILE","Projectile"], [true,Vector3.ZERO,false,false,"CHARGE RELEASE","MageSpell"], [true,Vector3.ZERO,false,false,"RISING STRIKE","RaiseWall"], [true,Vector3.ZERO,false,false,"SIDE STRIKE","Punch"], [true,Vector3.ZERO,false,false,"LOW SWEEP","Kick"]]:
        visual.sync_pose(state[0],state[1],state[2],state[3],state[4],1.0,0.0)
        if not check(visual.current_clip == state[5], "state mapping " + str(state[5])): return
    fighter.facing = -1.0
    fighter.velocity = Vector3(-7.5,0,0)
    fighter._visual_root.scale.x = -1
    fighter._update_move_visuals()
    if not check(fighter._visual_root.scale == Vector3.ONE and visual.model.rotation.y < 0, "yaw facing, never mirror skeleton"): return
    var before: Vector3 = fighter.position
    visual.animation_player.advance(0.3)
    if not check(fighter.position == before and fighter.damage_percent == 0 and fighter.stocks == 3, "presentation cannot translate or damage fighter"): return
    var second = load("res://scripts/teknium_visual.gd").new()
    root.add_child(second)
    var m1 = visual.model.find_children("*","MeshInstance3D",true,false)[0].get_active_material(0)
    var m2 = second.model.find_children("*","MeshInstance3D",true,false)[0].get_active_material(0)
    if not check(m1 != m2 and not m1.emission_enabled and m1.albedo_texture != null, "per-instance texture materials without eye glow"): return
    for clip in ["Idle","Walk","Run","Block"]:
        if not check(visual.animation_player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "loop " + clip): return
    print("PASS: Teknium integrated states, locomotion, yaw, isolated materials and gameplay separation")
    fighter.queue_free()
    second.queue_free()
    quit(0)
