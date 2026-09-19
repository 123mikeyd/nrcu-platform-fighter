extends Node3D
## Read-only body/terrain diagnostic, never an attack-query visualization.
const SEGMENTS := 32
const FIGHTER_COLOR := Color(0.0, 1.0, 1.0)
const TERRAIN_COLOR := Color(0.3, 1.0, 0.3)
const TOP_SUPPORT_COLOR := Color(1.0, 0.45, 0.08) # Orange: physical one-way segment, not hurtboxes.
var entries: Dictionary = {}
var lines: MeshInstance3D
var line_mesh := ImmediateMesh.new()

func _ready() -> void:
    lines = MeshInstance3D.new()
    lines.name = "BodyTerrainLines"
    lines.mesh = line_mesh
    lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.vertex_color_use_as_albedo = true
    material.no_depth_test = true
    material.render_priority = 127
    lines.material_override = material
    add_child(lines)
    # Last render boundary reads final live poses, including scene-tree pause.
    RenderingServer.frame_pre_draw.connect(refresh)

func _exit_tree() -> void:
    if RenderingServer.frame_pre_draw.is_connected(refresh): RenderingServer.frame_pre_draw.disconnect(refresh)

func refresh() -> void:
    if not is_instance_valid(lines): return
    if not visible:
        entries.clear()
        line_mesh.clear_surfaces()
        return
    var next: Dictionary = {}
    var lab := get_parent()
    for node in lab.find_children("*", "CollisionShape3D", true, false):
        var body = node.get_parent()
        if not body is PhysicsBody3D or node.disabled or node.shape == null: continue
        var fighter: bool = body.is_in_group("core_fighters")
        var membership: int = 2 if fighter else 1
        if (body.collision_layer & membership) == 0: continue
        if not fighter and not body is StaticBody3D: continue
        if fighter and lab.get("simulation") != null:
            var participating := true
            for state in lab.simulation.fighters.values():
                if state.actor == body: participating = state.enabled and not state.eliminated
            if not participating: continue
        var points := world_lines(node)
        if points.is_empty(): continue # Unsupported shapes are never guessed.
        next[node.get_instance_id()] = {"points": points, "color": FIGHTER_COLOR if fighter else TERRAIN_COLOR}
    if lab.get("generated_collision_enabled") == true:
        for id in lab.simulation.fighters:
            var record: Dictionary = lab.simulation.collision_telemetry(id)
            var phase: String = lab.collision_snapshot_phase
            if phase == "contact_snapshot": record = record.get("contact_snapshot", {})
            if not record.get("ok", false): continue
            var points := PackedVector3Array()
            for primitive in record.get("primitives", []): points.append_array(capsule_lines(primitive))
            if points.is_empty(): continue
            next["hurtboxes:%d" % id] = {"points": points, "color": Color(1.0, .3, 1.0) if phase == "current_pose" else Color(1.0, .85, .1), "primitives": record.primitives.duplicate(true), "phase": phase}
    if lab.get("simulation") != null:
        for id in lab.simulation.fighters:
            var state: Dictionary = lab.simulation.fighters[id]
            if not state.enabled or state.eliminated or not is_instance_valid(state.actor) or not state.actor.is_inside_tree(): continue
            var jostle: Dictionary = lab.simulation.jostle_world(id)
            if jostle.get("eligible", false):
                next["jostle:%d" % id] = {"points": PackedVector3Array(jostle.world_segment),
                    "color": Color.WHITE, "geometry": jostle.duplicate(true)}
            var support: Dictionary = lab.simulation.top_support_telemetry(id)
            var geometry: Dictionary = support.get("geometry", {})
            var segment: Array = geometry.get("world_segment", [])
            if segment.size() != 2: continue
            # Configured surface remains visible without an active rider relation.
            # Use only the copied authoritative segment; no mesh/bone inference.
            next["top_support:%d" % id] = {"points": PackedVector3Array(segment), "color": TOP_SUPPORT_COLOR,
                "geometry": geometry.duplicate(true), "relation": support.relation.duplicate(true), "generation": support.generation}
    if next == entries: return
    entries = next
    line_mesh.clear_surfaces()
    if entries.is_empty(): return
    line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
    for entry in entries.values():
        line_mesh.surface_set_color(entry.color)
        for point in entry.points: line_mesh.surface_add_vertex(lines.to_local(point))
    line_mesh.surface_end()


## Polygonal surface approximation of the published world capsule enclosure.
func capsule_lines(primitive: Dictionary) -> PackedVector3Array:
    var a: Vector3 = primitive.a
    var b: Vector3 = primitive.b
    var r: float = primitive.radius
    var axis := (b-a).normalized() if a != b else Vector3.UP
    var u := axis.cross(Vector3.RIGHT if absf(axis.x) < .9 else Vector3.BACK).normalized()
    var v := axis.cross(u).normalized()
    var points := PackedVector3Array()
    for center in [a,b]:
        for i in SEGMENTS:
            for j in [i,i+1]:
                var angle: float = TAU*j/SEGMENTS
                points.append(center + r*(u*cos(angle)+v*sin(angle)))
    for radial in [u,v]:
        for i in SEGMENTS:
            for j in [i,i+1]:
                var angle: float = TAU*j/SEGMENTS
                points.append((b if i < SEGMENTS/2 else a) + r*(radial*cos(angle)+axis*sin(angle)))
        for sign_value in [-1,1]:
            points.append(a+radial*r*sign_value)
            points.append(b+radial*r*sign_value)
    return points

func world_lines(node: CollisionShape3D) -> PackedVector3Array:
    var points := PackedVector3Array()
    var shape := node.shape
    if shape is BoxShape3D:
        var h: Vector3 = shape.size * .5
        for axis in range(3):
            for a in [-1, 1]:
                for b in [-1, 1]:
                    var p := Vector3.ZERO
                    p[(axis + 1) % 3] = a * h[(axis + 1) % 3]
                    p[(axis + 2) % 3] = b * h[(axis + 2) % 3]
                    p[axis] = -h[axis]
                    points.append(p)
                    p[axis] = h[axis]
                    points.append(p)
    elif shape is SphereShape3D or shape is CapsuleShape3D or shape is CylinderShape3D:
        var r: float = shape.radius
        var half_stem: float = 0.0 if shape is SphereShape3D else maxf(0, shape.height * .5 - (r if shape is CapsuleShape3D else 0.0))
        # Horizontal rings and two orthogonal meridians retain cardinal extrema.
        for y in ([-half_stem, half_stem] if half_stem > 0 else [0.0]):
            for i in SEGMENTS:
                for j in [i, i + 1]:
                    var angle: float = TAU * j / SEGMENTS
                    points.append(Vector3(cos(angle) * r, y, sin(angle) * r))
        for axis in [0, 2]:
            if shape is CylinderShape3D:
                for sign_value in [-1, 1]:
                    for y in [-half_stem, half_stem]:
                        var p := Vector3(0, y, 0)
                        p[axis] = r * sign_value
                        points.append(p)
            else:
                for i in SEGMENTS:
                    for j in [i, i + 1]:
                        var angle: float = TAU * j / SEGMENTS
                        var sine := sin(angle)
                        var p := Vector3(0, sine * r + (half_stem if i < SEGMENTS / 2 else -half_stem), 0)
                        p[axis] = cos(angle) * r
                        points.append(p)
                # At the equator the upper/lower hemispheres meet the straight stem.
                if half_stem > 0:
                    for sign_value in [-1, 1]:
                        for y in [-half_stem, half_stem]:
                            var p := Vector3(0, y, 0)
                            p[axis] = r * sign_value
                            points.append(p)
    for i in points.size(): points[i] = node.global_transform * points[i]
    return points
