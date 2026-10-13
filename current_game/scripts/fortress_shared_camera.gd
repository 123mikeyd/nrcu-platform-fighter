extends Camera3D
# Sole gameplay-camera owner. Fixed perspective/pitch; dolly + shared bounds.
# No fighter/control/collision writes. Inherited pause freezes this node.
# SSB64 presentation pass (switches in ssb_presentation.gd): near-instant zoom out, SSB-rate zoom in,
# smoothed facing look-ahead, player-count padding, KO screen shake. Clamps are unchanged.
const P = preload("res://scripts/ssb_presentation.gd")
const MIN_DISTANCE := 21.0
const MAX_DISTANCE := 46.0
# Today's per-fighter box (+-1.1 x, -0.35..height y) is kept as the 2-fighter size; other counts scale it.
const BOX_HALF_WIDTH := 1.1
const BOX_FLOOR := -0.35
var arena: Node3D
var focus := Vector3(0,2,0)
var distance := 23.0
var desired_distance := 23.0
var tracked_count := 0
var snap_pending := true
var last_ids: Array = []
var offset_axis := Vector3(0,3.8,19.5).normalized()
var lead := {}            # instance id -> smoothed facing in [-1, 1] (look-ahead side)
var look_offset := Vector3.ZERO   # smoothed look-ahead added to focus when placing the camera
var shake_amount := 0.0
var shake_seconds := 0.0
var shake_left := 0.0
var shake_offset := Vector3.ZERO
var _shake_clock := 0.0
func _ready():
    name = "FortressSharedCamera"
    arena = get_parent()
    fov = 48.0
    current = true
    _place()
func _place():
    position = focus + look_offset + offset_axis * distance
    look_at(focus + look_offset)
# Short decaying jolt (KO explosion / screen-KO thud). Grows with camera distance like SSB's quake.
func add_shake(amount: float, seconds: float) -> void:
    if amount <= shake_amount * (shake_left / maxf(shake_seconds, 0.001)): return
    shake_amount = amount
    shake_seconds = maxf(seconds, 0.01)
    shake_left = shake_seconds
func _tick_shake(delta: float, dist: float) -> void:
    if shake_left <= 0.0:
        shake_offset = Vector3.ZERO
        return
    shake_left = maxf(0.0, shake_left - delta)
    _shake_clock += delta
    var envelope := shake_left / shake_seconds
    var scale_k := maxf(1.0, dist / P.SHAKE_REF_DISTANCE)
    var a := shake_amount * envelope * envelope * scale_k
    # Two incommensurate sines: a firm rattle without per-frame random teleporting.
    shake_offset = Vector3(sin(_shake_clock * 71.0), sin(_shake_clock * 53.0 + 1.3) * 0.8, 0) * a
    position += global_basis.x * shake_offset.x + global_basis.y * shake_offset.y
func _process(delta):
    if arena.active_level != "debug" and not P.CAMERA_DYNAMIC_ON_THEMED_STAGES:
        position = Vector3(0,5.8,19.5)
        look_at(Vector3(0,2,0))
        snap_pending = true
        _tick_shake(delta, 19.9)
        return
    var points: Array[Vector3] = []
    var ids: Array = []
    tracked_count = 0
    var actors: Array = []
    for actor in arena.fighters:
        if not is_instance_valid(actor) or actor.stocks <= 0 or not actor.is_visible_in_tree(): continue
        if actor.has_meta("ssb_ko"): continue   # KO beat (star / screen KO) is not framed
        var p: Vector3 = actor.global_position
        # Beyond authored blast envelope: do not chase a just-eliminated actor.
        if not p.is_finite() or absf(p.x)>16 or p.y < -8 or p.y > 15: continue
        ids.append(actor.get_instance_id())
        actors.append(actor)
        tracked_count += 1
    # SSB player-count padding (1.5/1.32/1.16/1.0), normalised so 2 fighters keep today's box. [FACT ratios]
    var adj: float = P.camera_padding(tracked_count) / 1.32
    # SSB box: 1000 in front of facing, 700 behind -> front = 2*1000/1700 of the mean half-width. [FACT]
    var ahead: float = (P.CAM_BOX_FRONT - P.CAM_BOX_BACK) / (P.CAM_BOX_FRONT + P.CAM_BOX_BACK)
    var seen := {}
    var lead_points: Array[float] = []
    for actor in actors:
        var id: int = actor.get_instance_id()
        seen[id] = true
        var facing_now: float = signf(float(actor.get("facing"))) if actor.get("facing") != null else 0.0
        var l: float = lead.get(id, facing_now)
        l = lerpf(l, facing_now, 1.0 - exp(-delta * P.CAM_LOOK_AHEAD_RATE))
        lead[id] = l
        var skew: float = ahead * l if P.CAMERA_LOOK_AHEAD else 0.0
        var p: Vector3 = actor.global_position
        var height: float = 3.7 if actor.character_id == "bobo" else 2.8
        var half_w: float = BOX_HALF_WIDTH * adj
        var mid_y: float = (BOX_FLOOR + height) * 0.5
        var half_h: float = (height - BOX_FLOOR) * 0.5 * adj
        for x in [-half_w, half_w]:
            for y in [mid_y - half_h, mid_y + half_h]: points.append(p+Vector3(x,y,0))
        lead_points.append(p.x - half_w * (1.0 - skew))
        lead_points.append(p.x + half_w * (1.0 + skew))
    for id in lead.keys():
        if not seen.has(id): lead.erase(id)
    if points.is_empty():
        snap_pending = true
        _place()
        _tick_shake(delta, distance)
        return
    var low := points[0]
    var high := points[0]
    for p in points:
        low = low.min(p)
        high = high.max(p)
    var target := (low+high)*0.5
    target.x = clampf(target.x,-6,6)
    target.y = clampf(target.y,2.0,8.0)
    target.z = 0
    if target.distance_to(focus) > 0.18:
        focus = focus.lerp(target,1.0-exp(-delta*3.5))
    # Look-ahead rides on top of the dead-zoned focus (it is already smoothed per fighter), so the
    # 0.18 m dead zone cannot swallow it. Same x clamp as the focus.
    var look_x := 0.0
    if not lead_points.is_empty():
        look_x = (lead_points.min() + lead_points.max()) * 0.5 - (low.x + high.x) * 0.5
    look_offset = Vector3(clampf(focus.x + look_x, -6, 6) - focus.x, 0, 0)
    var view_focus := focus + look_offset
    var aspect := get_viewport().get_visible_rect().size.aspect()
    var tangent := tan(deg_to_rad(fov*0.5))
    desired_distance = MIN_DISTANCE
    # Fit all padded corners in actual camera basis; reserve HUD space top/bottom.
    for p in points:
        var relative := p-view_focus
        var horizontal := absf(relative.dot(global_basis.x))
        var vertical := absf(relative.dot(global_basis.y))
        var depth := relative.dot(offset_axis)
        desired_distance = maxf(desired_distance,depth+maxf(horizontal/(tangent*aspect*0.87),vertical/(tangent*0.66))+1.0)
    desired_distance = clampf(desired_distance,MIN_DISTANCE,MAX_DISTANCE)
    if snap_pending or (ids != last_ids and last_ids.is_empty()):
        focus = target
        look_offset = Vector3(clampf(focus.x + look_x, -6, 6) - focus.x, 0, 0)
        distance = desired_distance
        snap_pending = false
    else:
        # SSB: zoom out (near-)instantly so launched fighters stay framed; zoom in at 7.5 %/frame.
        var out_rate: float = P.CAM_ZOOM_OUT_RATE if P.CAMERA_FAST_ZOOM else 7.0
        var in_rate: float = P.CAM_ZOOM_IN_RATE if P.CAMERA_FAST_ZOOM else 1.6
        # SSB zoom is per-frame: clamp hitch frames so a long frame can't turn a fast zoom into a cut.
        var zd: float = minf(delta, 1.0 / 30.0) if P.CAMERA_FAST_ZOOM else delta
        var next_distance := lerpf(distance,desired_distance,1.0-exp(-zd*(out_rate if desired_distance>distance else in_rate)))
        distance = next_distance
    last_ids = ids
    _place()
    _tick_shake(delta, distance)
