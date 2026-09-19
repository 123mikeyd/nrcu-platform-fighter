extends "res://tests/test_core_combat_lab.gd"

const Stage = preload("res://scripts/core/stage/combat_lab_stage.gd")
const MARGIN := 12.0

func run() -> void:
    for viewport_size in [Vector2i(1280, 720), Vector2i(960, 540)]:
        var viewport := SubViewport.new()
        viewport.size = viewport_size
        viewport.own_world_3d = true
        root.add_child(viewport)
        var lab = load("res://scenes/combat_lab.tscn").instantiate()
        viewport.add_child(lab)
        lab.set_physics_process(false)
        var camera: Camera3D = viewport.get_camera_3d()
        for stocks in [false, true]:
            if stocks: lab.start_stock_match()
            else: lab.set_ledges_enabled(true)
            for i in range(4): await process_frame
            var panels = lab.find_children("*", "PanelContainer", true, false).filter(func(panel): return panel.get_parent() is CanvasLayer)
            var safe := Rect2(MARGIN, panels[0].get_global_rect().end.y + MARGIN,
                viewport_size.x - 2 * MARGIN, 0)
            safe.size.y = panels[1].get_global_rect().position.y - MARGIN - safe.position.y
            print("SAFE %s stocks=%s %s camera size=%s position=%s" % [viewport_size, stocks, safe, camera.size, camera.position])
            var collider: CollisionShape3D = lab.actors[0].get_node("CoreCapsule")
            var capsule: CapsuleShape3D = collider.shape
            # Project a conservative box enclosing the actual full 3D capsule,
            # including both ends, width and depth (not just the foot origin).
            for anchor in Stage.new().create_anchors():
                var route := [anchor.hang(), Vector3(anchor.hang().x, anchor.climb().y, anchor.hang().z), anchor.climb()]
                for origin in route:
                    var bounds := Rect2(camera.unproject_position(origin), Vector2.ZERO)
                    for x in [-capsule.radius, capsule.radius]:
                        for y in [-capsule.height / 2, capsule.height / 2]:
                            for z in [-capsule.radius, capsule.radius]:
                                var projected := camera.unproject_position(origin + collider.position + Vector3(x, y, z))
                                bounds = bounds.expand(projected)
                                check(safe.has_point(projected), "%s %s route %s full capsule %s clears HUD+12px" % [viewport_size, anchor.anchor_id, origin, projected])
                    print("PROJECTION %s %s origin=%s capsule=%s" % [viewport_size, anchor.anchor_id, origin, bounds])
            var feet := camera.unproject_position(Vector3.ZERO)
            var head := camera.unproject_position(Vector3(0, capsule.height, 0))
            check(safe.has_point(feet) and safe.has_point(head), "center stage remains usable")
            check(feet.y - head.y >= viewport_size.y * .11, "fighters retain readable height, no distant zoom")
        lab.enter_sandbox()
        lab.set_ledges_enabled(false)
        for i in range(3): await process_frame
        check(camera.size == 14 and camera.position == Vector3(0, 6, 28), "opt-out restores accepted non-ledge framing")
        lab.free()
        viewport.free()
    if failures == 0: print("PASS: ledge camera full capsules and climb routes clear HUD at both resolutions")
    quit(1 if failures else 0)
