extends Camera3D
# Sole gameplay-camera owner. Fixed perspective/pitch; dolly + shared bounds.
# No fighter/control/collision writes. Inherited pause freezes this node.
const MIN_DISTANCE := 21.0
const MAX_DISTANCE := 46.0
var arena: Node3D
var focus := Vector3(0,2,0)
var distance := 23.0
var desired_distance := 23.0
var tracked_count := 0
var snap_pending := true
var last_ids: Array = []
var offset_axis := Vector3(0,3.8,19.5).normalized()
func _ready():
    name = "FortressSharedCamera"
    arena = get_parent()
    fov = 48.0
    current = true
    _place()
func _place():
    position = focus + offset_axis * distance
    look_at(focus)
func _process(delta):
    if arena.active_level not in ["debug","hall","meadow"]:
        position = Vector3(0,5.8,19.5)
        look_at(Vector3(0,2,0))
        snap_pending = true
        return
    var points: Array[Vector3] = []
    var ids: Array = []
    tracked_count = 0
    for actor in arena.fighters:
        if not is_instance_valid(actor) or actor.stocks <= 0 or not actor.is_visible_in_tree(): continue
        var p: Vector3 = actor.global_position
        # Beyond authored blast envelope: do not chase a just-eliminated actor.
        if not p.is_finite() or absf(p.x)>16 or p.y < -8 or p.y > 15: continue
        ids.append(actor.get_instance_id())
        tracked_count += 1
        var height := 3.7 if actor.character_id == "bobo" else 2.8
        for x in [-1.1,1.1]:
            for y in [-0.35,height]: points.append(p+Vector3(x,y,0))
    if points.is_empty():
        snap_pending = true
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
    var aspect := get_viewport().get_visible_rect().size.aspect()
    var tangent := tan(deg_to_rad(fov*0.5))
    desired_distance = MIN_DISTANCE
    # Fit all padded corners in actual camera basis; reserve HUD space top/bottom.
    for p in points:
        var relative := p-focus
        var horizontal := absf(relative.dot(global_basis.x))
        var vertical := absf(relative.dot(global_basis.y))
        var depth := relative.dot(offset_axis)
        desired_distance = maxf(desired_distance,depth+maxf(horizontal/(tangent*aspect*0.87),vertical/(tangent*0.66))+1.0)
    desired_distance = clampf(desired_distance,MIN_DISTANCE,MAX_DISTANCE)
    if snap_pending or (ids != last_ids and last_ids.is_empty()):
        focus = target
        distance = desired_distance
        snap_pending = false
    else:
        # Fast expansion protects launched fighters; slower contraction avoids pumping.
        distance = lerpf(distance,desired_distance,1.0-exp(-delta*(7.0 if desired_distance>distance else 1.6)))
    last_ids = ids
    _place()
