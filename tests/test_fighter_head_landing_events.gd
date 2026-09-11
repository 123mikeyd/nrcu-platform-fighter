extends SceneTree
const F = preload("res://scripts/fighter.gd")
const OUT = "res://.verification/evidence/fighter_head_slide/"
var failures: Array = []
var cases: Array = []
func _initialize(): call_deferred("run")
func step():
    await physics_frame
    await process_frame
func check(ok: bool, message: String):
    if not ok:
        failures.append(message)
        print("FAIL: "+message)
func run():
    for id in ["ggb","doge_man","turbofit"]:
        var world = Node3D.new()
        root.add_child(world)
        var platform = StaticBody3D.new()
        platform.collision_layer = 2
        platform.add_to_group("pass_through_platforms")
        platform.set_meta("top_y",3.0)
        platform.set_meta("half_width",6.0)
        platform.position.y = 2.75
        var c = CollisionShape3D.new()
        var box = BoxShape3D.new()
        box.size = Vector3(12,0.5,5)
        c.shape = box
        platform.add_child(c)
        world.add_child(platform)
        var bottom = F.new()
        bottom.character_id = "probe"
        bottom.player_index = 3
        bottom.team_id = 1
        bottom.position.y = 3.1
        world.add_child(bottom)
        var top = F.new()
        top.character_id = id
        top.player_index = 4
        top.team_id = 1
        top.position = Vector3(4,3.1,0)
        world.add_child(top)
        for i in 20: await step()
        top.reset_fighter(Vector3(0,6.5,0))
        top.jumps_used = 2
        top.recovery_spent = true
        var head = false
        var landed = false
        var checked = false
        var frames_on_head = 0
        for i in 150:
            await step()
            if not head:
                for j in top.get_slide_collision_count():
                    var hit = top.get_slide_collision(j)
                    if hit.get_collider() == bottom and hit.get_normal().y > 0.7:
                        head = true
                if head:
                    if id == "ggb":
                        top.start_special(Vector2.DOWN)
                        check(top.drop_committed and not is_instance_valid(top._ggb_dust),"GGB head down-special is not a landing/impact")
                    elif id == "doge_man":
                        top.torpedo_phase = "fall"
                        top.torpedo_time = 0
                    else:
                        # Production basic routing uses is_grounded; inspect the
                        # same route directly immediately after physical contact.
                        top.basic_attack(Vector2.ZERO,not top.is_grounded())
                        check(top.turbofit_attack_clip == "AirSideKick","head basic stays aerial, never ground-only")
            elif not top.is_grounded() and frames_on_head < 3:
                frames_on_head += 1
                checked = true
                check(top.recovery_spent and top.jumps_used == 2,id+" head does not reset resources")
                if id == "ggb": check(top.drop_committed and not is_instance_valid(top._ggb_dust),"GGB has no head landing dust/damage")
                if id == "doge_man": check(top.torpedo_phase == "fall" and top.landing_lag == 0,"Doge head never starts torpedo landing")
                if id == "turbofit": check(top.turbofit_attack_clip == "AirSideKick","head never cancels aerial kick as landing")
            if head and top.is_grounded():
                landed = true
                check(absf(top.position.y-3.0) < 0.08,"slip lands on real pass-through top")
                check(not top.recovery_spent and top.jumps_used == 0,id+" platform restores resources")
                if id == "ggb": check(not top.drop_committed and is_instance_valid(top._ggb_dust),"GGB real platform starts impact")
                if id == "doge_man": check(top.torpedo_phase == "landing","Doge real platform starts landing")
                break
        check(head and checked and landed,id+" head episode then actual pass-through landing")
        cases.append({"character":id,"head":head,"head_event_checks":checked,"platform_landed":landed})
        world.queue_free()
        await process_frame
    FileAccess.open(OUT+"head_landing_events.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":cases},"  "))
    if failures.is_empty(): print("PASS: no fighter-head landing events; GGB/Doge/Turbo retain air state then land on pass-through")
    quit(0 if failures.is_empty() else 1)
