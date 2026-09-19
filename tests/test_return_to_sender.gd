extends SceneTree
var failures := 0
var checks := 0
func check(value: bool, label: String):
    checks += 1
    if not value:
        failures += 1
        print("FAIL: "+label)
func _initialize(): call_deferred("run")
func run():
    var f = load("res://scripts/fighter.gd").new()
    f.character_id = "test_placeholder"
    root.add_child(f)
    f.set_physics_process(false)
    f.spawn_position = Vector3(-3, 1, 0)
    f.global_position = Vector3(0,-9,0)
    f._handle_blast_zone()
    check(f.stocks == 2, "stock spent once")
    check(f.global_position.y > 2.0, "revival arrives above spawn instead of instant floor warp")
    check(f.has_method("is_revival_protected") and f.call("is_revival_protected"), "revival starts protected")
    check(f.revival.has_method("tick"), "revival has bounded arrival and departure lifecycle")
    if f.revival.has_method("tick"):
        f.revival.tick(0.30, f.read_controls(0))
        check(f.revival.phase == "waiting", "portal deposits fighter onto platform")
        check(f.is_grounded(), "owner stands grounded for idle presentation on waiting platform")
        check(f.revival.get_node_or_null("Platform") != null, "shared platform visible")
        check(f.revival.label.font_size*f.revival.label.pixel_size >= 0.3, "departure hint remains legible at stage camera distance")
        check(f.revival.aura.material_override.albedo_color.a >= 0.2, "protection silhouette has clear initial contrast")
        var input = f.read_controls(0)
        input.right = true
        f.revival.tick(0.1, input)
        check(f.revival.phase == "waiting", "minimum orientation hold cannot be skipped")
        f.revival.tick(0.4, input)
        check(f.revival.phase == "idle", "movement leaves after orientation")
        check(f.is_revival_protected(), "departure retains protection")
        f.revival.tick(1.3, f.read_controls(0))
        check(not f.is_revival_protected(), "protection expires")
    f._handle_blast_zone()
    f.receive_hit(15, Vector3.RIGHT, 4)
    f.apply_status_damage(5)
    check(f.damage_percent == 0 and f.velocity == Vector3.ZERO, "revival rejects direct hits and status damage")
    var enemy = load("res://scripts/fighter.gd").new()
    enemy.character_id = "test_placeholder"
    root.add_child(enemy)
    enemy.set_physics_process(false)
    check(not enemy.can_hit(f), "shared eligibility rejects grab/melee/projectile targets")
    check(not f.apply_freeze(enemy) and not f.apply_burn(enemy), "revival rejects freeze and burn")
    f.receive_contact_hit(10, Vector3.RIGHT, 4, f.global_position)
    check(f.damage_percent == 0, "contact reception cannot bypass revival")
    f.hitstun = 0
    f.basic_attack(Vector2.RIGHT, true)
    check(f.last_move == "", "orientation rejects attack API")
    f.revival.tick(0.3, f.read_controls(0))
    f.revival.tick(2.4, f.read_controls(0))
    f.basic_attack(Vector2.RIGHT, true)
    check(not f.is_revival_protected(), "basic ends departure protection before attack")
    f._begin_revival()
    f.revival.tick(0.3, f.read_controls(0))
    f.revival.tick(2.4, f.read_controls(0))
    f.start_special(Vector2.UP)
    check(not f.is_revival_protected(), "special ends departure protection before attack")
    f._begin_revival()
    check(not f.try_jump(), "direct jump cannot skip arrival")
    f.reset_fighter(Vector3(2,1,0), true)
    check(not f.is_revival_protected() and not f.revival.platform.visible, "reset clears platform and protection")
    check(f.global_position == Vector3(2,1,0) and f.stocks == 3, "initial/reset spawn semantics retained")
    f._handle_blast_zone()
    f.controls_enabled = false
    check(not f.is_revival_protected() and not f.revival.aura.visible, "results/menu disable cleans synchronously")
    f.controls_enabled = true
    f.stocks = 1
    f._handle_blast_zone()
    check(f.stocks == 0 and not f.visible and not f.is_revival_protected(), "final stock never revives")
    f.reset_fighter(Vector3(-3,1,0), true)
    var floor_body := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(20,1,4)
    shape.shape = box
    floor_body.add_child(shape)
    floor_body.position.y = 3.0
    root.add_child(floor_body)
    await physics_frame
    await process_frame
    f._handle_blast_zone()
    check(f.revival.anchor.y > 4.5 and f.revival.anchor.y <= 5.5, "placement clears actual raised surface and stays camera safe")
    enemy.spawn_position = f.spawn_position
    enemy._handle_blast_zone()
    check(absf(enemy.revival.anchor.x-f.revival.anchor.x) >= 2.1, "simultaneous respawns reserve separate platforms")
    check(f.revival.find_children("*", "CollisionObject3D").is_empty(), "owned platform cannot become opponent terrain")
    check(f.collision_layer == 0 and f.collision_mask == 0, "arriving fighter cannot be used as extra terrain")
    var original_layer: int = f._active_collision_layer
    f.revival.tick(0.3, f.read_controls(0))
    f.revival.tick(2.4, f.read_controls(0))
    check(f.collision_layer == original_layer and f.collision_mask == f._active_collision_mask, "departure restores native collision")
    f.control_type = "bot"
    f._bot.read(f, 0)
    f._bot.timer = 0.1
    f._physics_process(1.0/60)
    check(is_equal_approx(f._bot.timer, 0.1-1.0/60), "bot input clock advances once per callback after revival")
    floor_body.free()
    enemy.free()
    f.free()
    print("RETURN_TO_SENDER_COMPLETE checks=%d failures=%d" % [checks,failures])
    quit(1 if failures else 0)
