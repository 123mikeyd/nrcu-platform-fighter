class_name FighterHero
extends SubViewportContainer
# Reusable 3D fighter hero (Visual spec §10): ONE live model at a time in its
# own SubViewport — consistent camera, lighting and framing, reused by
# Character Select (selected-fighter hero) and Results (winner hero).
#
# The instance is a real Fighter with physics/controls disabled, removed from
# the "fighters" group so gameplay queries never see it. Framing is computed
# from the model's own AABB, so tall/short/wide silhouettes all get a clean
# fit without per-fighter coordinate tables.

const FighterScript = preload("res://scripts/fighter.gd")
const Roster = preload("res://scripts/roster.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")

const CAMERA_ANGLE_DEG := 18.0     # slight 3/4 turn for depth
const CAMERA_ELEV_DEG := 12.0
const FIT_MARGIN := 1.12           # breathing room around the silhouette
const AIM_OFFSET_Y := 0.07         # aim just above box center: feet sit low in frame
# Canonical silhouette box, measured from the rendered build (feet ~0.19,
# head/detail top ~2.79 units for every fighter — they share the capsule+head
# skeleton). Framing on this box gives every fighter the same confident
# composition and floor line; measured AABBs include hidden helper meshes
# (flash/shell/rings) and are not usable for the camera. Add per-fighter
# entries below only when a build genuinely differs.
const MODEL_BOX := AABB(Vector3(-0.75, 0.15, -0.75), Vector3(1.5, 2.7, 1.5))
const FRAME_OVERRIDES := {}
const SWAY_DEG := 3.5              # ambient motion, own clock
const SWAY_SECONDS := 7.0
const BASE_YAW_DEG := -22.0        # neutral stance toward the camera

var fighter: Node3D = null
var _hero_id := ""
var _stage: Node3D
var _camera: Camera3D
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _sway := 0.0
var _sway_enabled := true
var _fit_distance := 0.0
var _fit_attempts := 0

func _ready() -> void:
    stretch = true
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _build_stage()

func _build_stage() -> void:
    # Lazy: callers may call set_fighter() in the same frame the rig is added
    # (before _ready runs), so the viewport rig is built on demand.
    if _stage != null and is_instance_valid(_stage):
        return
    var vp := SubViewport.new()
    vp.name = "HeroViewport"
    vp.transparent_bg = true
    vp.own_world_3d = true
    vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    vp.msaa_3d = Viewport.MSAA_2X
    add_child(vp)
    var world := Environment.new()
    world.background_mode = Environment.BG_CANVAS
    world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    world.ambient_light_color = Color("cfe3dd")
    world.ambient_light_energy = 0.72
    var holder := Node3D.new()
    holder.name = "HeroStage"
    vp.add_child(holder)
    _stage = holder
    _camera = Camera3D.new()
    _camera.name = "HeroCamera"
    _camera.fov = 32.0
    _camera.current = true
    holder.add_child(_camera)
    _key_light = DirectionalLight3D.new()
    _key_light.light_energy = 1.15
    _key_light.rotation_degrees = Vector3(-38.0, 32.0, 0.0)
    holder.add_child(_key_light)
    _fill_light = DirectionalLight3D.new()
    _fill_light.light_energy = 0.45
    _fill_light.light_color = Color("ffd9ae")
    _fill_light.rotation_degrees = Vector3(-14.0, -128.0, 0.0)
    holder.add_child(_fill_light)
    var we := WorldEnvironment.new()
    we.name = "HeroEnvironment"
    we.environment = world
    holder.add_child(we)

func set_fighter(id: String, palette_index := 0) -> void:
    _build_stage()
    clear_fighter()
    _fit_attempts = 0
    if id == "":
        return
    var f = FighterScript.new()
    f.character_id = id
    _hero_id = id
    f.fighter_name = Roster.display_name(id).to_upper()
    f.body_color = Roster.palette(id, palette_index)
    f.controls_enabled = false
    var holder: Node3D = _stage
    holder.add_child(f)
    f.remove_from_group("fighters")
    f.collision_layer = 0
    f.collision_mask = 0
    f.set_physics_process(false)
    # HUD-only children (the arena's player tag, the move-status text) never
    # belong on a hero model.
    for node in f.find_children("*", "Label3D", true, false):
        var label: Label3D = node
        label.hide()
    f.position = Vector3.ZERO
    f.rotation_degrees = Vector3(0.0, BASE_YAW_DEG, 0.0)
    fighter = f
    call_deferred("frame_model")

func clear_fighter() -> void:
    if fighter != null and is_instance_valid(fighter):
        fighter.queue_free()
    fighter = null

func has_fighter() -> bool:
    return fighter != null and is_instance_valid(fighter)

func model_aabb() -> AABB:
    # Only VISIBLE meshes count: fighters carry invisible helpers (attack
    # flash, frozen shell, wave rings) whose AABBs are far larger than the
    # silhouette and would push the camera away.
    var result := AABB()
    if not has_fighter():
        return result
    var first := true
    for node in fighter.find_children("*", "MeshInstance3D", true, false):
        var mesh: MeshInstance3D = node
        # Own `visible` flag, not is_visible_in_tree(): the latter is
        # unreliable for nodes inside a SubViewport's 3D world, and all
        # helpers (flash, shell, rings) hide themselves locally.
        if mesh.mesh == null or not mesh.visible:
            continue
        var box: AABB = mesh.global_transform * mesh.get_aabb()
        if first:
            result = box
            first = false
        else:
            result = result.merge(box)
    return result

func frame_model() -> void:
    # Fit the camera to the silhouette: no clipping, consistent floor line.
    # The canonical box is projected onto the camera's right/up axes, so the
    # same framing holds at any viewport aspect.
    var box: AABB = FRAME_OVERRIDES.get(_hero_id, MODEL_BOX)
    var center := box.get_center() + Vector3(0.0, AIM_OFFSET_Y, 0.0)
    var vfov := deg_to_rad(_camera.fov)
    var aspect: float = maxf(size.x / maxf(size.y, 1.0), 0.5)
    var forward := Vector3(
        sin(deg_to_rad(CAMERA_ANGLE_DEG)),
        sin(deg_to_rad(CAMERA_ELEV_DEG)),
        cos(deg_to_rad(CAMERA_ANGLE_DEG))).normalized()
    var right := Vector3.UP.cross(forward).normalized()
    var up := forward.cross(right).normalized()
    var half_w := 0.0
    var half_h := 0.0
    for xi in 2:
        for yi in 2:
            for zi in 2:
                var corner := box.position + Vector3(
                    box.size.x * xi, box.size.y * yi, box.size.z * zi)
                var offset := corner - center
                half_w = maxf(half_w, absf(offset.dot(right)))
                half_h = maxf(half_h, absf(offset.dot(up)))
    var dist_v := half_h / tan(vfov * 0.5)
    var dist_h := half_w / (tan(vfov * 0.5) * aspect)
    _fit_distance = maxf(dist_v, dist_h) * FIT_MARGIN
    _camera.position = center + forward * _fit_distance
    _camera.look_at(center, Vector3.UP)

func get_fit_distance() -> float:
    return _fit_distance

func set_sway_enabled(value: bool) -> void:
    _sway_enabled = value

func _process(delta: float) -> void:
    # Self-healing fit: a character's meshes can arrive a frame after the
    # instance (deferred visual setup), so retry until the camera is placed.
    if has_fighter() and _fit_distance <= 0.01 and _fit_attempts < 120:
        _fit_attempts += 1
        frame_model()
    if not has_fighter() or not _sway_enabled:
        return
    _sway += delta
    var wave := sin(TAU * _sway / SWAY_SECONDS)
    fighter.rotation_degrees = Vector3(0.0, BASE_YAW_DEG + wave * SWAY_DEG, 0.0)
