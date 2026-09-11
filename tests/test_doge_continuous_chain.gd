extends SceneTree
const F = preload("res://scripts/fighter.gd")
var fails := 0
func check(ok, msg):
    if not ok:
        fails += 1
        printerr("FAIL: ",msg)
func _initialize(): call_deferred("run")
func run():
    var f = F.new()
    f.character_id = "doge_man"
    root.add_child(f)
    f.set_physics_process(false)
    f._start_doge_attack("Punch4",Vector2.ZERO)
    f._tick_doge_attack(0.2)
    f.basic_attack(Vector2.ZERO,false)
    f._tick_doge_attack(0.35)
    check(f.doge_attack_clip == "Punch1","Punch4 buffers cyclic Punch1")
    f._cancel_doge_attack()
    f.basic_attack(Vector2.ZERO,false)
    f._tick_doge_attack(0.2)
    f.basic_attack(Vector2.DOWN,false)
    f._tick_doge_attack(0.18)
    check(f.doge_attack_clip == "TysonTwoPiece","down branch at next safe link")
    f._cancel_doge_attack()
    f.basic_attack(Vector2.DOWN,false)
    f._tick_doge_attack(0.18)
    f.basic_attack(Vector2.ZERO,false)
    check(f.doge_tyson_followup,"anticipatory fresh F reserves right")
    f._tick_doge_attack(0.5)
    f.basic_attack(Vector2.ZERO,false)
    f._tick_doge_attack(0.33)
    check(f.doge_attack_clip == "Punch1","Tyson right links original Punch1")
    f.queue_free()
    await process_frame
    if fails == 0: print("PASS continuous branches")
    quit(1 if fails else 0)
