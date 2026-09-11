extends SceneTree
const F = preload("res://scripts/fighter.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var f = F.new()
    f.character_id = "doge_man"
    root.add_child(f)
    f.set_physics_process(false)
    var player = f.get_node("VisualRoot/DogeVisual").animation_player
    var ok: bool = player.has_animation("GroundCharge") and player.has_animation("GroundRush")
    if not ok: printerr("FAIL approved ground charge and tackle clips missing")
    f.queue_free()
    await process_frame
    if ok: print("PASS approved grounded rush animation presence")
    quit(0 if ok else 1)
