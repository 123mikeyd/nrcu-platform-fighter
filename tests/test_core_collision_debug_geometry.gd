extends "res://tests/test_core_collision_debug.gd"
func run() -> void:
    var overlay = load("res://scripts/tools/collision_debug_overlay.gd").new()
    root.add_child(overlay)
    check(overlay.has_method("world_lines"), "live resource wireframe API exists")
    if not overlay.has_method("world_lines"):
        overlay.free()
        quit(1)
        return
    var body := StaticBody3D.new()
    root.add_child(body)
    var node := CollisionShape3D.new()
    body.add_child(node)
    for shape in [BoxShape3D.new(), SphereShape3D.new(), CapsuleShape3D.new(), CylinderShape3D.new()]:
        node.shape = shape
        if shape is BoxShape3D: shape.size = Vector3(2, 4, 6)
        else:
            shape.radius = .7
            if not shape is SphereShape3D: shape.height = 3.4
        node.transform = Transform3D.IDENTITY
        var local: PackedVector3Array = overlay.world_lines(node)
        check(local.size() > 0 and local.size() % 2 == 0, "paired primitive lines")
        if shape is CapsuleShape3D:
            var stem: float = shape.height * .5 - shape.radius
            for i in range(0, local.size(), 2):
                var a: Vector3 = local[i]
                var b: Vector3 = local[i + 1]
                if a.y * b.y < 0:
                    check(is_equal_approx(a.x, b.x) and is_equal_approx(a.z, b.z) and is_equal_approx(absf(a.y), stem) and is_equal_approx(absf(b.y), stem), "capsule has straight stems, never diagonal hemisphere bridge")
        var bounds := AABB(local[0], Vector3.ZERO)
        for point in local: bounds = bounds.expand(point)
        var expected := Vector3(2, 4, 6) if shape is BoxShape3D else Vector3(1.4, 1.4 if shape is SphereShape3D else 3.4, 1.4)
        check(bounds.size.is_equal_approx(expected), "resource dimensions include exact cardinal extrema: " + shape.get_class())
        body.transform = Transform3D(Basis.from_euler(Vector3(.3, .7, -.4)).scaled(Vector3(2, .8, 1.4)), Vector3(5, -2, 3))
        node.position = Vector3(.2, 1.2, -.4)
        var world: PackedVector3Array = overlay.world_lines(node)
        for i in local.size(): check(world[i].is_equal_approx(node.global_transform * local[i]), "complete global transform")
        body.transform = Transform3D.IDENTITY
    body.free()
    overlay.free()
    if failures == 0: print("PASS: collision debug exact primitive dimensions and transformed vertices")
    quit(1 if failures else 0)
