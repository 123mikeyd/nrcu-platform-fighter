extends SceneTree
var failures := 0
var rows := []
func check(ok, message):
    if not ok: failures += 1; print("FAIL: ", message)
func _initialize(): call_deferred("run")
func run():
    for id in ["witcheer"]:
        for facing in [-1.0, 1.0]:
            var f = load("res://scripts/fighter.gd").new()
            root.add_child(f); f.set_physics_process(false); f.facing = facing
            var v = load("res://scripts/fighter.gd").new(); v.character_id = "ice_mage" if id == "fire_mage" else id
            root.add_child(v); v.set_physics_process(false); v.position = Vector3(1.35*facing,0,0)
            if id == "fire_mage": v.enable_fire_prototype()
            await physics_frame; await process_frame
            f.start_special(Vector2.ZERO)
            var m = f.teknium_magic
            m.tick(0.20); v._update_move_visuals(0)
            check(v.caught_by == m, id+" real collision capture")
            m.tick(4.0/24.0); v._update_move_visuals(0)
            check(v.electrocution_presentation.active_visual != null, id+" hold reaction installed")
            for i in 5: m.tick(0.25); v._update_move_visuals(0)
            check(v.damage_percent == 10 and m.tick_count == 5 and m.phase == "ending", id+" five ticks ten damage")
            rows.append({"id":id,"facing":facing,"ticks":m.tick_count,"damage":v.damage_percent})
            m.tick(5.0/24.0)
            check(v.caught_by == null and v.electrocution_presentation.active_visual == null, id+" release clears")
            var visual = v.get_node("VisualRoot/WitcheerVisual")
            # Release resumes AnimationPlayer before the next grounded visual tick.
            visual.sync_pose(true, Vector3(7,0,0), false, false, facing)
            check(visual.animation_player.assigned_animation == "Run" and visual.animation_player.is_playing(), "grounded Run replaces resumed reaction")
            f.queue_free(); v.queue_free(); await process_frame
    var file = FileAccess.open("res://.verification/evidence/witcheer_electrocution/coverage_runtime.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(rows,"  ")); file.close()
    if failures == 0: print("PASS: roster electrocution real capture both facings, unchanged budgets and release")
    quit(0 if failures == 0 else 1)
