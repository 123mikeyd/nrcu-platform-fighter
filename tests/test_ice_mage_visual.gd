extends SceneTree
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> bool:
    if not ok:
        push_error("FAIL: " + message)
        quit(1)
    return ok
func run():
    var roster = load("res://scripts/roster.gd")
    var config = load("res://scripts/match_config.gd")
    if not check(roster.ids()==["teknium","doge_man","ggb","turbofit","ice_mage", "witcheer", "mephisto"],"seven-character roster preserves original order"): return
    if not check(roster.display_name("ice_mage")=="Ice Mage" and "ice_mage" in config.CHARACTERS,"Ice Mage setup identity"): return
    var slots = config.default_slots()
    slots[0].character="ice_mage"
    if not check(config.validate(slots,false)=="","Ice Mage accepted in four-player match"): return
    var fighter = load("res://scripts/fighter.gd").new()
    fighter.character_id="ice_mage"
    root.add_child(fighter)
    fighter.set_physics_process(false)
    var visual = fighter.get_node_or_null("VisualRoot/IceMageVisual")
    if not check(visual!=null,"rigged Ice Mage replaces placeholder"): return
    if not check(fighter._visual_root.get_child_count()==1,"one visual, no duplicate primitives"): return
    for state in [[true,Vector3.ZERO,"Idle"],[true,Vector3(2,0,0),"Walk"],[true,Vector3(7.5,0,0),"Run"],[false,Vector3(7.5,-2,0),"Idle"]]:
        visual.sync_pose(state[0],state[1],false,false,"",1.0,0.0)
        if not check(visual.current_clip==state[2],"locomotion "+state[2]): return
    if not check(visual.fallback_label=="Airborne: Idle fallback","honest missing airborne animation label"): return
    fighter.facing=-1
    fighter._visual_root.scale.x=-1
    fighter._update_move_visuals()
    if not check(fighter._visual_root.scale==Vector3.ONE and visual.model.rotation.y<0,"yaw not mirrored skeleton"): return
    var pos=fighter.position
    visual.animation_player.advance(0.2)
    if not check(fighter.position==pos and fighter.damage_percent==0,"presentation does not own collision or damage"): return
    var other=load("res://scripts/ice_mage_visual.gd").new()
    root.add_child(other)
    var m1=visual.model.find_children("*","MeshInstance3D",true,false)[0].get_active_material(0)
    var m2=other.model.find_children("*","MeshInstance3D",true,false)[0].get_active_material(0)
    if not check(m1!=m2 and not m1.emission_enabled and m1.albedo_color==Color.WHITE,"isolated original skin, no tint or eye glow"): return
    for clip in ["Idle","Walk","Run"]:
        if not check(visual.animation_player.get_animation(clip).loop_mode==Animation.LOOP_LINEAR,"loop "+clip): return
    fighter.queue_free()
    other.queue_free()
    print("PASS: Ice Mage fifth roster, original four preserved, setup support, Idle Walk Run, honest fallback and isolated yaw/material presentation")
    quit(0)
