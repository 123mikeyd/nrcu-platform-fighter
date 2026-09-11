extends Node3D
# Provisional tuning. One status per victim, refresh only; never multiplicative.
const DURATION := 2.0
const INTERVAL := 0.5
const TICK_DAMAGE := 1.0
const MAX_TICKS := 4
var remaining := 0.0
var next_tick := INTERVAL
var ticks_left := 0
var total_ticks := 0
# Presentation has its own clock: it never advances or spends a damage tick.
var indicator: Sprite3D
var embers: Array[Sprite3D] = []
var visual_age := 0.0
var body_height := 1.8
var body_radius := 0.55
var body_floor := 0.0

func _ready() -> void:
    name = "BurnStatus"
    var image := Image.new()
    image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="80" viewBox="0 0 64 80"><path d="M34 5 C39 23 53 26 54 43 C65 32 60 57 51 66 C40 79 17 77 9 61 C0 44 12 32 19 22 C17 37 24 40 26 32 C30 22 25 17 34 5Z" fill="#ff852c" stroke="#352016" stroke-width="5" stroke-linejoin="round"/><path d="M34 34 C36 47 46 48 44 59 C42 70 25 71 22 60 C19 51 28 48 34 34Z" fill="#ffe3a1"/></svg>')
    indicator = Sprite3D.new()
    indicator.name = "FlameIndicator"
    indicator.texture = ImageTexture.create_from_image(image)
    indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    # Only the small status icon overlays terrain; sparks remain world-occluded.
    indicator.no_depth_test = true
    indicator.shaded = false
    add_child(indicator)
    var spark_image := Image.new()
    spark_image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="24"><ellipse cx="8" cy="12" rx="4" ry="8" fill="#ffc47c"/><ellipse cx="8" cy="11" rx="2" ry="5" fill="#ffe9b7"/></svg>')
    var spark_texture := ImageTexture.create_from_image(spark_image)
    for i in 7:
        var spark := Sprite3D.new()
        spark.name = "Ember%d" % i
        spark.texture = spark_texture
        spark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        spark.no_depth_test = false
        spark.shaded = false
        add_child(spark)
        embers.append(spark)
    visibility_changed.connect(_sync_visibility)
    hide()

func _fit_body() -> void:
    # Capsule is a stable body envelope for animated rigs (bind AABBs are not).
    var fighter = get_parent()
    for child in fighter.get_children():
        if child is CollisionShape3D and child.shape is CapsuleShape3D:
            body_height = child.shape.height * child.scale.y
            body_radius = child.shape.radius * child.scale.x
            body_floor = child.position.y - body_height * 0.5
    # GGB's actual static presentation is smaller than its gameplay capsule.
    var ggb = fighter.get_node_or_null("VisualRoot/GGBVisual")
    if ggb:
        var first := true
        var bounds := AABB()
        for mesh in ggb.meshes:
            var local: Transform3D = fighter.global_transform.affine_inverse() * mesh.global_transform
            var box: AABB = local * mesh.get_aabb()
            bounds = box if first else bounds.merge(box)
            first = false
        if not first:
            body_height = bounds.size.y
            body_floor = bounds.position.y
            body_radius = minf(bounds.size.x * 0.5, body_height * 0.55)
    indicator.pixel_size = clampf(body_height * 0.27, 0.36, 0.49) / 80.0
    # Beside the torso, not over the face or competing with the overhead P marker.
    indicator.position = Vector3(body_radius + 0.30, body_floor + body_height * 0.68, 0)
    for spark in embers:
        spark.pixel_size = clampf(body_height * 0.052, 0.045, 0.09) / 24.0

func _sync_visibility() -> void:
    set_process(visible)
    visual_age = 0.0
    if visible:
        _fit_body()
        _process(0.0)

func _process(delta: float) -> void:
    if not visible or remaining <= 0: return
    visual_age += maxf(delta, 0.0)
    var envelope := smoothstep(0.0, 0.30, remaining)
    indicator.modulate.a = envelope
    for i in embers.size():
        var phase := fposmod(visual_age / 1.15 + float(i) / embers.size(), 1.0)
        var side := -1.0 if i % 2 == 0 else 1.0
        var spark := embers[i]
        spark.position = Vector3(side * body_radius * (0.70 + 0.22 * sin(phase * PI)), body_floor + body_height * (0.12 + phase * 0.70), 0.24 + float(i % 3) * 0.12)
        spark.modulate.a = sin(phase * PI) * 0.68 * envelope
func refresh() -> void:
    if remaining <= 0: next_tick = INTERVAL
    remaining = DURATION
    ticks_left = MAX_TICKS
    show()
func clear() -> void:
    remaining = 0
    next_tick = INTERVAL
    ticks_left = 0
    hide()
func tick(delta: float) -> void:
    if remaining <= 0: return
    var fighter = get_parent()
    if not fighter.controls_enabled or fighter.stocks <= 0:
        clear()
        return
    var elapsed := minf(maxf(delta, 0), remaining)
    remaining = maxf(0, remaining - elapsed)
    next_tick -= elapsed
    while next_tick <= 0.000001 and ticks_left > 0:
        ticks_left -= 1
        total_ticks += 1
        next_tick += INTERVAL
        # Do not call receive_hit: DOT does not interrupt, knock back or thaw.
        if fighter.has_method("apply_status_damage"):
            fighter.apply_status_damage(TICK_DAMAGE)
            if fighter.stocks <= 0: return
        else:
            fighter.damage_percent += TICK_DAMAGE
            fighter.state_changed.emit()
    # A preserved phase can spend four ticks before the refreshed duration ends.
    # Keep the full duration without granting an extra tick or refreshing a fade.
    if remaining <= 0: clear()
