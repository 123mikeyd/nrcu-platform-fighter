extends SceneTree

const TEXTURE := "res://assets/kainan/detail_crop_screen_01m00s.png"
const SHA256 := "1209d98bfb15d040acef23b77ef4b2bfab8dca6333f626a1ea3db1768850cd25"
var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, message: String):
    if not ok:
        failures += 1
        printerr("FAIL: " + message)

func inspect_static(node: Node):
    check(not node is CollisionObject3D and not node is CollisionShape3D, "terminal has no collision/areas")
    check(not node is Light3D and not node is AnimationPlayer and not node is Timer, "no lighting spill, animation or flashing timers")
    check(not node.is_processing() and not node.is_physics_processing(), "terminal has no time-driven behavior")
    for child in node.get_children(): inspect_static(child)

func run():
    root.size = Vector2i(1280, 720)
    var arena = load("res://scenes/main.tscn").instantiate()
    root.add_child(arena)
    await process_frame
    var terminal = arena.get_node_or_null("KainanTerminal")
    check(terminal != null, "approved static Kainan terminal exists in actual arena")
    if terminal != null:
        inspect_static(terminal)
        check(terminal.position.is_equal_approx(Vector3(0, 3.1, -4.90)), "measured wall placement behind combat plane")
        check(arena.find_children("KainanTerminal", "", true, false).size() == 1, "one cameo only")
        check(FileAccess.get_sha256(TEXTURE) == SHA256, "runtime image is byte-identical whole approved crop")
        var screen = terminal.get_node("ReferenceScreen")
        check(screen.global_position.z > -4.725, "entire source clears existing horizontal wall rail face")
        var material = screen.material_override
        check(material.albedo_texture.get_size() == Vector2(600, 685), "original image dimensions preserved")
        check(material.albedo_texture.resource_path == TEXTURE, "approved reference displayed directly")
        check(is_equal_approx(screen.mesh.size.x / screen.mesh.size.y, 600.0 / 685.0), "whole-image aspect ratio, no stretch/crop")
        check(material.uv1_scale == Vector3.ONE and material.uv1_offset == Vector3.ZERO, "full image UVs")
        check(material.emission_enabled and material.emission_energy_multiplier <= 0.3, "modest constant self emission")
        check(material.emission_texture == material.albedo_texture, "glow follows source, no invented emblem")
        check(not material.no_depth_test, "fighters occlude terminal normally")
        var camera = root.get_camera_3d()
        var a: Vector2 = camera.unproject_position(screen.to_global(Vector3(-screen.mesh.size.x / 2, screen.mesh.size.y / 2, 0)))
        var b: Vector2 = camera.unproject_position(screen.to_global(Vector3(screen.mesh.size.x / 2, -screen.mesh.size.y / 2, 0)))
        print("SCREEN_PIXEL_BOUNDS ", a, " -> ", b, " size ", b-a)
        check(b.x-a.x >= 50 and b.x-a.x <= 85 and b.y-a.y >= 55 and b.y-a.y <= 95, "small readable terminal, not billboard")
        for child in terminal.get_children():
            if child is MeshInstance3D:
                check(child.global_position.z + child.get_aabb().end.z < -4.5, "all terminal surfaces safely behind platform depths")
        var before: float = material.emission_energy_multiplier
        for i in 10: await process_frame
        check(material.emission_energy_multiplier == before, "emission remains constant")
    check(arena.get_node("MainPlatform").position == Vector3(0, -0.55, 0), "main combat platform unchanged")
    check(get_nodes_in_group("pass_through_platforms").size() == 3, "all three upper platforms retained")
    arena.queue_free()
    await process_frame
    if failures == 0: print("PASS: Kainan whole-source static nonblocking wall terminal")
    quit(1 if failures else 0)
