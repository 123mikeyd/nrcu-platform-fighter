extends SceneTree
var failures := 0
func check(ok, message):
    if not ok: failures += 1; print("FAIL: ",message)
func _initialize(): call_deferred("run")
func run():
    var f = load("res://scripts/fighter.gd").new()
    root.add_child(f);f.set_physics_process(false)
    f.start_special(Vector2.RIGHT)
    check(get_nodes_in_group("projectiles").is_empty(),"force must not spawn on button press")
    var magic = f.get_node_or_null("TekniumMagic")
    check(magic != null,"isolated magic clock exists")
    if magic != null:
        magic.tick(0.249)
        check(get_nodes_in_group("projectiles").is_empty(),"no shot before source46")
        magic.tick(0.001)
        var shots = get_nodes_in_group("projectiles")
        check(shots.size()==1,"one shot source46")
        if shots.size()==1:
            shots[0].set_physics_process(false)
            check(shots[0].global_position.distance_to(f.get_node("VisualRoot/TekniumVisual").hand_tip("RightHand"))<0.001,"shot at evaluated right hand tip")
        magic.tick(18.0/24.0)
        check(magic.phase=="idle","force completes source64")
    f.queue_free()
    for shot in get_nodes_in_group("projectiles"):shot.queue_free()
    await process_frame
    if failures==0:print("PASS: force delayed hand spawn and complete source timing")
    quit(0 if failures==0 else 1)
