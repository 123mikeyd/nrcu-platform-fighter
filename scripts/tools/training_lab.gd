extends Node3D

const Actor = preload("res://scripts/core/fighter/fighter_actor.gd")
const Frame = preload("res://scripts/core/input/input_frame.gd")
const Buffer = preload("res://scripts/core/input/input_buffer.gd")
const PlayerSource = preload("res://scripts/core/input/player_input_source.gd")
const RecordedSource = preload("res://scripts/core/input/recorded_input_source.gd")
const BotSource = preload("res://scripts/core/input/bot_input_source.gd")
const Overlay = preload("res://scripts/tools/training_overlay.gd")
const PilotProfile = preload("res://data/characters/teknium_movement.tres")

var actors: Array = []
var sources: Array = []
var buffers: Array = []
var recordings: Array = []
var bots: Array = []
var slot_modes: Array[String] = ["Keyboard", "Dummy"]
var spawns: Array[Vector3] = [Vector3(-7, 1, 0), Vector3(7, 1, 0)]
var simulation_tick := 0
var paused := false
var pending_steps := 0
var recording := false
var recording_invalid_reason := ""
var replaying := false
var replay_index := 0
var trace: Array = []
var last_requests: Array[String] = ["Neutral", "Neutral"]
var overlay
var capsule_visuals: Array = []
var imported_visuals: Array = []
var show_models := false
var status_message := "Movement candidate — combat and ledge grabs are not implemented here."
var _publish_elapsed := 0.0

func _notification(what: int) -> void:
    if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
        set_paused(true)
        if recording_invalid_reason.is_empty():
            status_message = "Focus lost: replay suspended without queue changes." if replaying else "Focus lost: paused and buffered inputs cleared. Resume when ready."

func _process(delta: float) -> void:
    if not OS.has_feature("web"): return
    _publish_elapsed += delta
    if _publish_elapsed < 0.05: return
    _publish_elapsed = 0
    # Diagnostic output only: no browser bridge can mutate simulation state.
    JavaScriptBridge.eval("window.__nrcuLab = " + JSON.stringify(get_snapshot()) + ";", true)

func _ready() -> void:
    _build_world()
    for slot in range(2):
        var actor = Actor.new()
        actor.profile = PilotProfile
        actor.name = "CorePlayer%d" % (slot + 1)
        add_child(actor)
        actors.append(actor)
        actor.reset_at(spawns[slot])
        var source = PlayerSource.new()
        source.slot = slot
        source.load_profile("user://core_input_%d.cfg" % slot)
        sources.append(source)
        buffers.append(Buffer.new())
        recordings.append(RecordedSource.new())
        bots.append(BotSource.new())
        _build_actor_visual(actor, slot)
    overlay = Overlay.new()
    overlay.lab = self
    add_child(overlay)

func _physics_process(_delta: float) -> void:
    if not paused:
        _simulate_tick()
    elif pending_steps > 0:
        pending_steps -= 1
        _simulate_tick()

func _simulate_tick() -> void:
    if actors.is_empty(): return
    if replaying and replay_index >= recordings[0].frames.size():
        replaying = false
        set_paused(true)
        status_message = "Replay finished. Reset or resume to take control."
        return
    var sampled: Array = []
    for slot in range(2):
        var frame
        if replaying:
            frame = recordings[slot].sample(simulation_tick)
        elif slot_modes[slot] == "Dummy":
            frame = Frame.new()
            frame.tick = simulation_tick
        elif slot_modes[slot] == "Bot":
            frame = bots[slot].sample(simulation_tick, actors[slot].global_position, actors[1-slot].global_position)
        else:
            frame = sources[slot].sample(simulation_tick)
        sampled.append(frame)
        if recording:
            recordings[slot].record(frame)
    for slot in range(2):
        var frame = sampled[slot]
        var actor = actors[slot]
        var buffer = buffers[slot]
        if not replaying and slot_modes[slot] == "Pad" and not sources[slot].connected:
            _flush_live_queue(slot, "controller disconnect cleared live input queue")
            last_requests[slot] = "Controller disconnected: neutral input / queue flushed"
        buffer.advance(frame)
        var command := {"move_x": float(frame.axis.x), "jump": false,
            "jump_held": bool(frame.held.get("jump", false)),
            "jump_released": bool(frame.released.get("jump", false)),
            "down": false, "shield": bool(frame.held.get("shield", false))}
        if not buffer.peek("jump").is_empty():
            if not command.shield and actor.can_accept_jump():
                buffer.consume("jump")
                command.jump = true
                last_requests[slot] = "Jump accepted @ %d" % simulation_tick
            else:
                last_requests[slot] = "Jump buffered: waiting for legal state"
        if not buffer.peek("down").is_empty():
            if actor.is_on_floor() or actor.velocity.y <= 0:
                buffer.consume("down")
                command.down = true
                last_requests[slot] = "Down request accepted"
        # Combat requests are explicitly rejected in this movement-only milestone.
        for action in ["attack", "special"]:
            if not buffer.peek(action).is_empty():
                buffer.consume(action)
                last_requests[slot] = "%s unavailable: movement lab" % action.capitalize()
        actor.simulate(command)
        if actor.position.y < -9 or absf(actor.position.x) > 19:
            actor.reset_at(spawns[slot])
            buffer.clear()
            sources[slot].reset()
            last_requests[slot] = "Out of bounds: respawn + input flush"
        _sync_visual(slot)
    if replaying: replay_index += 1
    trace.append(get_snapshot())
    if trace.size() > 3600: trace.pop_front()
    simulation_tick += 1

func _invalidate_recording(reason: String) -> void:
    if not recording: return
    recording_invalid_reason = reason
    recording = false
    status_message = "Recording invalid: " + reason + ". Record a new take before replay."

func _flush_live_queue(slot: int, reason: String) -> void:
    if replaying: return
    _invalidate_recording(reason)
    buffers[slot].clear()

func set_paused(value: bool) -> void:
    paused = value
    pending_steps = 0
    for slot in range(sources.size()):
        sources[slot].reset()
        # Resume is not a queue-flush event; playback never flushes simulation.
        if value: _flush_live_queue(slot, "pause cleared live input queues")

func step_once() -> void:
    if paused: pending_steps += 1

func _reset_simulation() -> void:
    simulation_tick = 0
    pending_steps = 0
    replay_index = 0
    trace.clear()
    for slot in range(actors.size()):
        actors[slot].reset_at(spawns[slot])
        sources[slot].reset()
        var window: int = buffers[slot].window_ticks
        buffers[slot] = Buffer.new()
        buffers[slot].window_ticks = window
        if is_instance_valid(imported_visuals[slot]): imported_visuals[slot].reset()
        last_requests[slot] = "Reset: transient state cleared"
        _sync_visual(slot)

func reset_lab() -> void:
    recording = false
    replaying = false
    _reset_simulation()
    status_message = "Reset complete. Existing recording retained until Record is pressed again."

func start_recording() -> void:
    replaying = false
    _reset_simulation()
    for source in recordings: source.frames.clear()
    recording_invalid_reason = ""
    recording = true
    status_message = "Recording both slots from reset. Stop recording before replay."

func stop_recording() -> void:
    recording = false
    if not recording_invalid_reason.is_empty():
        status_message = "Recording invalid: " + recording_invalid_reason + ". Record a new take before replay."
        return
    status_message = "Recorded %d ticks. Replay starts from the same reset state." % recordings[0].frames.size()

func start_replay() -> bool:
    if not recording_invalid_reason.is_empty():
        status_message = "Recording invalid: " + recording_invalid_reason + ". Record a new take before replay."
        return false
    if recordings.is_empty() or recordings[0].frames.is_empty():
        status_message = "Record some movement first."
        return false
    recording = false
    _reset_simulation()
    for source in recordings: source.rewind()
    replaying = true
    status_message = "Replaying recorded intents; live gameplay input ignored."
    return true

func set_slot_mode(slot: int, mode: String, device := -1) -> void:
    if slot < 0 or slot >= sources.size(): return
    if mode not in ["Keyboard", "Pad", "Dummy", "Bot"]: return
    if mode == "Pad" and device < 0: return
    for other in range(sources.size()):
        if other != slot and mode == "Pad" and slot_modes[other] == "Pad" and sources[other].device == device:
            status_message = "That controller is already assigned to P%d." % (other + 1)
            return
    set_paused(true)
    replaying = false
    recording = false
    slot_modes[slot] = mode
    sources[slot].device = device
    sources[slot].reset()
    buffers[slot].clear()
    status_message = "Input assignment changed while paused. Resume when ready."

func rebind_key(slot: int, action: String, physical_key: int) -> bool:
    if slot < 0 or slot >= sources.size() or physical_key <= 0: return false
    if not sources[slot].bindings.has(action): return false
    set_paused(true)
    for other in sources[slot].bindings:
        if other != action and sources[slot].bindings[other] == physical_key:
            status_message = "Key already assigned to %s. Choose another key." % other
            return false
    sources[slot].bindings[action] = physical_key
    sources[slot].reset()
    _flush_live_queue(slot, "key rebind cleared live input queue")
    status_message = "P%d %s bound to %s. Save profiles to keep it." % [slot + 1, action, OS.get_keycode_string(physical_key)]
    return true

func save_profiles() -> void:
    var errors: Array = []
    for slot in range(sources.size()):
        var result = sources[slot].save_profile("user://core_input_%d.cfg" % slot)
        if result != OK: errors.append("P%d: %s" % [slot + 1, error_string(result)])
    status_message = "Profiles saved locally on this device." if errors.is_empty() else "Save failed: " + ", ".join(errors)

func save_trace() -> void:
    var file := FileAccess.open("user://core_movement_trace.json", FileAccess.WRITE)
    if not file:
        status_message = "Could not save trace: " + error_string(FileAccess.get_open_error())
        return
    file.store_string(JSON.stringify({"schema": 1, "physics_hz": 60, "trace": trace}, "  "))
    status_message = "Trace saved to user://core_movement_trace.json (this device)."

func get_snapshot() -> Dictionary:
    var snapshots: Array = []
    for slot in range(actors.size()):
        var data: Dictionary = actors[slot].telemetry().duplicate(true)
        data["position"] = [actors[slot].position.x, actors[slot].position.y, actors[slot].position.z]
        var v: Vector3 = actors[slot].velocity
        data["velocity"] = [v.x, v.y, v.z]
        data["pending"] = buffers[slot].debug_pending()
        data["input_mode"] = slot_modes[slot]
        data["connected"] = sources[slot].connected
        data["last_request"] = last_requests[slot]
        snapshots.append(data)
    return {"tick": simulation_tick, "paused": paused, "recording": recording,
        "replaying": replaying, "actors": snapshots}

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo: return
    match event.physical_keycode:
        KEY_F1: set_paused(not paused)
        KEY_F2: step_once()
        KEY_F3: reset_lab()
        KEY_F4:
            if recording: stop_recording()
            else: start_recording()
        KEY_F5: start_replay()
        _: return
    get_viewport().set_input_as_handled()

func _build_world() -> void:
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("111b2b")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("a3c4df")
    environment.environment.ambient_light_energy = 0.7
    add_child(environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-35, -25, 0)
    light.light_energy = 1.1
    add_child(light)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 20
    camera.position = Vector3(0, 7, 28)
    add_child(camera)
    camera.look_at(Vector3(0, 3, 0))
    camera.current = true
    _platform(Vector3(-7, -0.4, 0), Vector3(10, 0.8, 3), false)
    _platform(Vector3(7, -0.4, 0), Vector3(10, 0.8, 3), false)
    _platform(Vector3(0, 4.0, 0), Vector3(6, 0.3, 2), true)
    _platform(Vector3(-8, 3.0, 0), Vector3(3, 0.3, 2), true)
    _platform(Vector3(8, 3.0, 0), Vector3(3, 0.3, 2), true)
    for x in [-12.0, -2.0, 2.0, 12.0]:
        var marker := MeshInstance3D.new()
        marker.mesh = SphereMesh.new()
        marker.mesh.radius = 0.12
        marker.mesh.height = 0.24
        marker.material_override = _material(Color("ffc369"))
        marker.position = Vector3(x, 0.15, 0)
        marker.add_to_group("core_ledge_markers")
        add_child(marker)
    var label := Label3D.new()
    label.text = "GAP / AUTO RESET BELOW ARENA"
    label.font_size = 26
    label.pixel_size = 0.01
    label.position = Vector3(0, -1.8, 0)
    label.modulate = Color("7f9bb7")
    add_child(label)

func _platform(at: Vector3, size: Vector3, pass_through: bool) -> void:
    var body := StaticBody3D.new()
    body.position = at
    body.collision_layer = 1
    body.collision_mask = 0
    if pass_through:
        body.add_to_group("core_pass_through")
        body.set_meta("top_y", at.y + size.y / 2)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    var mesh := MeshInstance3D.new()
    var box_mesh := BoxMesh.new()
    box_mesh.size = size
    mesh.mesh = box_mesh
    mesh.material_override = _material(Color("527e9a") if pass_through else Color("284355"))
    body.add_child(mesh)
    add_child(body)

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.9
    return material

func _build_actor_visual(actor, slot: int) -> void:
    var mesh := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.38
    capsule.height = 1.8
    mesh.mesh = capsule
    mesh.position.y = 0.9
    mesh.material_override = _material(Color("61e6b3") if slot == 0 else Color("ffb665"))
    actor.add_child(mesh)
    capsule_visuals.append(mesh)
    imported_visuals.append(null)
    var label := Label3D.new()
    label.text = "P%d" % (slot + 1)
    label.font_size = 44
    label.pixel_size = 0.008
    label.position.y = 2.4
    label.modulate = Color("61e6b3") if slot == 0 else Color("ffb665")
    actor.add_child(label)

func set_models_visible(value: bool) -> void:
    show_models = value
    for slot in range(actors.size()):
        if value and not is_instance_valid(imported_visuals[slot]):
            var visual = load("res://scripts/core/presentation/teknium_presenter.gd").new()
            actors[slot].add_child(visual)
            imported_visuals[slot] = visual
        capsule_visuals[slot].visible = not value
        if is_instance_valid(imported_visuals[slot]): imported_visuals[slot].visible = value
        _sync_visual(slot)
    status_message = "P3 Teknium: source clips + TEMP rise/fall/land/turn pose fallbacks; no combat." if value else "Capsule view: inspect movement without animation bias."

func _sync_visual(slot: int) -> void:
    if not is_instance_valid(imported_visuals[slot]): return
    var actor = actors[slot]
    var data: Dictionary = actor.telemetry().duplicate(true)
    if absf(actor.velocity.x) >= 0.05:
        data["facing"] = -1.0 if actor.velocity.x < 0 else 1.0
    imported_visuals[slot].present(data, actor.runtime.tick)
