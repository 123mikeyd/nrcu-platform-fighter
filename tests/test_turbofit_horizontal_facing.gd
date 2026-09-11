extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(view, expected: float, label: String) -> void:
    if not is_equal_approx(view.model.rotation.y, expected * PI / 2):
        failures += 1
        print("FAIL ",label)
func run() -> void:
    var f = F.new()
    f.character_id = "turbofit"
    root.add_child(f)
    await process_frame
    f.set_physics_process(false)
    var v = f._visual_root.get_node("TurboFitVisual")
    for face in [1.0,-1.0]:
        f.facing = -face
        f.swing_direction = Vector3(face,0,0)
        f.last_move = "GUITAR SWING"
        f.attack_cooldown = 0.5
        f._update_move_visuals()
        check(v,face,"committed strike")
        f.attack_cooldown = 0
        f._update_move_visuals()
        check(v,-face,"cooldown restores current facing")
        f.attack_cooldown = 0.5
        f._update_move_visuals(0,true)
        check(v,-face,"interrupted")
        f.shielding = true
        f._update_move_visuals()
        check(v,-face,"shield")
        f.shielding = false
        f.swing_direction = Vector3.UP
        f._update_move_visuals()
        check(v,-face,"backhand excluded")
        f.swing_direction = Vector3(-face,0,0)
        f._update_move_visuals()
        check(v,-face,"new attack aim")
        for move in ["", "POWER CHORD", "SOUND WAVE", "RISING CHORD", "SOUND ORB"]:
            v.sync_pose(true,Vector3(face*2,0,0),false,false,move,Vector3(face,0,0),-face,0)
            check(v,-face,"unrelated "+move)
        v.sync_pose(false,Vector3.ZERO,false,false,"AIR SIDE KICK",Vector3(face,0,0),-face,0,"AirSideKick",0.17,0.25)
        check(v,-face,"air kick existing facing")
    print("PASS TurboFit horizontal facing lifecycle" if failures == 0 else "FAIL facing lifecycle")
    quit(0 if failures == 0 else 1)
