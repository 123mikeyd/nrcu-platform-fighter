extends RefCounted
## Caller-driven shared input owner; no Node, render callback, or gameplay writes.
const AI = preload("res://scripts/core/input/repo_ai_input_source.gd")
const Frame = preload("res://scripts/core/input/input_frame.gd")
var ai = AI.new()
var enabled := true
## Caller-supplied public support-platform geometry: left/right world X, top Y.
## Empty preserves the original oracle; independent of collision interaction arm.
var stage_bounds: Dictionary = {}
const SparringPolicy = preload("res://scripts/core/input/sparring_input_source.gd")
const Navigation = preload("res://scripts/core/input/stage_navigation.gd")
var navigation = Navigation.new()
var _navigation_surfaces: Array = []
var _navigation_ready := false

## Explicit opt-in. Supply all static horizontal world XY boxes, stable IDs,
## one_way flags, before sampling. Empty opts out without altering the oracle.
func configure_navigation(surfaces: Array) -> bool:
	if surfaces == _navigation_surfaces: return true
	var probe = Navigation.new()
	var schema_caps := {"full_jump_speed":1.0,"air_jump_speed":1.0,"air_jumps":0,"gravity":1.0,"air_speed":1.0}
	if not surfaces.is_empty() and not probe.configure(surfaces,schema_caps): return false
	_navigation_surfaces = surfaces.duplicate(true)
	reset()
	return true

func _configure_navigation_actor(actor) -> void:
	_navigation_ready = false
	if _navigation_surfaces.is_empty(): return
	# Match runtime's detached authored tuning, not a guessed roster table.
	var tuning = actor.runtime._tuning
	var caps := {}
	for key in ["full_jump_speed","air_jump_speed","air_jumps","gravity","air_speed"]: caps[key] = tuning.get(key)
	_navigation_ready = navigation.configure(_navigation_surfaces,caps)
var _generation := -1
var _tick := -1
var _physics := -1
var _identity: Array = []
var _frames: Dictionary = {}

func configure(entity_id: int, use_ai: bool, difficulty: String = "normal") -> bool:
	if entity_id != 2 or difficulty not in AI.DIFFICULTIES: return false
	enabled = use_ai
	ai.configure(difficulty)
	reset()
	return true

func reset() -> void:
	ai.reset(); navigation.reset(); _navigation_ready = false
	_generation = -1; _tick = -1; _identity = []; _frames.clear()
	# Keep the physical guard: reset must never permit a second native move.

func _observation(sim, id: int) -> Dictionary:
	var f: Dictionary = sim.fighters[id]
	var r = f.actor.runtime
	var cooldown: float = maxf(0, f.ready_tick - sim.tick) / 60.0
	if f.kit != null:
		var kit: Dictionary = f.kit.snapshot()
		cooldown = maxf(cooldown,kit.get("basic",{}).get("remaining",0.0))
		cooldown = maxf(cooldown,kit.get("special",{}).get("cooldown",0.0))
		cooldown = maxf(cooldown,kit.get("interrupted_cooldown",0.0))
	return {"id":id,"position":f.actor.global_position,"velocity":f.actor.velocity,
		"team":f.team,"enabled":f.enabled and not f.eliminated,"character_id":f.kit_id,
		"attack_cooldown":cooldown,"can_jump":r.grounded or r.air_jumps_left > 0,
		"combat_locked":(f.kit != null and f.kit.locked()) or f.force != null or f.grab != null or f.recovery != null,
		"grounded":r.grounded,"air_jumps_left":r.air_jumps_left,"jump_legal":f.actor.can_accept_jump() and (f.kit == null or not f.kit.locked()),
		"recovery_spent":r.recovery_spent,"magic_locked":f.caught_by != 0 or f.grab != null,
		"magic_cooldown":maxf(0,f.magic_ready_tick-sim.tick)/60.0,"facing":f.facing,
		"stage_bounds":stage_bounds.duplicate(true)}

func sample_all(sim, human_frames: Dictionary = {}) -> Dictionary:
	if _generation != sim.generation:
		reset(); _generation = sim.generation
	if _tick == sim.tick: return _copy_frames(_frames)
	var observations: Array = []
	var ids: Array = sim.fighters.keys(); ids.sort()
	for id in ids:
		var f: Dictionary = sim.fighters[id]
		if is_instance_valid(f.actor) and f.actor.is_inside_tree(): observations.append(_observation(sim,id))
	_frames = {}
	for observation in observations:
		var id: int = observation.id
		var frame = human_frames.get(id,Frame.new())
		if id == 2 and enabled:
			var f: Dictionary = sim.fighters[id]
			var identity: Array = [f.kit_id,f.enabled,f.eliminated,f.stocks]
			if identity != _identity:
				ai.reset(); navigation.reset(); _identity = identity
				_configure_navigation_actor(f.actor)
			if observation.enabled and sim.result.is_empty() and f.kit_id in ["teknium","turbofit"]:
				var sequence_before: int = ai.sequence
				frame = ai.sample(sim.tick,observation,observations,f.hitstop_left <= 0)
				if _navigation_ready:
					var sparring: bool = ai is SparringPolicy
					var allow_start := true
					if sparring: allow_start = ai.age-1 >= ai._breath_until and (ai.age-1) % 180 < 132
					var nav_observation: Dictionary = observation.duplicate(true)
					nav_observation.can_jump = observation.jump_legal
					frame = navigation.adapt(frame,nav_observation,observations,ai.sequence != sequence_before,
						f.hitstop_left <= 0 and not f.frozen,24 if sparring else 0,0.55 if sparring else 1.0,allow_start)
			else: frame = Frame.new(); frame.source_id = "repo_ai"
		_frames[id] = Frame.from_dict(frame.to_dict())
		_frames[id].tick = sim.tick
	_tick = sim.tick
	return _copy_frames(_frames)

func _copy_frames(frames: Dictionary) -> Dictionary:
	var result := {}
	for id in frames: result[id] = Frame.from_dict(frames[id].to_dict())
	return result

func advance(sim, human_sources: Dictionary = {}, paused: bool = false, single_step: bool = false) -> bool:
	if paused and not single_step: return false
	if not sim.result.is_empty() or _physics == Engine.get_physics_frames(): return false
	_physics = Engine.get_physics_frames()
	var humans := {}
	for id in human_sources:
		if id == 2 and enabled: continue
		humans[id] = human_sources[id].sample(sim.tick)
	var before: int = sim.tick
	sim.simulate(sample_all(sim,humans))
	return sim.tick != before
