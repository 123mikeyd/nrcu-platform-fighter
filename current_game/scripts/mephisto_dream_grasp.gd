extends RefCounted
# Down-special DREAM GRASP (Mephisto sleep kit, first playable pass).
# The companion demon reaches forward with the accepted Mephisto03 Swipe arm
# path; the accepted Grasp finger curl closes on the first opponent whose
# receiving anatomy meets the right hand. A caught opponent is held head-in-palm,
# crushed for small damage, then dropped asleep. Whiffs close on air and recover.
# The girl commands it with the installed ForcePush cast/hold/recovery pose.
var moves
var victim = null
var caught_at := -1.0
var head_offset := 1.4
var released := false
var close_weight := 0.0
var floor_y := 0.0
var head_dx_local := 0.0
# Adaptive lunge: point-blank grabs keep the original arm path (which already
# closes on overlapping targets); farther targets get up to LUNGE_MAX extra reach.
var lunge := 0.0
const LUNGE_MAX := 0.9
const HAND_REACH := 0.95         # unlunged wrist->fingers reach in front of Mephisto
# Reach aim: the arm tilts about the shoulder toward the nearest opponent's
# head during the reach, so short (GGB) and very close targets are not passed over.
var aim_y := NAN
const AIM_MIN := -1.0
const AIM_MAX := 0.6
func nearest_front_head_y() -> float:
	var actor = moves.actor
	var best = null
	var best_dx := 99.0
	for target in actor.get_tree().get_nodes_in_group("fighters"):
		if target == actor or not actor.can_hit(target) or target.stocks <= 0: continue
		var dx: float = (target.global_position.x - actor.global_position.x) * moves.facing
		if dx > -0.2 and dx < 2.8 and absf(target.global_position.y - actor.global_position.y) < 2.5 and dx < best_dx:
			best = target; best_dx = dx
	if best == null: return NAN
	var head := target_head_point(best)
	# Lunge only as far as needed to put the fingers on that head (capped).
	var head_dx: float = (head.x - actor.global_position.x) * moves.facing
	lunge = clampf(head_dx - HAND_REACH, 0.0, LUNGE_MAX)
	return head.y
func reach_aim_weight(t: float) -> float:
	if is_nan(aim_y) or caught(): return 0.0
	return smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(ACTIVE_END, ACTIVE_END + WHIFF_CLOSE + RETRACT * 0.6, t))
var last_aim_angle := 0.0
var catch_aim := 0.0
func apply_reach_aim(companion, t: float) -> void:
	var w := reach_aim_weight(t)
	last_aim_angle = companion.solve_hoist_angle(aim_y, AIM_MIN, AIM_MAX) * w if w > 0.0 else 0.0
	if w > 0.0: companion.hoist(last_aim_angle)
func held_arm_angle(companion, t: float) -> float:
	# Blend from the reach aim at the catch into the per-frame hoist, then release.
	var k := smoothstep(caught_at, caught_at + 0.2, t)
	var r := retract_start()
	var solved: float = companion.solve_hoist_angle(target_palm_y(), HOIST_MIN, HOIST_MAX)
	return lerpf(catch_aim, solved, k) * (1.0 - smoothstep(r, r + RETRACT * 0.8, t))
func nearest_front_gap() -> float:
	var actor = moves.actor
	var best := 99.0
	for target in actor.get_tree().get_nodes_in_group("fighters"):
		if target == actor or not actor.can_hit(target) or target.stocks <= 0: continue
		var dx: float = (target.global_position.x - actor.global_position.x) * moves.facing
		if dx > 0 and absf(target.global_position.y - actor.global_position.y) < 2.5: best = minf(best, dx)
	return best
const HOIST_LIFT := 0.5
const GRIP_MIN_LIFT := 0.3          # desired victim foot clearance while held
const HOIST_MIN := -0.25
const HOIST_MAX := 0.9           # radians about the shoulder
const REACH_END := 0.40          # elapsed at full Swipe extension
const SWIPE_EXTENDED := 0.417    # Swipe source seconds, arm fully out
const SWIPE_RETRACT := 0.583     # Swipe source seconds, retract start
const ACTIVE_START := 0.24
const ACTIVE_END := 0.52
const WHIFF_CLOSE := 0.14
const HOLD := 0.55
const RETRACT := 0.45
const CRUSH_DAMAGE := 6.0
const GRAB_RADIUS := 0.16
func begin() -> void:
	victim = null; caught_at = -1.0; released = false; close_weight = 0.0; last_aim_angle = 0.0; catch_aim = 0.0; head_dx_local = 0.0
	lunge = 0.0
	aim_y = nearest_front_head_y()
func caught() -> bool:
	return caught_at >= 0.0
func retract_start() -> float:
	return caught_at + HOLD if caught() else ACTIVE_END + WHIFF_CLOSE
func duration() -> float:
	return (maxf(caught_at, 0.0) + HOLD + RETRACT) if caught() else ACTIVE_END + WHIFF_CLOSE + RETRACT
func swipe_time(t: float) -> float:
	if t <= REACH_END: return t / REACH_END * SWIPE_EXTENDED
	var r := retract_start()
	if t < r: return lerpf(SWIPE_EXTENDED, 0.5, clampf((t - REACH_END) / maxf(r - REACH_END, .001), 0, 1))
	return lerpf(SWIPE_RETRACT, 1.0, clampf((t - r) / RETRACT, 0, 1))
func advance(t: float) -> float:
	var r := retract_start()
	return smoothstep(0.08, REACH_END * 0.85, t) * (1.0 - smoothstep(r, r + RETRACT * 0.9, t))
func finger_close(t: float) -> float:
	var r := retract_start()
	var start := caught_at if caught() else ACTIVE_END
	var w := smoothstep(start, start + (0.10 if caught() else WHIFF_CLOSE), t) if t >= start else 0.0
	return w * (1.0 - smoothstep(r + 0.05, r + 0.25, t))
func hoist_weight(t: float) -> float:
	if not caught(): return 0.0
	var r := retract_start()
	return smoothstep(caught_at, caught_at + 0.2, t) * (1.0 - smoothstep(r, r + RETRACT * 0.8, t))
func target_palm_y() -> float:
	return floor_y + head_offset + HOIST_LIFT
func palm(companion) -> Vector3:
	return companion.point("Hand.R").lerp(companion.point("Middle.01.R"), 0.65)
func holding(target) -> bool:
	return is_instance_valid(target) and target == victim and caught() and not released and moves.move == "DreamGrasp" and moves.elapsed < caught_at + HOLD
func hold_anchor(target) -> Vector3:
	var companion = moves.view().companion
	var p: Vector3 = palm(companion)
	# Head-in-palm when the arm can reach; very tall victims (Bobo) are gripped
	# lower (neck/chest) so they still leave the floor instead of scraping it.
	# Never pull a held victim below Mephisto's floor line.
	var grip := minf(head_offset, maxf(0.3, p.y - floor_y - GRIP_MIN_LIFT))
	return Vector3(p.x - head_dx_local, maxf(p.y - grip, floor_y), 0)
func present(t: float) -> void:
	var v = moves.view()
	v.pose_frame(704, moves.facing); v.show_native_girl(moves.facing)
	var Ember = preload("res://scripts/mephisto_ember_pose.gd")
	var r := retract_start()
	if t < r:
		Ember.present(v, "EmberHold", minf(t * 1.9, Ember.CAST))
	else:
		Ember.present(v, "EmberRelease", Ember.EXPLOSION + clampf((t - r) / RETRACT, 0, 1) * (Ember.RECOVER_END - Ember.EXPLOSION))
	v.current_clip = "Girl2/ForcePush/DreamGrasp"
	v.companion.sync_pose()
func target_head_point(target) -> Vector3:
	# The victim's visible Head bone (world). Every rig is aimed at and held by its
	# real head; rigid models (GGB) fall back to their highest receiving capsule.
	var visual_root = target.get_node_or_null("VisualRoot")
	var best_point := Vector3.ZERO
	var found := false
	if visual_root != null:
		for sk in visual_root.find_children("*", "Skeleton3D", true, false):
			if not sk.is_visible_in_tree() or "Companion" in str(visual_root.get_path_to(sk)): continue
			for n in ["Head", "mixamorig_Head", "DEF-spine.006"]:
				var i: int = sk.find_bone(n)
				if i >= 0:
					var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin + Vector3(0, 0.08, 0)
					if not found or p.y > best_point.y: best_point = p
					found = true
					break
	if not found:
		for shape in target.get_hurtbox_shapes():
			if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D: continue
			if not found or shape.global_position.y > best_point.y: best_point = shape.global_position
			found = true
	if not found: best_point = target.global_position + Vector3(0, 1.4, 0)
	best_point.y = target.global_position.y + clampf(best_point.y - target.global_position.y, 0.6, 2.8)
	return best_point
func target_head_offset(target) -> float:
	return target_head_point(target).y - target.global_position.y

func tick(previous: float, t: float) -> void:
	var companion = moves.view().companion
	if not caught() and t >= ACTIVE_START and previous <= ACTIVE_END:
		var start := maxf(previous, ACTIVE_START); var end := minf(t, ACTIVE_END)
		var count := maxi(1, int(ceil((end - start) * 120.0)))
		for step in range(count + 1):
			var s := lerpf(start, end, float(step) / count)
			companion.sample("Swipe", swipe_time(s))
			apply_reach_aim(companion, s)
			var wrist: Vector3 = companion.point("Hand.R")
			var points := [wrist]
			for digit in ["Index.01.R", "Middle.01.R", "Ring.01.R", "Pinky.01.R"]:
				var k: Vector3 = companion.point(digit)
				points.append(wrist.lerp(k, 0.5)); points.append(k)
			var target = find_target(points)
			if target != null:
				grab(target, s, points)
				break
		companion.sync_pose()
	if caught() and not released and t >= caught_at + HOLD:
		released = true
		if is_instance_valid(victim): victim.velocity = Vector3(moves.facing * 0.6, 0.0, 0)
func find_target(points: Array):
	var actor = moves.actor
	for target in actor.get_tree().get_nodes_in_group("fighters"):
		if target in moves.targets or not actor.can_hit(target) or target.stocks <= 0: continue
		if (target.global_position.x - actor.global_position.x) * moves.facing <= 0: continue
		for shape in target.get_hurtbox_shapes():
			if not shape is CollisionShape3D or shape.disabled or not shape.shape is CapsuleShape3D: continue
			var half := maxf(0.0, shape.shape.height * 0.5 - shape.shape.radius)
			var xf: Transform3D = shape.global_transform
			var r: float = shape.shape.radius * maxf(xf.basis.x.length(), xf.basis.z.length())
			for point in points:
				var nearest := Geometry3D.get_closest_point_to_segment(point, xf * Vector3(0, -half, 0), xf * Vector3(0, half, 0))
				if point.distance_to(nearest) <= r + GRAB_RADIUS:
					return target
	return null
func grab(target, s: float, points: Array) -> void:
	var actor = moves.actor
	moves.targets.append(target)
	var row := {"move": "DreamGrasp", "elapsed": s, "target": target.character_id, "point": str(points[0]), "damage": CRUSH_DAMAGE}
	if target.can_sleep(actor):
		victim = target; caught_at = s; catch_aim = last_aim_angle
		var hp := target_head_point(target)
		head_offset = hp.y - target.global_position.y
		head_dx_local = hp.x - target.global_position.x
		# Floor line = the victim's own standing height if grounded (rigs differ).
		floor_y = maxf(actor.global_position.y, target.global_position.y) if target.is_on_floor() else actor.global_position.y
		target.hit_source = actor
		target.apply_status_damage(CRUSH_DAMAGE)
		target.last_damage_source = actor
		target.apply_sleep(actor, HOLD - (moves.elapsed - s), self)
		row["kind"] = "caught asleep"; row["sleep_total"] = target.sleep_total
	else:
		# Sleep-immune (just woke) targets are shoved, never re-slept or looped.
		target.receive_hit_from(CRUSH_DAMAGE, Vector3(moves.facing, .3, 0), 3.2, actor)
		caught_at = -1.0
		row["kind"] = "immune shove"
	moves.contacts.append(row)
func cancel() -> void:
	if is_instance_valid(victim) and victim.sleep_anchor_owner == self:
		victim.sleep_anchor_owner = null
	victim = null; released = true
