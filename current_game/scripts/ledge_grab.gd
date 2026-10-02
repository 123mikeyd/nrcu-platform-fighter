extends Node
# Ledge grab MVP (PROVISIONAL, candidate build only; Mike 2026-09-30: "cleared to add ledge grabbing").
# Doge Man, Teknium and TurboFit.
# Clips: Doge ledge v3e (Mike: "much better"). Hands align to the REAL stage edge every tick:
# each clip carries its Blender ledge-edge point in skeleton space, and the fighter origin is placed so
# that point lands on the game ledge corner. The controller owns position; no physics while on the ledge.
const FPS := 30.0
const CONFIG := {
	"doge_man": {
		"view": "DogeVisual",
		"library": "res://assets/doge_man/ledge_v3e_20260930.tres",
		"edge": {"LedgeCatch": Vector3(0, 141.890442, 127.939606), "LedgeHang": Vector3(0, 186.858414, 24.661982), "LedgeClimb": Vector3(0, 180.257172, 19.159782)},
		"catch": [13.0, 45.0, 0.45],   # source frames from..to, gameplay seconds
		"climb": [20.0, 131.0, 1.25],
	},
	# Tek ledge v001 (2026-10-01, PROVISIONAL; Mike: "looks good" on the review, install approved).
	# Same Mixamo sources/frame layout and v3e fingertip method as Doge, retargeted onto Tek's game rig.
	"teknium": {
		"view": "TekniumVisual",
		"library": "res://assets/teknium/ledge_v001_20261001.tres",
		"edge": {"LedgeCatch": Vector3(0, 139.786102, 104.922531), "LedgeHang": Vector3(0, 179.019257, 23.172342), "LedgeClimb": Vector3(0, 175.999557, 21.713602)},
		"catch": [13.0, 45.0, 0.45],
		"climb": [20.0, 131.0, 1.25],
	},
	# TurboFit ledge v001 (2026-10-01, PROVISIONAL; Mike: "sufficient to put into the game and let everyone play with it").
	# Same Mixamo sources and v3e fingertip method; skeleton space is -Z up / +Y back (rig node rotated).
	"turbofit": {
		"view": "TurboFitVisual",
		"library": "res://assets/turbofit/turbofit_ledge_v001_20261001.tres",
		"edge": {"LedgeCatch": Vector3(0, 128.058655, -205.07164), "LedgeHang": Vector3(0, 22.447077, -228.733582), "LedgeClimb": Vector3(0, 21.724012, -228.556351)},
		"catch": [13.0, 45.0, 0.45],
		"climb": [0.0, 131.0, 1.5],
		# Turbo hangs ~0.62 m lower than Tek; 13.0 gives him about the same clearance over the top
		# as Doge/Tek get from LEDGE_JUMP_SPEED (gravity 25 m/s^2).
		"jump_speed": 13.0,
	},
}
const HANG_MAX := 4.0           # auto-drop after this long hanging
const INTANGIBLE := 0.6         # from the grab
const REGRAB_COOLDOWN := 0.6
const GRAB_X := 0.9             # horizontal reach around the hang spot
const GRAB_BELOW := 1.2         # how far below the hang spot a grab still catches
const GRAB_ABOVE := 0.6
const WALL_CLEAR := 0.58        # capsule radius 0.55 + margin: released fighters start outside the stage wall
const JUMP_TOWARD := 3.0
const LEDGE_JUMP_SPEED := 12.5   # hang origin sits ~2.3 m below the top; a normal 10.5 jump cannot clear it
static var occupied := {}

var actor
var view
var skeleton: Skeleton3D
var cfg: Dictionary
var phase := "idle"
var elapsed := 0.0
var hang_time := 0.0
var edge_point := Vector3.ZERO
var side := 1.0                 # +1 = right-hand ledge (fighter hangs at x > edge, faces -1)
var ledge_key := ""
var intangible := 0.0
var cooldown := 0.0
var armed := {}
var assist_hold := -1.0
var jump_assist := 0.0          # after a ledge jump: push toward the stage once he has cleared the top
var stock_at_grab := 0
# telemetry for tests/review
var grabs := 0
var climbs := 0
var drops := 0
var ledge_jumps := 0
var interrupts := 0
var last_event := ""

func _ready() -> void:
	actor = get_parent()
	cfg = CONFIG[actor.character_id]
	view = actor._visual_root.get_node(cfg.view)
	skeleton = view.model.find_children("*", "Skeleton3D", true, false)[0]
	var lib = load(cfg.library)
	var local = view.animation_player.get_animation_library("")
	for clip in lib.get_animation_list():
		var a: Animation = lib.get_animation(clip).duplicate(true)
		a.loop_mode = Animation.LOOP_LINEAR if clip == "LedgeHang" else Animation.LOOP_NONE
		local.add_animation(clip, a)

func active() -> bool:
	return phase != "idle"

func is_intangible() -> bool:
	return active() and intangible > 0.0

func invalid_reason() -> String:
	if not is_instance_valid(actor): return "actor"
	if not actor.controls_enabled: return "controls"
	if actor.stocks <= 0 or actor.stocks != stock_at_grab: return "stocks %d/%d" % [actor.stocks, stock_at_grab]
	if actor.hitstun > 0: return "hitstun %.2f" % actor.hitstun
	if actor.freeze_remaining > 0: return "frozen"
	if actor.sleep_remaining > 0: return "asleep"
	if is_instance_valid(actor.caught_by): return "caught"
	if actor.tumble and actor.tumble.active: return "tumble"
	return ""

func valid_actor() -> bool:
	return is_instance_valid(actor) and actor.controls_enabled and actor.stocks > 0 and actor.stocks == stock_at_grab \
		and actor.hitstun <= 0 and actor.freeze_remaining <= 0 and actor.sleep_remaining <= 0 \
		and not is_instance_valid(actor.caught_by) and not (actor.tumble and actor.tumble.active)

# ---- ledges: solid (non pass-through) stage boxes on layer 1 ----
func ledges() -> Array:
	var out := []
	var root = actor.get_parent()
	if root == null: return out
	for body in root.get_children():
		if not body is StaticBody3D or body.is_in_group("pass_through_platforms") or (body.collision_layer & 1) == 0: continue
		for child in body.get_children():
			if child is CollisionShape3D and not child.disabled and child.shape is BoxShape3D:
				var half: Vector3 = child.shape.size * 0.5
				var c: Vector3 = body.global_transform * child.position
				var top := c.y + half.y
				out.append({"key": "%d:R" % body.get_instance_id(), "edge": Vector3(c.x + half.x, top, 0), "side": 1.0})
				out.append({"key": "%d:L" % body.get_instance_id(), "edge": Vector3(c.x - half.x, top, 0), "side": -1.0})
	return out

# World offset (from the fighter origin) of a clip's ledge-edge point for a facing. Pose-independent.
func edge_offset(clip: String, f: float) -> Vector3:
	var skel_in_model: Transform3D = view.model.global_transform.affine_inverse() * skeleton.global_transform
	var model_t := Transform3D(Basis(Vector3.UP, f * PI / 2), view.model.position)
	var t: Transform3D = view.transform * view.flight_root.transform * model_t * skel_in_model
	return t * cfg.edge[clip]

func hang_spot(edge: Vector3, s: float) -> Vector3:
	var p: Vector3 = edge - edge_offset("LedgeHang", -s)
	p.z = 0
	return p

# ---- called from Fighter._physics_process before tumble; true = this tick is owned by the ledge ----
func tick(delta: float) -> bool:
	cooldown = maxf(0.0, cooldown - delta)
	intangible = maxf(0.0, intangible - delta)
	if not active(): return false
	if not valid_actor():
		interrupts += 1; last_event = "interrupted:" + invalid_reason(); cancel(); return false
	var input: Dictionary = actor.read_controls(delta)
	for k in ["left", "right", "up", "down", "jump", "attack", "special"]:
		if not input[k]: armed[k] = true
	var toward := "left" if side > 0 else "right"
	var away := "right" if side > 0 else "left"
	var fresh := func(k): return input[k] and armed.get(k, false)
	elapsed += delta
	match phase:
		"catch":
			if elapsed >= cfg.catch[2]: phase = "hang"; elapsed = 0.0; hang_time = 0.0
		"hang":
			hang_time += delta
			if fresh.call("jump"): _latch(input); ledge_jump(); return true
			if fresh.call("up") or fresh.call(toward): phase = "climb"; elapsed = 0.0; last_event = "climb"
			elif fresh.call("down") or fresh.call(away) or hang_time >= HANG_MAX:
				_latch(input); drop("drop" if hang_time < HANG_MAX else "timeout"); return true
		"climb":
			if elapsed >= cfg.climb[2]: _latch(input); finish_climb(); return true
	_latch(input)
	present()
	return true

func _latch(input: Dictionary) -> void:
	actor._jump_was_down = input.jump or input.up
	actor._attack_was_down = input.attack
	actor._special_was_down = input.special
	actor._down_was_down = input.down

func source() -> Array:
	match phase:
		"catch": return ["LedgeCatch", lerpf(cfg.catch[0], cfg.catch[1], clampf(elapsed / cfg.catch[2], 0, 1))]
		"climb": return ["LedgeClimb", lerpf(cfg.climb[0], cfg.climb[1], clampf(elapsed / cfg.climb[2], 0, 1))]
	var hang_len: float = view.animation_player.get_animation("LedgeHang").length
	return ["LedgeHang", fmod(hang_time, hang_len) * FPS]

func present() -> void:
	var s = source()
	var clip: String = s[0]
	actor.facing = -side
	actor._visual_root.scale = Vector3.ONE; actor._visual_root.rotation = Vector3.ZERO; actor._visual_root.position = Vector3.ZERO
	view.flight_root.rotation = Vector3.ZERO
	view.model.rotation.y = actor.facing * PI / 2
	var ap: AnimationPlayer = view.animation_player
	if view.current_clip != clip: ap.play(clip, 0)
	view.current_clip = clip
	ap.speed_scale = 0
	ap.seek(float(s[1]) / FPS, true)
	var p: Vector3 = edge_point - edge_offset(clip, actor.facing)
	p.z = 0
	actor.global_position = p
	actor.velocity = Vector3.ZERO
	if actor.crouch_pose: actor.crouch_pose.sync_receivers()

# ---- called from Fighter._physics_process after movement ----
func after_move() -> void:
	if jump_assist > 0.0:
		# Ledge jump: rise beside the wall, then drift onto the stage for a short window.
		# Any held left/right or landing, hit or new move hands control straight back.
		var dt: float = actor.get_physics_process_delta_time()
		var steer: bool = actor._read_raw_controls(0).left or actor._read_raw_controls(0).right
		if actor.hitstun > 0 or actor.is_grounded() or steer or actor.coordinate_state().control_lane() != "input":
			jump_assist = 0.0
		elif actor.global_position.y > edge_point.y + 0.05:
			if assist_hold < 0.0: assist_hold = 0.45
			actor.velocity.x = -side * JUMP_TOWARD
			assist_hold -= dt
			if assist_hold <= 0.0: jump_assist = 0.0
		else:
			jump_assist = maxf(0.0, jump_assist - dt)
	if active() or cooldown > 0.0: return
	if actor.is_grounded() or actor.velocity.y > 0.0 or actor._down_was_down: return
	stock_at_grab = actor.stocks
	if not valid_actor(): return
	var lane: String = actor.coordinate_state().control_lane()
	if lane not in ["input", "special"]: return
	var p: Vector3 = actor.global_position
	for l in ledges():
		if occupied.has(l.key) and is_instance_valid(occupied[l.key]) and occupied[l.key] != self and occupied[l.key].active(): continue
		if (p.x - l.edge.x) * l.side < -0.35: continue          # must be outside (or right at) the edge
		var h := hang_spot(l.edge, l.side)
		var dy := p.y - h.y
		if absf(p.x - h.x) <= GRAB_X and dy >= -GRAB_BELOW and dy <= GRAB_ABOVE:
			grab(l)
			return

func grab(l: Dictionary) -> void:
	actor.cancel_for_grab()
	if actor.air_doge and actor.air_doge.active(): actor.air_doge.cancel()
	if actor.turbofit_snapline and actor.turbofit_snapline.active(): actor.turbofit_snapline.cancel()
	var held: Dictionary = actor._read_raw_controls(0)
	armed.clear()
	for k in held: armed[k] = not held[k]      # anything held at grab time must be re-pressed
	edge_point = l.edge; side = l.side; ledge_key = l.key; occupied[ledge_key] = self
	phase = "catch"; elapsed = 0.0; hang_time = 0.0
	intangible = INTANGIBLE
	actor.reset_air_resources()
	actor.last_move = "LEDGE GRAB"
	grabs += 1; last_event = "grab"
	present()

func _release(reason: String) -> void:
	# Start physics outside the stage wall so the movement capsule never begins inside it.
	var p: Vector3 = actor.global_position
	if (p.x - edge_point.x) * side < WALL_CLEAR: p.x = edge_point.x + side * WALL_CLEAR
	actor.global_position = p
	phase = "idle"; elapsed = 0.0; intangible = 0.0
	if occupied.get(ledge_key) == self: occupied.erase(ledge_key)
	view.current_clip = ""
	last_event = reason

func drop(reason := "drop") -> void:
	_release(reason)
	actor.velocity = Vector3.ZERO
	cooldown = REGRAB_COOLDOWN
	drops += 1

func ledge_jump() -> void:
	_release("ledge_jump")
	actor.velocity = Vector3.ZERO
	actor.jumps_used = 0
	actor.try_jump()
	actor.velocity.y = cfg.get("jump_speed", LEDGE_JUMP_SPEED)
	actor.velocity.x = 0.0
	jump_assist = 0.8; assist_hold = -1.0
	cooldown = REGRAB_COOLDOWN
	ledge_jumps += 1

func finish_climb() -> void:
	# Keep the visible hips where the climb ended, then stand on the stage top in the ordinary Idle.
	var hb := skeleton.find_bone("Hips")
	if hb < 0: hb = skeleton.find_bone("mixamorig_Hips")   # TurboFit's Mixamo rig
	var hips_end: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(hb).origin
	var ap: AnimationPlayer = view.animation_player
	ap.play("Idle", 0); ap.speed_scale = 1; ap.seek(0, true)
	var hips_idle: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(hb).origin
	var p: Vector3 = actor.global_position
	p.x += hips_end.x - hips_idle.x
	var inside: float = edge_point.x - side * 0.6          # never finish hanging over the edge
	if (p.x - inside) * side > 0: p.x = inside
	p.y = edge_point.y + 0.01
	p.z = 0
	if occupied.get(ledge_key) == self: occupied.erase(ledge_key)
	phase = "idle"; elapsed = 0.0; intangible = 0.0
	actor.global_position = p
	actor.velocity = Vector3.ZERO
	view.current_clip = "Idle"
	if cfg.view == "TurboFitVisual":
		# He was falling when he grabbed; without this his visual plays Landing after standing up.
		# The 1 cm drop onto the top would also count as a fall, so snap him onto the floor now.
		view.falling = false; view.landing_remaining = 0.0
		actor.apply_floor_snap()
	climbs += 1; last_event = "climbed"
	actor.last_move = ""

func cancel() -> void:
	jump_assist = 0.0
	if phase == "idle": return
	if occupied.get(ledge_key) == self: occupied.erase(ledge_key)
	phase = "idle"; elapsed = 0.0; intangible = 0.0
	if view: view.current_clip = ""

func _exit_tree() -> void:
	if occupied.get(ledge_key) == self: occupied.erase(ledge_key)
