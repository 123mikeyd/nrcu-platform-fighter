extends SceneTree
const F = preload("res://scripts/fighter.gd")
var failures := 0
var evidence: Array = []
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: " + message)
func _initialize() -> void: call_deferred("run")
func key(code: int, down: bool) -> void:
    var e := InputEventKey.new()
    e.keycode = code
    e.pressed = down
    Input.parse_input_event(e)
    Input.flush_buffered_events()
func step(count: int) -> void:
    for i in count:
        await physics_frame
        await process_frame
func run() -> void:
    var stage := Node3D.new()
    root.add_child(stage)
    var floor := StaticBody3D.new()
    floor.collision_layer = 2
    var collision := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(30, 1, 4)
    collision.shape = box
    floor.position.y = -0.5
    floor.add_child(collision)
    stage.add_child(floor)
    var target = F.new()
    target.character_id = "doge_man"
    target.player_index = 3
    stage.add_child(target)
    var f = F.new()
    f.character_id = "doge_man"
    stage.add_child(f)
    var view = f.get_node("VisualRoot/DogeVisual")
    for face in [1, -1]:
        for delay in [1, 12, 24, 30, 36, 42]:
            for distance in [1.2, 2.0]:
                key(KEY_SPACE, false)
                key(KEY_F, false)
                f.reset_fighter(Vector3.ZERO, true)
                target.reset_fighter(Vector3(face * distance, 0, 0), true)
                f.facing = face
                await step(8)
                key(KEY_SPACE, true)
                await step(1)
                key(KEY_SPACE, false)
                check(view.current_clip == "JumpMoves2", "Space triggers jump")
                await step(delay - 1)
                key(KEY_F, true)
                await step(1)
                key(KEY_F, false)
                var started: bool = f.doge_attack_clip == "SupermanMoves2"
                check(started, "air F selects approved punch delay " + str(delay))
                var trace: Array = []
                var struck_at := -1.0
                var saw_hit := false
                for tick in 40:
                    await step(1)
                    if target.damage_percent > 0 and struck_at < 0: struck_at = f.doge_attack_elapsed
                    saw_hit = saw_hit or target.get_node("VisualRoot/DogeVisual").current_clip == "HitMoves2"
                    trace.append({"tick":tick,"elapsed":f.doge_attack_elapsed,"y":f.position.y,"damage":target.damage_percent,"grounded":f.is_grounded(),"clip":view.current_clip,"struck":f._doge_struck})
                    check(not f._attack_flash.visible, "no flash sphere")
                check(f.doge_attack_clip.is_empty(), "aerial clip ends or cancels on floor")
                check(target.damage_percent in [0.0, 8.0], "at most one unchanged damage packet")
                var expected_hit: bool = delay in [24, 30] or (delay == 1 and distance == 1.2)
                check(target.damage_percent == (8.0 if expected_hit else 0.0), "standing contact/apex miss/late landing cancellation " + str([face,delay,distance]))
                if struck_at >= 0:
                    check(struck_at >= 7.25 / 24.0 - 0.00001, "no damage before visible strike")
                    check(saw_hit, "real contact triggers hit presentation")
                evidence.append({"facing":face,"delay":delay,"separation":distance,"damage":target.damage_percent,"impact_elapsed":struck_at,"trace":trace})
    var contacts := evidence.filter(func(row): return row.damage == 8.0)
    check(contacts.any(func(row): return row.facing == 1), "real jump standing contact right")
    check(contacts.any(func(row): return row.facing == -1), "real jump standing contact left")
    var file := FileAccess.open("res://.verification/evidence/doge_moves2/physics_contacts.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(evidence, "  "))
    print("CONTACT_CASES ", evidence.map(func(row): return [row.facing,row.delay,row.separation,row.damage]))
    stage.queue_free()
    await process_frame
    if failures == 0: print("PASS Doge Moves2 real Space/F gravity standing contacts both facings")
    quit(1 if failures else 0)
