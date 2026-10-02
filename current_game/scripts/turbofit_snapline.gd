extends Node
# TurboFit SNAPLINE Up-B (review MVP, NOT APPROVED).
# Draw the guitar like a bow -> string snaps, whips up and latches to a fixed air point
# -> hop kick (air: soft air-cushion ripple) -> reel up holding the Mercury pose -> normal air.
# Presentation = approved Blender audition clips (snapline_clips_v001.tres), sampled on this clock.
# No damage, no enemy/ledge latch yet (later features). Recovery rules match the current Up-B:
# one use per airtime, jumps spent, no helpless state.

const CLIPS = preload("res://assets/turbofit/snapline_clips_v001.tres")
const GUITAR = preload("res://assets/turbofit/real_guitar.glb")
const FPS := 30.0
# Frames after the Up-B press, taken 1:1 from the Blender audition (v012/build_anim2.py).
const BEATS := {
	"AIR": {"clip": "SnaplineAir", "hook0": 4, "hook1": 8, "snap0": 14, "snap1": 17, "latch": 21, "kick": 22, "reel1": 42, "end": 44},
	"GROUND": {"clip": "SnaplineGround", "hook0": 3, "hook1": 6, "snap0": 20, "snap1": 23, "latch": 27, "kick": 29, "reel1": 49, "end": 51},
}
# Tunables (game units; Turbo renders at 1.25x Blender metres).
const SNAP_LEN := 3.6          # headstock -> latch point. Tuned so the rise ~= current Rising Chord (~3.6u apex)
const LATCH_SHORT := 0.5625    # reel stops this far short of the latch (0.45 m * 1.25)
const SNAP_DIR := Vector2(0.25, 1.0)  # x is multiplied by facing
const STALL_DECEL := 60.0      # air: how fast the fall is cancelled during the draw
# Exact hand->guitar grips exported from the audition rig (RightHand bone space).
# Hand-bone -> guitar grips, solved from Blender/Godot bone geometry at pose A (press+8) and B (press+17); fit error 0.
const REL_A := Transform3D(Vector3(1.818055e-05, 2.46465, 55.14492), Vector3(-55.19998, -4.73611e-06, 1.716826e-05), Vector3(-1.262574e-05, -55.14497, 2.464647), Vector3(11.03992, 7.154368, 2.426072))
const REL_B := Transform3D(Vector3(-6.680782e-06, -11.12044, 54.0682), Vector3(-55.19993, 6.983735e-05, 9.913353e-06), Vector3(-7.722965e-05, -54.06815, -11.12044), Vector3(11.04005, 7.122048, 2.833566))
const NUT := Vector3(0, 0.58, 0.03)
const BRIDGE := Vector3(0, -0.60, 0.06)
const WHIP_POINTS := 14

var actor
var view
var skeleton: Skeleton3D
var phase := "idle"   # idle | draw | whip | reel
var kind := "AIR"
var elapsed := 0.0
var facing := 1.0
var actor_stock := 0
var latch := Vector3.ZERO
var latched := false
var reel_vec := Vector3.ZERO
var reel_start := Vector3.ZERO
var cushion_origin := Vector3.ZERO
var cushion_clock := -1.0
var starts := 0
var completes := 0
var cancels := 0
var guitar: Node3D
var fx_root: Node3D
var segments: Array[MeshInstance3D] = []
var barb: MeshInstance3D
var cushion: MeshInstance3D
var cushion_mat: StandardMaterial3D

func _ready() -> void:
	actor = get_parent()
	view = actor._visual_root.get_node("TurboFitVisual")
	skeleton = view._kick_skeleton
	var lib: AnimationLibrary = view.animation_player.get_animation_library("")
	for n in CLIPS.get_animation_list():
		if not lib.has_animation(n): lib.add_animation(n, CLIPS.get_animation(n).duplicate(true))
	fx_root = Node3D.new(); fx_root.name = "SnaplineFX"; fx_root.top_level = true; actor.add_child(fx_root)
	guitar = GUITAR.instantiate(); guitar.name = "SnaplineGuitar"; fx_root.add_child(guitar)
	var smat := StandardMaterial3D.new(); smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; smat.albedo_color = Color(0.93, 0.95, 1.0)
	for i in WHIP_POINTS:
		var s := MeshInstance3D.new(); var c := CylinderMesh.new()
		c.top_radius = 0.012; c.bottom_radius = 0.012; c.height = 1.0; c.radial_segments = 6; c.rings = 1
		s.mesh = c; s.material_override = smat; fx_root.add_child(s); segments.append(s)
	barb = MeshInstance3D.new(); var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.04; cone.height = 0.1; cone.radial_segments = 8
	barb.mesh = cone; barb.material_override = smat; fx_root.add_child(barb)
	cushion = MeshInstance3D.new(); var tor := TorusMesh.new(); tor.inner_radius = 0.9; tor.outer_radius = 1.0; tor.rings = 32; tor.ring_segments = 6
	cushion.mesh = tor
	cushion_mat = StandardMaterial3D.new(); cushion_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cushion_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; cushion_mat.albedo_color = Color(0.75, 0.92, 1.0, 0.0)
	cushion.material_override = cushion_mat; fx_root.add_child(cushion)
	_hide_fx(true)

func active() -> bool:
	return phase != "idle"

func beats() -> Dictionary:
	return BEATS[kind]

func frame() -> float:
	return elapsed * FPS

func valid_actor() -> bool:
	return is_instance_valid(actor) and actor.controls_enabled and actor.stocks > 0 and actor.hitstun <= 0 and actor.freeze_remaining <= 0 and not is_instance_valid(actor.caught_by) and not (actor.tumble and actor.tumble.active)

func start() -> bool:
	if active() or actor.recovery_spent or not valid_actor(): return false
	kind = "GROUND" if actor.is_grounded() else "AIR"
	actor.cancel_for_grab()
	view.guitar_moves.hide_now()
	view.cancel_power_chord()
	actor.recovery_spent = true; actor.jumps_used = 2
	actor.recovery_active = 0; actor.attack_flash_time = 0; actor.attack_cooldown = 0
	actor.last_move = "SNAPLINE"
	actor_stock = actor.stocks; facing = actor.facing
	phase = "draw"; elapsed = 0.0; latched = false; cushion_clock = -1.0
	starts += 1
	if kind == "GROUND": actor.velocity = Vector3.ZERO
	present()
	return true

func watchdog() -> void:
	if active() and (not valid_actor() or actor.stocks != actor_stock): cancel()

func before_move(delta: float) -> void:
	watchdog()
	if not active(): return
	elapsed += delta
	var f := frame(); var b := beats()
	match phase:
		"draw", "whip":
			if kind == "AIR":
				actor.velocity.y = move_toward(actor.velocity.y + actor.GRAVITY * delta, 0.0, STALL_DECEL * delta)
				actor.velocity.x = move_toward(actor.velocity.x, 0.0, actor.AIR_ACCELERATION * delta)
			else:
				actor.velocity = Vector3.ZERO
			if phase == "draw" and f >= b.snap0: phase = "whip"
			if phase == "whip" and f >= b.latch and not latched: _latch()
			if phase == "whip" and f >= b.kick:
				phase = "reel"; reel_start = actor.global_position
				if kind == "AIR": cushion_origin = _bone_world("LeftToeBase") + Vector3(0, -0.1, 0); cushion_clock = 0.0
		"reel":
			var t := clampf((f - b.kick) / float(b.reel1 - b.kick), 0.0, 1.0)
			var tn := clampf((f + delta * FPS - b.kick) / float(b.reel1 - b.kick), 0.0, 1.0)
			var target := reel_start + reel_vec * (1.0 - pow(1.0 - tn, 2.0))
			actor.velocity = (target - actor.global_position) / maxf(delta, 0.001)
			actor.velocity.z = 0
			if t >= 1.0 or f >= b.reel1: _finish()

func after_move(delta: float) -> void:
	if cushion_clock >= 0.0:
		cushion_clock += delta
	if active(): present()
	_update_cushion()

func _latch() -> void:
	var nut := _nut_world()
	var dir := Vector3(SNAP_DIR.x * facing, SNAP_DIR.y, 0).normalized()
	latch = nut + dir * SNAP_LEN; latch.z = 0
	reel_vec = (latch - nut) - dir * LATCH_SHORT; reel_vec.z = 0
	latched = true

func _finish() -> void:
	completes += 1
	# Apex: vertical speed spent; gravity + normal air control resume. Recovery stays spent.
	actor.velocity = Vector3(actor.velocity.x * 0.2, 0.0, 0.0)
	phase = "idle"; elapsed = 0.0
	_hide_fx(false)
	view.current_clip = "FallLoop"
	view.animation_player.speed_scale = 1.0
	view.animation_player.play("FallLoop", 0.23)
	view.falling = true

func cancel() -> void:
	if not active(): return
	cancels += 1
	phase = "idle"; elapsed = 0.0
	_hide_fx(true)

func _hide_fx(include_cushion: bool) -> void:
	if guitar: guitar.visible = false
	for s in segments: s.visible = false
	if barb: barb.visible = false
	if include_cushion and cushion: cushion.visible = false; cushion_clock = -1.0

func _bone_world(n: String) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_" + n))).origin

func _grip() -> Transform3D:
	var b := beats(); var f := frame()
	var t := clampf((f - b.snap0) / float(b.snap1 - b.snap0), 0.0, 1.0); t = t * t * (3.0 - 2.0 * t)
	var qa := REL_A.basis.get_rotation_quaternion(); var qb := REL_B.basis.get_rotation_quaternion()
	var sc := REL_A.basis.get_scale().lerp(REL_B.basis.get_scale(), t)
	var rel := Transform3D(Basis(qa.slerp(qb, t)).scaled(sc), REL_A.origin.lerp(REL_B.origin, t))
	var hb := skeleton.find_bone("mixamorig_RightHand")
	return skeleton.global_transform * skeleton.get_bone_global_pose(hb) * rel

func _nut_world() -> Vector3:
	skeleton.force_update_all_bone_transforms()
	return _grip() * NUT

func present() -> void:
	if not active(): return
	var b := beats(); var f := frame()
	actor.facing = facing
	actor._visual_root.scale = Vector3.ONE; actor._visual_root.rotation = Vector3.ZERO
	view.model.rotation.y = facing * PI / 2.0
	view.falling = false; view.landing_remaining = 0.0
	var ap: AnimationPlayer = view.animation_player
	# No crossfade: speed_scale is 0 (clip is driven by this clock), so a blend would never advance.
	# Clip frame 0 is already a sample of the native FallLoop/Idle entry pose.
	if view.current_clip != b.clip or ap.assigned_animation != b.clip: ap.play(b.clip, 0.0)
	view.current_clip = b.clip
	ap.speed_scale = 0.0
	ap.seek(minf(f, b.end) / FPS, true)
	skeleton.force_update_all_bone_transforms()
	# guitar pops in over 3 frames
	var gs := clampf(f / 3.0, 0.0, 1.0); gs = gs * gs * (3.0 - 2.0 * gs)
	var gx := _grip()
	guitar.global_transform = Transform3D(gx.basis.scaled_local(Vector3.ONE * maxf(gs, 0.001)), gx.origin)
	guitar.visible = true
	var nut := gx * NUT; var bridge := gx * BRIDGE
	var pts: Array[Vector3] = []
	if f >= 3.0 and f <= b.snap0:
		var w := clampf((f - b.hook0) / float(b.hook1 - b.hook0), 0.0, 1.0); w = w * w * (3.0 - 2.0 * w)
		var rest := bridge + (nut - bridge) * 0.3
		pts = [bridge, rest.lerp(_bone_world("LeftHandIndex3"), w), nut]
		barb.visible = false
	elif f > b.snap0:
		if not latched: _latch_preview(nut)
		var p := clampf((f - b.snap0) / float(b.latch - b.snap0), 0.0, 1.0); var pe := 1.0 - pow(1.0 - p, 3.0)
		var tip := nut + (latch - nut) * pe; var ax := tip - nut
		var axn := ax.normalized() if ax.length() > 0.0001 else Vector3(SNAP_DIR.x * facing, SNAP_DIR.y, 0).normalized()
		var side := Vector3(-axn.y, axn.x, 0); var amp := 0.2 * pow(1.0 - p, 1.5)
		for i in WHIP_POINTS + 1:
			var s := float(i) / WHIP_POINTS
			pts.append(nut + ax * s + side * (amp * sin(s * PI * 3.0 + f * 1.3) * s))
		barb.visible = true
		barb.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, axn)), tip)
	_draw_polyline(pts)

func _latch_preview(nut: Vector3) -> void:
	# Latch point is fixed the first whip frame (matches the Blender audition).
	var dir := Vector3(SNAP_DIR.x * facing, SNAP_DIR.y, 0).normalized()
	latch = nut + dir * SNAP_LEN; latch.z = 0
	reel_vec = (latch - nut) - dir * LATCH_SHORT; reel_vec.z = 0
	latched = true

func _draw_polyline(pts: Array[Vector3]) -> void:
	for i in segments.size():
		var s := segments[i]
		if i + 1 >= pts.size(): s.visible = false; continue
		var a := pts[i]; var c := pts[i + 1]; var d := c - a; var l := d.length()
		if l < 0.0001: s.visible = false; continue
		s.visible = true
		s.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, d / l)).scaled(Vector3(1, l, 1)), (a + c) * 0.5)

func _update_cushion() -> void:
	# Soft single fade (no flashing): expands 0.3 s under the push foot. Visual only, not a platform.
	if cushion_clock < 0.0: cushion.visible = false; return
	var t := cushion_clock / 0.3
	if t >= 1.0: cushion.visible = false; cushion_clock = -1.0; return
	cushion.visible = true
	var r := 0.15 + 0.6 * (1.0 - pow(1.0 - t, 2.0))
	cushion.global_transform = Transform3D(Basis().scaled(Vector3(r, 0.35 * r, r * 0.55)), cushion_origin)
	cushion_mat.albedo_color.a = 0.75 * (1.0 - t)
