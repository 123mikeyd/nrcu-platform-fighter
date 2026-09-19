extends RefCounted
## Opt-in, static horizontal support graph. World XY Rect2 end.y is top.
## Only a bounded ground + one air jump envelope; not universal pathfinding.
var _surfaces: Dictionary = {}
var _edges: Dictionary = {}
var _caps: Dictionary = {}
const MARGIN := 0.75
var _history: Array = []
var _goal := ""
var _target := {}
var _leg := {}
var _blocked := {}
var _attempts := {}
var _retry_after := 0
var _age := 0
var _last_jump := false
var _last_down := false

func reset() -> void:
	_history.clear(); _goal = ""; _leg.clear(); _blocked.clear()
	_age = 0; _last_jump = false; _last_down = false; _target.clear()
	_attempts.clear(); _retry_after = 0

func support(position: Vector3) -> String:
	for id in _surfaces:
		var rect: Rect2 = _surfaces[id].rect
		if position.x >= rect.position.x and position.x <= rect.end.x and absf(position.y-rect.end.y) < 0.15:
			return id
	return ""

func adapt(frame, own: Dictionary, others: Array, decision: bool, advancing: bool,
		delay: int = 0, speed: float = 1.0, allow_start: bool = true):
	if not advancing:
		frame.held.jump = _last_jump; frame.held.down = _last_down
		for action in ["jump","down"]:
			frame.pressed.erase(action); frame.released.erase(action)
		return frame
	_age += 1
	_history.append(others.duplicate(true))
	var seen: Array = []
	if _history.size() > delay: seen = _history.pop_front()
	var current := support(own.position)
	if decision and not seen.is_empty():
		var distance := INF; var goal := ""
		_target.clear()
		for other in seen:
			if other.id == own.id or not other.enabled: continue
			if own.team >= 0 and own.team == other.team: continue
			var d: float = own.position.distance_to(other.position)
			if d < distance:
				distance = d; goal = support(other.position); _target = other.duplicate(true)
		if goal != _goal: _blocked.clear(); _attempts.clear(); _retry_after = 0
		_goal = goal
	if not _leg.is_empty() and ((_leg.phase == "align" and _age-_leg.started > 180) or (_leg.phase != "align" and _age-_leg.launched > 120)):
		_fail_leg()
	if not _leg.is_empty() and _leg.phase != "align" and own.grounded and _age-_leg.launched > 8:
		if current != _leg.to: _fail_leg()
		else: _leg.clear()
	if _leg.is_empty() and _age >= _retry_after and decision and allow_start and own.grounded and current != "" and _goal != "" and current != _goal:
		var path := route(current,_goal)
		# Among equally short graph paths, approach the nearest first support.
		# This uses only current self position and the already observed goal.
		var approach := INF
		for neighbor in _edges[current]:
			var tail := route(neighbor,_goal)
			if tail.is_empty() or tail.size()+1 > path.size(): continue
			var bounds: Rect2 = _surfaces[neighbor].rect
			if path.size()>1 and _surfaces[path[1]].rect.end.y > _surfaces[current].rect.end.y and bounds.end.y <= _surfaces[current].rect.end.y: continue
			var distance: float = absf(own.position.x-clampf(own.position.x,bounds.position.x+MARGIN,bounds.end.x-MARGIN))
			if distance < approach:
				path = [current] + tail; approach = distance
		if path.size() > 1 and not _blocked.has(current+">"+path[1]):
			var a: Rect2 = _surfaces[current].rect; var b: Rect2 = _surfaces[path[1]].rect
			var landing := clampf(own.position.x,b.position.x+MARGIN,b.end.x-MARGIN)
			var launch := clampf(landing,a.position.x+MARGIN,a.end.x-MARGIN)
			var drop := b.end.y < a.end.y and landing == launch
			_leg = {"from":current,"to":path[1],"launch":launch,"landing":landing,"drop":drop,
				"phase":"align","started":_age,"launched":_age,
				"double":b.end.y-a.end.y > _caps.full_jump_speed**2/(2*_caps.gravity)-0.4}
	var active := not _leg.is_empty()
	# Defer only voluntary offense for a committed traversal, never an accepted
	# kit episode. The source clocks/budgets still advance, without refunds.
	var reachable: bool = not _target.is_empty() and own.position.distance_to(_target.position) < 2.4
	if active and not reachable and not own.get("combat_locked",false):
		for action in ["attack","special"]:
			frame.held[action] = false
			frame.pressed.erase(action)
			frame.released.erase(action)
	var blocked := current != "" and _goal != "" and current != _goal and not active
	if active or blocked:
		var jump := false; var down := false; var move := 0.0
		if active and (_leg.phase != "align" or allow_start):
			var aim: float = _leg.launch if _leg.phase == "align" else _leg.landing
			# Self-only landing feedback. Target aim is frozen at a sparse decision.
			var dx: float = aim-own.position.x
			move = clampf(dx*2.0-own.velocity.x*0.25,-speed,speed)
			if _leg.phase == "align" and current == _leg.from and own.grounded and absf(dx)<0.16 and absf(own.velocity.x)<0.7 and own.can_jump and not frame.held.get("attack",false) and not frame.held.get("special",false) and not frame.held.get("shield",false):
				_leg.phase = "drop" if _leg.drop else "flight"
				_leg.launched = _age
			if _leg.phase == "drop": down = true
			if _leg.phase == "flight":
				jump = true
				if not own.grounded and own.velocity.y <= 2.0 and _age-_leg.launched > 10 and _leg.double and own.air_jumps_left > 0:
					jump = false; _leg.phase = "air"
			elif _leg.phase == "air":
				jump = own.air_jumps_left == 0 or (own.can_jump and not frame.held.get("attack",false) and not frame.held.get("special",false))
		# Retained combat keeps its source direction; budgets are never refunded.
		if not frame.pressed.get("attack",false) and not frame.pressed.get("special",false) and not frame.held.get("shield",false):
			frame.axis = Vector2(move,1 if down else 0)
		frame.held.jump = jump; frame.held.down = down
	for action in ["jump","down"]:
		var previous: bool = _last_jump if action == "jump" else _last_down
		frame.pressed.erase(action); frame.released.erase(action)
		var held: bool = frame.held.get(action,false)
		if held and not previous: frame.pressed[action] = true
		if not held and previous: frame.released[action] = true
	_last_jump = frame.held.get("jump",false); _last_down = frame.held.get("down",false)
	return frame

func _fail_leg() -> void:
	var key: String = _leg.from+">"+_leg.to
	_attempts[key] = _attempts.get(key,0)+1
	if _attempts[key] >= 3: _blocked[key] = true
	_retry_after = _age+48
	_leg.clear()

func configure(surfaces: Array, capabilities: Dictionary) -> bool:
	reset()
	_surfaces.clear(); _edges.clear(); _caps.clear()
	for key in ["full_jump_speed","air_jump_speed","air_jumps","gravity","air_speed"]:
		if typeof(capabilities.get(key)) not in [TYPE_INT,TYPE_FLOAT]: return false
		if not is_finite(capabilities[key]) or capabilities[key] < 0: return false
	if capabilities.gravity <= 0 or capabilities.air_speed <= 0: return false
	if capabilities.air_jumps > 1: return false
	var copied := {}
	for value in surfaces:
		if not value is Dictionary or not value.get("id") is String or value.id.is_empty(): return false
		if copied.has(value.id) or not value.get("rect") is Rect2 or not value.get("one_way") is bool: return false
		var r: Rect2 = value.rect
		if not r.position.is_finite() or not r.size.is_finite() or r.size.x <= 2*MARGIN or r.size.y <= 0: return false
		copied[value.id] = value.duplicate(true)
	_surfaces = copied; _caps = capabilities.duplicate(true)
	var ids := _surfaces.keys(); ids.sort()
	var height: float = (_caps.full_jump_speed**2 + _caps.air_jump_speed**2 * _caps.air_jumps) / (2*_caps.gravity) - 0.5
	for id in ids:
		_edges[id] = []
		# Ascents before drops makes the upper bridge preferable to falling home.
		for rising in [true,false]:
			for other in ids:
				if id == other: continue
				var a: Rect2 = _surfaces[id].rect; var b: Rect2 = _surfaces[other].rect
				var dy := b.end.y-a.end.y
				if (dy > 0) != rising: continue
				var gap := maxf(0,maxf(b.position.x+MARGIN-(a.end.x-MARGIN),a.position.x+MARGIN-(b.end.x-MARGIN)))
				# Conservative local step; reject long lateral gaps, ceilings/solid tops.
				if rising and _surfaces[other].one_way and dy <= height and gap <= _caps.air_speed*0.4:
					_edges[id].append(other)
				elif dy < 0 and _surfaces[id].one_way and (gap == 0 or (_surfaces[other].one_way and gap <= _caps.air_speed*0.4)):
					_edges[id].append(other)
	return not _surfaces.is_empty()

func route(start: String, goal: String) -> Array:
	if not _edges.has(start) or not _edges.has(goal): return []
	var queue: Array = [[start]]; var visited := {start:true}
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		if path.back() == goal: return path
		for next in _edges[path.back()]:
			if visited.has(next): continue
			visited[next] = true
			queue.append(path + [next])
	return []
