extends Node
# SSB64-style KO beat, inserted BEFORE the existing Return to Sender revival (which is unchanged).
#   side / bottom : explosion at the exit point (clamped on screen, pointing back into the stage),
#                   short camera shake + rumble, fighter hidden, 0.75 s wait            [FACT 45 f]
#   star (top)    : fighter shrinks and flies into the background, twinkles, short wait [CAL ~0.6x SSB]
#   screen (top)  : 1 in 6 top KOs: fighter thuds against the camera and slides down    [FACT 1/6]
# Then it calls fighter._handle_blast_zone() so stock loss, Return to Sender, elimination and the
# winner screen run exactly as before (the last stock's beat plays before the results).
# During the beat the fighter's own physics callback is paused, controls are off (so it cannot be hit
# or targeted by bots), collision is off and the shared camera ignores it. Pausing the SceneTree
# freezes the beat. Reset / match teardown call cancel() through fighter._clear_move_state().
var P   # ssb_presentation.gd (loaded lazily to avoid a preload cycle)
var actor
var active := false
var kind := "side"
var elapsed := 0.0
var total := 0.75
var exit_point := Vector3.ZERO
var star_start := Vector3.ZERO
var _was_physics := true
var _was_controls := true
var _visual_scale := Vector3.ONE
var _visual_rotation := Vector3.ZERO
var _twinkled := false
var _thudded := false
var _hidden_after := INF

func start(fighter, ko_kind: String) -> void:
    P = load("res://scripts/ssb_presentation.gd")
    actor = fighter
    kind = ko_kind
    active = true
    elapsed = 0.0
    _twinkled = false
    _thudded = false
    exit_point = actor.global_position
    star_start = exit_point
    _was_physics = actor.is_physics_processing()
    _was_controls = actor.controls_enabled
    var root = actor.get("_visual_root")
    if root:
        _visual_scale = root.scale
        _visual_rotation = root.rotation
    actor.set_meta("ssb_ko", kind)
    actor.set_physics_process(false)
    actor.controls_enabled = false          # existing setter clears moves/tumble/revival; can_hit() now false
    actor.velocity = Vector3.ZERO
    actor.hitstun = 0.0
    actor.collision_layer = 0
    actor.collision_mask = 0
    match kind:
        "star":
            total = P.STAR_FLIGHT + P.STAR_TWINKLE + P.STAR_TAIL
            _hidden_after = P.STAR_FLIGHT
            P.play_sfx(actor, P.STAR_KO_SFX, exit_point)
        "screen":
            total = P.SCREEN_FLY_IN + P.SCREEN_HOLD + P.SCREEN_SLIDE + P.SCREEN_TAIL
            _hidden_after = P.SCREEN_FLY_IN + P.SCREEN_HOLD + P.SCREEN_SLIDE
            _face_camera()
        _:
            total = P.DEAD_WAIT
            _hidden_after = 0.0
            actor.visible = false
            _explode()
            P.shake(actor, P.KO_SHAKE, P.KO_SHAKE_SECONDS)
            P.ko_rumble(actor)
            P.play_sfx(actor, P.KO_BOOM_SFX, exit_point)
    set_physics_process(true)

func _physics_process(delta: float) -> void:
    if not active: return
    if not is_instance_valid(actor): active = false; return
    elapsed += delta
    match kind:
        "star": _tick_star()
        "screen": _tick_screen()
    if elapsed >= _hidden_after and actor.visible: actor.visible = false
    if elapsed + 0.00001 >= total: finish()

func remaining() -> float:
    return maxf(0.0, total - elapsed) if active else 0.0

func _camera() -> Camera3D:
    return actor.get_viewport().get_camera_3d() if actor.is_inside_tree() else null

# Where the star ends up: upper part of the current view, on the KO side, pushed back to STAR_DEPTH_Z.
# The default stage's back walls sit at z -8..-15, so the star stays just in front of them
# (perspective + the visual shrink sell the distance) instead of vanishing behind scenery.
const STAR_DEPTH_Z := -6.5
func _star_target() -> Vector3:
    var cam := _camera()
    if cam == null: return Vector3(exit_point.x * 0.4, 9.0, STAR_DEPTH_Z)
    var tangent := tan(deg_to_rad(cam.fov * 0.5))
    var size: Vector2 = actor.get_viewport().get_visible_rect().size
    var aspect: float = size.aspect() if size.y > 1 else 16.0 / 9.0
    var side := clampf(exit_point.x / 16.0, -1.0, 1.0)
    var ray := -cam.global_basis.z + cam.global_basis.y * (tangent * 0.62) + cam.global_basis.x * (tangent * aspect * 0.45 * side)
    if ray.z > -0.01: return Vector3(exit_point.x * 0.4, 9.0, STAR_DEPTH_Z)
    var t := (STAR_DEPTH_Z - cam.global_position.z) / ray.z
    return cam.global_position + ray * t

func _tick_star() -> void:
    var t := clampf(elapsed / P.STAR_FLIGHT, 0.0, 1.0)
    var eased := 1.0 - pow(1.0 - t, 2.2)
    actor.global_position = star_start.lerp(_star_target(), eased)
    var root = actor.get("_visual_root")
    if root:
        root.scale = _visual_scale * lerpf(1.0, 0.3, eased)
        root.rotation = _visual_rotation + Vector3(0, 0, elapsed * 9.0)
    if t >= 1.0 and not _twinkled:
        _twinkled = true
        var fx = P.FxScript.new()
        fx.setup_twinkle(Color(actor.body_color).lerp(Color.WHITE, 0.5), 1.1)
        P.fx_host(actor).add_child(fx)
        fx.global_position = actor.global_position
        P.play_sfx(actor, P.STAR_KO_SFX, actor.global_position)

func _face_camera() -> void:
    var root = actor.get("_visual_root")
    if root:
        root.rotation = Vector3.ZERO
        root.scale = Vector3(absf(_visual_scale.x), _visual_scale.y, _visual_scale.z)

func _tick_screen() -> void:
    var cam := _camera()
    if cam == null: return
    var tangent := tan(deg_to_rad(cam.fov * 0.5))
    var near_depth := 5.2                       # [CAL] fighter fills ~40 % of the screen height
    var lens := cam.global_position - cam.global_basis.z * near_depth - cam.global_basis.y * 1.0
    var fly: float = P.SCREEN_FLY_IN
    var hold: float = P.SCREEN_HOLD
    if elapsed < fly:
        var t: float = elapsed / fly
        var far := cam.global_position - cam.global_basis.z * 40.0 + cam.global_basis.y * 6.0
        actor.global_position = far.lerp(lens, t * t)
    elif elapsed < fly + hold:
        if not _thudded:
            _thudded = true
            P.shake(actor, P.SCREEN_KO_SHAKE, P.KO_SHAKE_SECONDS)
            P.ko_rumble(actor)
            P.play_sfx(actor, P.SCREEN_KO_SFX, lens)
        var squash := 1.0 - 0.12 * sin(PI * clampf((elapsed - fly) / 0.12, 0, 1))
        actor.global_position = lens
        var root = actor.get("_visual_root")
        if root: root.scale = Vector3(absf(_visual_scale.x) * (2.0 - squash), _visual_scale.y * squash, _visual_scale.z)
    else:
        var t := clampf((elapsed - fly - hold) / P.SCREEN_SLIDE, 0.0, 1.0)
        var drop := tangent * near_depth * 2.4 * t * t   # slides off the bottom edge
        actor.global_position = lens - cam.global_basis.y * drop

func _clamp_on_screen(p: Vector3) -> Vector3:
    # SSB clamps the explosion to the camera bounds so it is always seen.   [FACT ftcommondead.c:209-216]
    var out := Vector3(clampf(p.x, -15.0, 15.0), clampf(p.y, -6.5, 14.0), 0.0)
    var cam := _camera()
    if cam == null: return out
    var size: Vector2 = actor.get_viewport().get_visible_rect().size
    if size.x < 2 or size.y < 2: return out
    var plane := Plane(Vector3.BACK, 0.0)
    var lo := Vector3(INF, INF, 0)
    var hi := Vector3(-INF, -INF, 0)
    for corner in [Vector2(0.10, 0.12), Vector2(0.90, 0.12), Vector2(0.10, 0.88), Vector2(0.90, 0.88)]:
        var px: Vector2 = corner * size
        var hit = plane.intersects_ray(cam.project_ray_origin(px), cam.project_ray_normal(px))
        if hit == null: return out
        lo = lo.min(hit); hi = hi.max(hit)
    return Vector3(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y), 0.0)

func _explode() -> void:
    var inward := Vector3.UP if kind == "bottom" else Vector3(-signf(exit_point.x), 0, 0)
    if kind not in ["bottom", "side"]:          # STAR_KO off: a top KO explodes downward
        inward = Vector3.DOWN
    var fx = P.FxScript.new()
    fx.setup_explosion(actor.body_color, inward)
    P.fx_host(actor).add_child(fx)
    fx.global_position = _clamp_on_screen(exit_point)

func _restore() -> void:
    actor.remove_meta("ssb_ko")
    var root = actor.get("_visual_root")
    if root:
        root.scale = _visual_scale
        root.rotation = _visual_rotation
    actor.global_position = exit_point
    actor.velocity = Vector3.ZERO
    actor.visible = true
    actor.collision_layer = actor._active_collision_layer
    actor.collision_mask = actor._active_collision_mask
    actor.controls_enabled = _was_controls
    actor.set_physics_process(_was_physics)

func finish() -> void:
    if not active: return
    active = false
    _restore()
    actor._handle_blast_zone()               # unchanged: lose_stock -> Return to Sender, or eliminated

# Reset / rematch / match teardown (via fighter._clear_move_state): drop the beat without spending a
# stock. The caller owns visibility, position and controls (reset shows/enables, match end hides/disables).
func cancel() -> void:
    if not active: return
    active = false
    if not is_instance_valid(actor): return
    actor.remove_meta("ssb_ko")
    var root = actor.get("_visual_root")
    if root:
        root.scale = _visual_scale
        root.rotation = _visual_rotation
    actor.collision_layer = actor._active_collision_layer
    actor.collision_mask = actor._active_collision_mask
    actor.set_physics_process(_was_physics)
