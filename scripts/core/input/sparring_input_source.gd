extends RefCounted
## Our deterministic beginner sparring policy, NOT Mikey's repository AI.
## Observation-only input source. All timing is actor-advancing committed ticks.
const Frame = preload("res://scripts/core/input/input_frame.gd")
const LABEL = "Sparring / Easy (ours)"
const REACTION_TICKS = 24
const DECISION_TICKS = 36
const ATTACK_INTERVAL = 120
const BREATH_TICKS = 72
const SPECIAL_INTERVAL = 360
const DEFENSE_INTERVAL = 240
const SHIELD_TICKS = 12
var difficulty := "easy"
var sequence := 0
var age := 0
var _history: Array = []
var _last_tick := -1
var _cached := {}
var _previous := {}
var _axis := Vector2.ZERO
var _next_attack := 0
var _breath_until := 0
var _next_special := 180
var _next_defense := 240
var _shield_until := 0
var _next_recovery := 0

func configure(value: String) -> bool:
	if value != "easy": return false
	reset(); return true

func reset() -> void:
	sequence = 0; age = 0; _history.clear(); _last_tick = -1
	_cached.clear(); _previous.clear(); _axis = Vector2.ZERO
	_next_attack = 0; _breath_until = 0
	_next_special = 180; _next_defense = 240; _shield_until = 0; _next_recovery = 0

func sample(tick: int, fighter: Dictionary, opponents: Array, advance: bool = true) -> Frame:
	if tick < _last_tick: reset()
	if tick == _last_tick: return Frame.from_dict(_cached)
	var frame = Frame.new(); frame.tick = tick; frame.source_id = "sparring_easy"
	if advance:
		_history.append({"own":fighter.duplicate(true),"others":opponents.duplicate(true)})
		if _history.size() > REACTION_TICKS:
			var old: Dictionary = _history.pop_front()
			if (age-REACTION_TICKS) % DECISION_TICKS == 0:
				sequence += 1
				_decide(old.own,old.others,frame)
		if not frame.held.get("attack",false) and not frame.held.get("special",false): frame.axis = _axis if age >= _breath_until else Vector2.ZERO
		if age < _shield_until: frame.held.shield = true
		age += 1
	else:
		# No decision/history/clock advance and no repeated one-shot edge.
		if _previous.get("shield",false): frame.held.shield = true
		frame.axis = _axis if age >= _breath_until else Vector2.ZERO
	for action in ["attack","special","jump","shield"]:
		if frame.held.get(action,false) and not _previous.get(action,false): frame.pressed[action] = true
		if not frame.held.get(action,false) and _previous.get(action,false): frame.released[action] = true
	_previous = frame.held.duplicate()
	_last_tick = tick; _cached = frame.to_dict()
	return frame

func _decide(fighter: Dictionary, opponents: Array, frame: Frame) -> void:
	_axis = Vector2.ZERO
	var bounds := _bounds(fighter.get("stage_bounds",{}))
	var offstage: bool = fighter.position.x < bounds.left or fighter.position.x > bounds.right or fighter.position.y < bounds.top-0.5
	if offstage:
		_breath_until = age # Recovery may interrupt a pause, not attack budget.
		_axis.x = signf((bounds.left+bounds.right)*0.5-fighter.position.x)
		if age >= _next_recovery and fighter.velocity.y <= 1.0 and not fighter.recovery_spent:
			if fighter.can_jump: frame.held.jump = true
			else: frame.held.special = true; frame.axis = Vector2(_axis.x,-1)
			_next_recovery = age+48
		return
	if age < _breath_until: return
	if fighter.position.x > bounds.right-1.0:
		_axis.x = -0.35; return
	if fighter.position.x < bounds.left+1.0:
		_axis.x = 0.35; return
	var target := {}; var nearest := INF
	for other in opponents:
		if other.id == fighter.id or not other.enabled: continue
		if fighter.team >= 0 and fighter.team == other.team: continue
		var distance: float = fighter.position.distance_to(other.position)
		if distance < nearest: target = other; nearest = distance
	if target.is_empty(): return
	var dx: float = target.position.x-fighter.position.x
	var dy: float = target.position.y-fighter.position.y
	if nearest <= 2.4 and target.get("attack_cooldown",0.0)>0.3 and age>=_next_defense:
		_shield_until = age+SHIELD_TICKS; _next_defense=age+DEFENSE_INTERVAL
		_breath_until=age+24
		return
	if nearest > 2.4 and nearest < 5.5 and absf(dy)<0.8 and age>=_next_special and age>=_next_attack:
		frame.held.special = true; frame.axis=Vector2(signf(dx),0)
		_next_special=age+SPECIAL_INTERVAL; _next_attack=age+ATTACK_INTERVAL
		_breath_until=age+BREATH_TICKS
		return
	if nearest <= 2.1 and absf(dy)<0.8 and age >= _next_attack:
		_axis.x = signf(dx) # Legal directional basic, never direct facing write.
		frame.held.attack = true
		_next_attack = age+ATTACK_INTERVAL
		_breath_until = age+BREATH_TICKS
		frame.axis = _axis
		# Keep the direction for this attack only, then release next tick.
		return
	if age % 180 >= 132: return # Explicit periodic pause even when out of reach.
	if absf(dx)>1.5: _axis.x = signf(dx)*0.55

func _bounds(value: Variant) -> Dictionary:
	var fallback := {"left":-8.0,"right":8.0,"top":0.0}
	if not value is Dictionary: return fallback
	for key in ["left","right","top"]:
		if not value.has(key) or typeof(value[key]) not in [TYPE_INT,TYPE_FLOAT]: return fallback
		if not is_finite(value[key]): return fallback
	if value.left >= value.right: return fallback
	return value

