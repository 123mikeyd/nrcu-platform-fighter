extends Node3D
# Visual-only, self-freeing effects for the SSB presentation pass (no collision, no gameplay state).
#   spark     : hit spark, size scales with damage (ssb_presentation.spark_scale), heavy variant adds a ring
#   explosion : blast-zone KO burst pointing back into the stage, coloured by the KO'd player's slot colour
#   twinkle   : the little star when a star-KO'd fighter vanishes into the background
# Everything is in-world geometry; nothing covers the screen.
var mode := "spark"
var color := Color.WHITE
var size := 0.26
var heavy := false
var direction := Vector3.LEFT
var life := 0.16
var age := 0.0
var _core: MeshInstance3D
var _ring: MeshInstance3D
var _rays: Array[MeshInstance3D] = []
var _ray_len: Array[float] = []

func setup_spark(c: Color, radius: float, is_heavy: bool) -> void:
    mode = "spark"; color = c; size = radius; heavy = is_heavy
    life = 0.26 if heavy else 0.16           # ~10 f light / ~16 f heavy

func setup_explosion(c: Color, inward: Vector3) -> void:
    mode = "explosion"; color = c; direction = inward.normalized(); life = 0.62

func setup_twinkle(c: Color, radius: float) -> void:
    mode = "twinkle"; color = c; size = radius; life = 0.40

static func _mat(c: Color, on_top := false) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    m.albedo_color = c
    m.no_depth_test = on_top
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m

func _mesh(m: Mesh, c: Color, on_top := false) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.mesh = m
    node.material_override = _mat(c, on_top)
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)
    return node

func _ready() -> void:
    name = "SsbFx_" + mode
    var hot := color.lerp(Color.WHITE, 0.65)
    match mode:
        "spark":
            var s := SphereMesh.new(); s.radius = size * 0.55; s.height = size * 1.1
            s.radial_segments = 12; s.rings = 6
            _core = _mesh(s, Color(hot, 0.95))
            var count := 8 if heavy else 6
            for i in count:
                var b := BoxMesh.new(); b.size = Vector3(size * 0.16, size * 1.6, size * 0.05)
                var ray := _mesh(b, Color(color.lerp(Color.WHITE, 0.35), 0.9))
                ray.rotation.z = TAU * float(i) / count + 0.3
                _rays.append(ray); _ray_len.append(size * (1.6 if i % 2 == 0 else 1.1))
            if heavy:
                var t := TorusMesh.new(); t.inner_radius = size * 0.9; t.outer_radius = size * 1.05
                _ring = _mesh(t, Color(hot, 0.8))
                _ring.rotation.x = PI * 0.5
        "explosion":
            var s := SphereMesh.new(); s.radius = 0.9; s.height = 1.8
            _core = _mesh(s, Color(hot, 0.95))
            var base := atan2(direction.y, direction.x)
            for i in 9:
                var spread := (float(i) / 8.0 - 0.5) * deg_to_rad(110.0)
                var length := 4.6 - absf(spread) * 1.6 + (0.5 if i % 2 == 0 else 0.0)
                var b := BoxMesh.new(); b.size = Vector3(0.34 if i == 4 else 0.24, 1.0, 0.1)
                var ray := _mesh(b, Color(color.lerp(Color.WHITE, 0.25 if i % 2 == 0 else 0.0), 0.95))
                ray.rotation.z = base + spread - PI * 0.5
                _rays.append(ray); _ray_len.append(length)
            var t := TorusMesh.new(); t.inner_radius = 0.85; t.outer_radius = 1.0
            _ring = _mesh(t, Color(color, 0.8))
            _ring.rotation.x = PI * 0.5
        "twinkle":
            for i in 2:
                var b := BoxMesh.new(); b.size = Vector3(size * 0.22, size * 2.6, size * 0.05)
                var ray := _mesh(b, Color(Color.WHITE.lerp(color, 0.25 * i), 1.0), true)
                ray.rotation.z = PI * 0.5 * i
                _rays.append(ray); _ray_len.append(size * 2.6)
            var s := SphereMesh.new(); s.radius = size * 0.35; s.height = size * 0.7
            _core = _mesh(s, Color(1, 1, 0.9, 1.0), true)
    _animate(0.0)

func _process(delta: float) -> void:
    age += delta
    if age >= life:
        queue_free()
        return
    _animate(age / life)

func _fade(node: MeshInstance3D, a: float) -> void:
    if node == null: return
    var m := node.material_override as StandardMaterial3D
    var c := m.albedo_color
    c.a = clampf(a, 0, 1)
    m.albedo_color = c

func _animate(t: float) -> void:
    match mode:
        "spark":
            var pop := minf(1.0, 0.45 + t * 4.0)          # snaps to full size in ~1/7 of its life
            var alpha := 1.0 - smoothstep(0.35, 1.0, t)
            _core.scale = Vector3.ONE * pop * (1.0 - 0.4 * t)
            _fade(_core, alpha)
            for i in _rays.size():
                var r := _rays[i]
                var dir := Vector3(-sin(r.rotation.z), cos(r.rotation.z), 0)
                var reach := _ray_len[i] * (0.4 + 0.9 * minf(1.0, t * 3.0))
                r.position = dir * reach * 0.5
                r.scale = Vector3(1.0 - 0.6 * t, reach / (size * 1.6), 1)
                _fade(r, alpha)
            if _ring:
                _ring.scale = Vector3.ONE * (0.6 + 1.6 * t)
                _fade(_ring, 0.85 * (1.0 - t))
        "explosion":
            var grow := minf(1.0, t / 0.18)                  # streaks shoot out in ~0.11 s
            var alpha := 1.0 - smoothstep(0.3, 1.0, t)
            _core.scale = Vector3.ONE * (0.6 + 1.1 * grow) * (1.0 - 0.5 * t)
            _fade(_core, alpha)
            for i in _rays.size():
                var r := _rays[i]
                var dir := Vector3(-sin(r.rotation.z), cos(r.rotation.z), 0)
                var reach := _ray_len[i] * grow
                r.position = dir * reach * 0.5
                r.scale = Vector3(1.0 - 0.7 * t, maxf(0.01, reach), 1)
                _fade(r, alpha)
            _ring.scale = Vector3.ONE * (0.5 + 3.2 * t)
            _fade(_ring, 0.8 * (1.0 - t))
        "twinkle":
            var s := sin(PI * t)                              # 0 -> 1 -> 0
            rotation.z = t * PI * 0.5
            for r in _rays:
                r.scale = Vector3.ONE * s
            _core.scale = Vector3.ONE * s
