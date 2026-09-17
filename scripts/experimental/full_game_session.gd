extends Node3D
## Frontend adapter only. Match owns all movement, damage, stocks and clocks.
signal finished(result: Dictionary)
var simulation = preload("res://scripts/core/match/match_simulation.gd").new()
var actors: Array = []
var sources: Array = []
var presenters: Array = []
var selected_fighters: Array = ["teknium","turbofit"]
var input_owner := "sparring_easy"
# -1 selects the slot's keyboard bindings; nonnegative IDs select native pads.
var selected_devices: Array = [-1,-1]
## Inventory seam only. Live input sampling still belongs to PlayerInputSource.
var connected_devices: Callable = Input.get_connected_joypads
func device_error() -> String:
	if selected_devices.size() != 2: return "Select one input device per slot."
	var devices: Array = selected_devices.duplicate()
	if sources.size() == 2:
		devices = [sources[0].device,sources[1].device]
	for device in devices:
		if not device is int or device < -1: return "Invalid input device."
	if input_owner == "human" and devices[0] >= 0 and devices[0] == devices[1]:
		return "Human slots must use different controllers."
	var present = connected_devices.call()
	for slot in 2:
		if slot == 1 and input_owner != "human": continue
		if devices[slot] >= 0 and not present.has(devices[slot]):
			return "P%d controller disconnected. Reconnect or select Keyboard." % (slot+1)
	return ""
var paused := false
var error := ""
var effects
var grab_effects
var stage
var inputs
var last_lifecycle := ""
var last_physics := -1
func _ready():
	set_physics_process(false)
	error = preload("res://scripts/experimental/full_game_config.gd").new().validate(selected_fighters,"toy_room",input_owner)
	if not error.is_empty(): return
	error = device_error()
	if not error.is_empty(): return
	stage = preload("res://scripts/experimental/full_game_stage.gd").new()
	add_child(stage)
	effects = preload("res://scripts/experimental/full_game_effects.gd").new()
	add_child(effects)
	grab_effects = preload("res://scripts/experimental/full_game_grab_effects.gd").new()
	add_child(grab_effects)
	var profiles := {}
	for slot in 2:
		var id: String = selected_fighters[slot]
		var base = load("res://data/collision/generated/%s.tres" % id)
		var override = load("res://data/collision/overrides/%s_anatomical_v1.tres" % id)
		if override.provenance.get("generated_profile_sha256","") != FileAccess.get_sha256("res://data/collision/generated/%s.tres" % id):
			error = "Collision profile provenance mismatch: " + id
			return
		var merged: Dictionary = base.merged_with(override)
		if not merged.get("errors",[]).is_empty():
			error = str(merged.errors)
			return
		profiles[slot+1] = merged.profile
		var actor = preload("res://scripts/core/fighter/fighter_actor.gd").new()
		actor.profile = preload("res://data/characters/teknium_movement.tres")
		add_child(actor)
		actors.append(actor)
		simulation.register_actor(slot+1,actor,-1,id)
		var source = preload("res://scripts/core/input/player_input_source.gd").new()
		source.slot = slot
		source.device = selected_devices[slot]
		source.reset()
		sources.append(source)
		var presenter = preload("res://scripts/core/presentation/teknium_presenter.gd").new() if id == "teknium" else preload("res://scripts/core/presentation/turbofit_presenter.gd").new()
		actor.add_child(presenter)
		presenters.append(presenter)
	inputs = preload("res://scripts/core/input/sparring_match_input.gd").new() if input_owner == "sparring_easy" else preload("res://scripts/core/input/repo_ai_match_input.gd").new()
	inputs.configure(2,input_owner != "human","easy" if input_owner in ["human","sparring_easy"] else input_owner.trim_prefix("repo_"))
	inputs.stage_bounds = stage.ai_bounds()
	var rules = preload("res://scripts/core/match/match_rules.gd").new()
	simulation.configure_rules(rules)
	simulation.configure_defense(preload("res://scripts/core/combat/defense_profile.gd").new())
	var hitstop = preload("res://scripts/core/combat/hitstop_profile.gd").new()
	hitstop.direct_hit_ticks = 4
	simulation.configure_hitstop(hitstop)
	simulation.configure_ledges(stage.anchors(),preload("res://scripts/core/stage/ledge_policy.gd").new())
	if not simulation.reset_with_collision_profiles(rules.stage.spawns,profiles,"grounded_jostle"):
		error = str(simulation.collision_install_diagnostics())
		return
	reset_inputs()
	present()
	set_physics_process(true)
func refresh_navigation() -> bool:
	var surfaces: Array = stage.navigation_surfaces()
	if surfaces.size() != 4 or not inputs.configure_navigation(surfaces):
		error = "Stage navigation unavailable: " + stage.navigation_error
		if not has_node("NavigationError"):
			var overlay := CanvasLayer.new(); overlay.name = "NavigationError"; overlay.layer = 100
			add_child(overlay)
			var message := Label.new(); message.name = "Message"
			message.position = Vector2(24,100)
			message.add_theme_color_override("font_color",Color.ORANGE_RED)
			overlay.add_child(message)
		get_node("NavigationError/Message").text = error
		return false
	if has_node("NavigationError"): get_node("NavigationError").free()
	inputs.stage_bounds = stage.ai_bounds()
	error = ""
	return true
func reset_inputs():
	if inputs != null:
		inputs.reset()
		refresh_navigation()
	for i in sources.size():
		sources[i].reset()
		simulation.fighters[i+1].buffer.clear()
		presenters[i].reset()
func set_paused(value: bool):
	paused = value
	reset_inputs()
func rematch():
	simulation.rematch()
	last_lifecycle = ""
	reset_inputs()
	paused = false
	present()
func _physics_process(_delta):
	if paused or not simulation.result.is_empty() or last_physics == Engine.get_physics_frames(): return
	last_physics = Engine.get_physics_frames()
	if not refresh_navigation(): return
	var frames := {}
	for slot in 2:
		if slot == 1 and inputs.enabled: continue
		frames[slot+1] = sources[slot].sample(simulation.tick)
	simulation.simulate(inputs.sample_all(simulation,frames))
	if not simulation.lifecycle_events.is_empty() and simulation.lifecycle_events.back().event_id != last_lifecycle:
		last_lifecycle = simulation.lifecycle_events.back().event_id
		inputs.reset()
		for event in simulation.lifecycle_events:
			if event.kind in ["ko","respawn","eliminated"]:
				var slot: int = event.entity_id-1
				sources[slot].reset()
				presenters[slot].reset()
			if event.kind == "result": reset_inputs()
	present()
	if not simulation.result.is_empty(): finished.emit(simulation.result.duplicate(true))
func present():
	var shots: Array = simulation.projectile_telemetry()
	for id in simulation.fighters:
		var special: Dictionary = simulation.kit_telemetry(id).get("special",{})
		if special.get("move","") == "sound_orb" and special.get("phase","") == "active":
			shots.append({"activation_id":special.activation_id,"kind":"sound_orb","position":simulation.fighters[id].actor.global_position + Vector3.UP,"source":id,"facing":simulation.fighters[id].facing,"opacity":0.16})
	effects.present(shots)
	for slot in actors.size():
		actors[slot].visible = not simulation.fighters[slot+1].eliminated
		presenters[slot].present_canonical(simulation.collision_telemetry(slot+1))
	var relations := []
	for id in simulation.fighters:
		var f: Dictionary = simulation.fighters[id]
		var grab = f.grab
		if grab == null or grab.phase != "hold" or grab.victim == 0: continue
		var victim: Dictionary = simulation.fighters.get(grab.victim,{})
		if victim.is_empty() or victim.caught_by != id or not victim.enabled or victim.frozen: continue
		var skeleton: Skeleton3D = presenters[id-1].skeleton
		var hand := skeleton.find_bone("RightHand")
		if hand < 0: continue
		var start: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(hand) * Vector3(0,19.50612449645996,0)
		relations.append({"activation_id":grab.activation_id,"start":start,"center":victim.actor.global_position+Vector3(0,1.25,0),"elapsed":grab.elapsed})
	grab_effects.present(relations)
func _exit_tree():
	for source in sources:
		source.reset()
		if Input.joy_connection_changed.is_connected(source._on_joy_connection_changed):
			Input.joy_connection_changed.disconnect(source._on_joy_connection_changed)
	for id in simulation.fighters: simulation.set_enabled(id,false)
	simulation.fighters.clear()
