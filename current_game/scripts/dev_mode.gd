extends Node
## DevMode autoload: saved developer settings, match pause ownership and
## training-mode time control (freeze, single-frame step, slow motion).
## Read-only toward fighters: it never changes moves, damage, timing or input.

signal changed

const SETTINGS_PATH := "user://nrcu_settings.cfg"
const SPEEDS := [1.0, 0.5, 0.25]
const LAYERS := {
	"hurtboxes": "Hurtboxes",
	"movement": "Movement capsules",
	"hitboxes": "Attack hitboxes (reported moves)",
	"projectiles": "Projectiles",
	"states": "State labels",
	"hits": "Hit markers + hit log",
	"inputs": "Input display",
	"perf": "Performance",
}

var enabled := false
var layers := {}
var speed_index := 0
var frame := 0            # physics frames advanced while unpaused
var menu_paused := false
var frozen := false
var _step_left := 0
## Hitboxes reported by instrumented moves (v2 hook). Each entry:
## {owner, shape:"sphere"/"capsule", a, b, radius, phase, expires_frame}
var hitboxes: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100000  # run after gameplay so a step is exactly one tick
	for key in LAYERS: layers[key] = key != "perf"
	_load()

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK: return
	enabled = bool(cfg.get_value("dev", "enabled", false))
	for key in LAYERS: layers[key] = bool(cfg.get_value("dev_layers", key, layers[key]))

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("dev", "enabled", enabled)
	for key in LAYERS: cfg.set_value("dev_layers", key, layers[key])
	cfg.save(SETTINGS_PATH)

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		frozen = false
		_step_left = 0
		speed_index = 0
		Engine.time_scale = 1.0
		hitboxes.clear()
	_apply_pause()
	save()
	changed.emit()

func set_layer(key: String, value: bool) -> void:
	layers[key] = value
	save()
	changed.emit()

func is_on(key: String) -> bool:
	return enabled and layers.get(key, false)

# ---- pause ownership -------------------------------------------------------
func set_menu_paused(value: bool) -> void:
	menu_paused = value
	_apply_pause()

func _apply_pause() -> void:
	if not is_inside_tree(): return
	get_tree().paused = menu_paused or (enabled and frozen and _step_left == 0)

func reset_match_state() -> void:
	menu_paused = false
	frozen = false
	_step_left = 0
	hitboxes.clear()
	_apply_pause()

# ---- training-mode time control -------------------------------------------
func toggle_freeze() -> void:
	if not enabled: return
	frozen = not frozen
	_step_left = 0
	_apply_pause()
	changed.emit()

func step_frame() -> void:
	if not enabled or menu_paused: return
	if not frozen:
		frozen = true
		_apply_pause()
		changed.emit()
		return
	_step_left = 1
	_apply_pause()

func cycle_speed() -> void:
	if not enabled: return
	speed_index = (speed_index + 1) % SPEEDS.size()
	Engine.time_scale = SPEEDS[speed_index]
	changed.emit()

func speed_label() -> String:
	return "%d%%" % roundi(SPEEDS[speed_index] * 100)

func _physics_process(_delta: float) -> void:
	if get_tree().paused: return
	frame += 1
	if _step_left > 0:
		_step_left -= 1
		if _step_left == 0: _apply_pause()
	if not hitboxes.is_empty():
		hitboxes = hitboxes.filter(func(h): return h.expires_frame >= frame and is_instance_valid(h.owner))

# ---- v2 hook for moves ------------------------------------------------------
## Call from an attack's contact query. Costs nothing unless Dev Mode shows hitboxes.
## phase: "startup", "active" or "recovery". Lives for `frames` physics ticks.
func report_hitbox(owner: Node, a: Vector3, radius: float, phase := "active", b = null, frames := 1) -> void:
	if not is_on("hitboxes"): return
	hitboxes.append({"owner": owner, "shape": "sphere" if b == null else "capsule", "a": a, "b": a if b == null else b, "radius": radius, "phase": phase, "expires_frame": frame + frames})
