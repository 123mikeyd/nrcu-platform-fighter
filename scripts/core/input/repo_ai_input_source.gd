extends RefCounted
## Derived from scripts/bot_controller.gd at 3950e911df1519c494688b4c79f84b6833bc9b92.
## Decision constants/order retained; no legacy nodes or authority mutations.
## See docs/core-ai-comparison-plan.md for the deliberate compatibility limits.
const Frame = preload("res://scripts/core/input/input_frame.gd")
const DIFFICULTIES = ["easy", "normal", "hard"]
var difficulty := "normal"
var timer := 0.0
var sequence := 0
var intent: Dictionary = {}
var _previous: Dictionary = {}
var _last_tick := -1
var _cached: Dictionary = {}

func reset() -> void:
	timer = 0.0; sequence = 0; intent.clear(); _previous.clear()
	_last_tick = -1; _cached.clear()

func configure(value: String) -> bool:
	if value not in DIFFICULTIES: return false
	difficulty = value
	reset()
	return true

func sample(tick: int, fighter: Dictionary, opponents: Array, advance: bool = true) -> Frame:
	if tick == _last_tick: return Frame.from_dict(_cached)
	var commands: Dictionary
	if advance: commands = read(fighter, opponents, 1.0 / 60.0)
	else: commands = intent
	var frame := Frame.new()
	frame.tick = tick; frame.source_id = "repo_ai"
	frame.axis = Vector2(int(commands.get("right",false))-int(commands.get("left",false)), int(commands.get("down",false))-int(commands.get("up",false)))
	for action in ["jump", "attack", "special", "shield", "down"]:
		frame.held[action] = commands.get(action,false)
		if frame.held[action] and not _previous.get(action,false): frame.pressed[action] = true
		if not frame.held[action] and _previous.get(action,false): frame.released[action] = true
	_previous = frame.held.duplicate()
	_last_tick = tick; _cached = frame.to_dict()
	return frame

func _stage_bounds(value: Variant) -> Dictionary:
	# Optional observation schema: accept all coordinates or use the whole oracle.
	# Do not coerce strings/bools or mix partial geometry with original defaults.
	var fallback := {"left":-8.0,"right":8.0,"top":0.0}
	if not value is Dictionary: return fallback
	for key in ["left","right","top"]:
		if not value.has(key): return fallback
		if typeof(value[key]) not in [TYPE_INT,TYPE_FLOAT]: return fallback
		if not is_finite(value[key]): return fallback
	if value.left >= value.right: return fallback
	return value

func read(fighter: Dictionary, opponents: Array, delta: float) -> Dictionary:
	# Resolve malformed public input before advancing any decision state.
	var bounds := _stage_bounds(fighter.get("stage_bounds",{}))
	timer -= delta
	if timer > 0 and not intent.is_empty(): return intent
	timer = {"easy":0.42,"normal":0.22,"hard":0.10}.get(difficulty,0.22)
	sequence += 1
	intent = {"left":false,"right":false,"up":false,"down":false,"jump":false,"attack":false,"special":false,"shield":false}
	var target: Dictionary = {}
	var nearest := INF
	for other in opponents:
		if other.id == fighter.id or not other.enabled: continue
		if fighter.team >= 0 and other.team >= 0 and fighter.team == other.team: continue
		var distance: float = fighter.position.distance_to(other.position)
		if distance < nearest: nearest = distance; target = other
	# Only validated support geometry participates in stage sensing.
	var left: float = bounds.left
	var right: float = bounds.right
	var top: float = bounds.top
	var offstage: bool = fighter.position.x < left or fighter.position.x > right or fighter.position.y < top - 0.5
	var destination: float = (left + right) * 0.5 if offstage or target.is_empty() else target.position.x
	var dx: float = destination - fighter.position.x
	intent.left = dx < -0.5
	intent.right = dx > 0.5
	if offstage:
		if fighter.velocity.y <= 1.0:
			if fighter.can_jump and not fighter.recovery_spent: intent.jump = sequence % 2 == 1
			elif not fighter.recovery_spent:
				intent.up = true; intent.special = sequence % 2 == 1
	elif not target.is_empty():
		if target.position.y > fighter.position.y + 1.8: intent.jump = sequence % 2 == 1
		if nearest < 2.4:
			intent.attack = sequence % 2 == 1
			intent.up = target.position.y > fighter.position.y + 0.8
			intent.down = target.position.y < fighter.position.y - 0.8
			intent.shield = difficulty == "hard" and target.attack_cooldown > 0.3 and sequence % 4 == 0
			if fighter.character_id == "teknium" and nearest < 1.65 and nearest > 0.6 and not fighter.magic_locked and fighter.magic_cooldown <= 0 and absf(target.position.y - fighter.position.y) < 0.4:
				intent.attack = false; intent.shield = false
				intent.left = false; intent.right = false; intent.up = false; intent.down = false
				# Legacy directly sets facing here. Core must turn through legal input.
				# Reserve one decision for turning before a neutral (grab) cast.
				if fighter.get("facing",signf(dx)) != signf(dx):
					intent.left = dx < 0; intent.right = dx > 0
				else: intent.special = sequence % 6 == 0 and fighter.attack_cooldown <= 0
		elif nearest < 7.0:
			intent.special = sequence % (5 if difficulty == "easy" else 3) == 0
	return intent
